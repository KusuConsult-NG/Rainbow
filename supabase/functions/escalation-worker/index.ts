import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.16.0";

/**
 * Escalation worker.
 *
 * Drives the SLA escalation engine ported from the Firestore Cloud Functions
 * (escalateTask / escalationWatchdog / triggerSLASweep). It does two things per
 * invocation:
 *
 *   1. Calls run_escalation_cycle() — all tier and SLA logic lives in the
 *      database, where it is transactional and cannot half-apply.
 *   2. Drains notification_outbox and sends the queued pushes, because a
 *      database function cannot make outbound HTTP calls.
 *
 * Intended to run every minute. If pg_cron is enabled, phase6 already schedules
 * the SQL half directly and this worker only needs to drain the outbox; where
 * pg_cron is unavailable, invoking this endpoint on a schedule runs both.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") || "";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") || "";
// One scheme across all three senders. `Key` is correct for current OneSignal
// REST keys; a project still on a legacy key sets ONESIGNAL_AUTH_SCHEME=Basic.
const ONESIGNAL_AUTH_SCHEME = (Deno.env.get("ONESIGNAL_AUTH_SCHEME") || "Key").trim();

/** Give up on a notification after this many failed sends. */
const MAX_ATTEMPTS = 5;
/** Cap per invocation so one backlog cannot stall the whole cycle. */
const OUTBOX_BATCH = 50;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const JSON_HEADERS = { ...CORS_HEADERS, "Content-Type": "application/json" };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

interface OutboxRow {
  id: string;
  alert_id: string | null;
  target_tier: string | null;
  target_lga: string | null;
  target_ward: string | null;
  target_pu: string | null;
  title: string;
  body: string;
  payload: Record<string, unknown>;
  attempts: number;
}

/**
 * Roles that staff a given command tier.
 *
 * Mirrors sendPushToTier from the Firestore original, including its tolerance
 * for the several spellings the role column has accumulated.
 */
function rolesForTier(tier: string): string[] {
  switch (tier.toUpperCase()) {
    case "HQ":
      return ["HQ_OFFICER", "HQ_COMMAND"];
    case "LGA":
      return ["LGA_OFFICER", "LGA_COMMAND"];
    case "WARD":
      return ["WARD_OFFICER", "WARD_COMMAND"];
    default:
      return ["POLLING_UNIT_OFFICER", "POLLING_OFFICER", "UNIT_COMMAND"];
  }
}

/**
 * Resolves the OneSignal subscription ids for one queued notification.
 *
 * Below HQ the recipients are narrowed to the matching jurisdiction, so a ward
 * escalation in Jos North does not buzz every ward officer in the state. HQ is
 * always copied on a CRITICAL incident, as in the original.
 */
async function resolveRecipients(
  supabase: ReturnType<typeof createClient>,
  row: OutboxRow,
): Promise<string[]> {
  const tier = (row.target_tier || "POLLING_UNIT").toUpperCase();
  const ids = new Set<string>();

  const { data: staff, error } = await supabase
    .from("profiles")
    .select("onesignal_player_id, role, geo_lga, geo_ward, geo_pu")
    .in("role", rolesForTier(tier))
    .not("onesignal_player_id", "is", null);

  if (error) {
    console.error("[ESCALATION_WORKER] profile lookup failed:", error.message);
    return [];
  }

  for (const p of staff ?? []) {
    const pid = p.onesignal_player_id as string | null;
    if (!pid || pid.trim().length === 0) continue;

    if (tier === "HQ") {
      ids.add(pid);
    } else if (tier === "LGA") {
      if (!row.target_lga || p.geo_lga === row.target_lga) ids.add(pid);
    } else if (tier === "WARD") {
      if (!row.target_ward || p.geo_ward === row.target_ward) ids.add(pid);
    } else {
      if (!row.target_pu || p.geo_pu === row.target_pu) ids.add(pid);
    }
  }

  if (String(row.payload?.severity ?? "").toUpperCase() === "CRITICAL" && tier !== "HQ") {
    const { data: hq } = await supabase
      .from("profiles")
      .select("onesignal_player_id")
      .in("role", rolesForTier("HQ"))
      .not("onesignal_player_id", "is", null);
    for (const p of hq ?? []) {
      const pid = p.onesignal_player_id as string | null;
      if (pid && pid.trim().length > 0) ids.add(pid);
    }
  }

  return [...ids];
}

async function sendPush(row: OutboxRow, playerIds: string[]): Promise<void> {
  const res = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      Authorization: `${ONESIGNAL_AUTH_SCHEME} ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      include_player_ids: playerIds,
      headings: { en: row.title },
      contents: { en: row.body },
      data: row.payload,
    }),
  });

  if (!res.ok) {
    throw new Error(`OneSignal ${res.status}: ${await res.text()}`);
  }
}

/** Sends every pending notification, marking each row with its outcome. */
async function drainOutbox(
  supabase: ReturnType<typeof createClient>,
): Promise<{ sent: number; failed: number; skipped: number }> {
  const { data: rows, error } = await supabase
    .from("notification_outbox")
    .select("*")
    .eq("status", "PENDING")
    .lt("attempts", MAX_ATTEMPTS)
    .order("created_at", { ascending: true })
    .limit(OUTBOX_BATCH);

  if (error) {
    console.error("[ESCALATION_WORKER] outbox read failed:", error.message);
    return { sent: 0, failed: 0, skipped: 0 };
  }

  let sent = 0, failed = 0, skipped = 0;

  for (const row of (rows ?? []) as OutboxRow[]) {
    try {
      const playerIds = await resolveRecipients(supabase, row);

      if (playerIds.length === 0) {
        // Nobody to tell. Close the row rather than retrying forever — the
        // escalation itself is already recorded in alert_timeline.
        await supabase
          .from("notification_outbox")
          .update({
            status: "NO_RECIPIENTS",
            attempts: row.attempts + 1,
            delivered_at: new Date().toISOString(),
          })
          .eq("id", row.id);
        skipped++;
        continue;
      }

      if (!ONESIGNAL_REST_API_KEY || !ONESIGNAL_APP_ID) {
        throw new Error("ONESIGNAL_APP_ID / ONESIGNAL_REST_API_KEY not configured");
      }

      await sendPush(row, playerIds);

      await supabase
        .from("notification_outbox")
        .update({
          status: "DELIVERED",
          attempts: row.attempts + 1,
          delivered_at: new Date().toISOString(),
          last_error: null,
        })
        .eq("id", row.id);
      sent++;
    } catch (e) {
      const attempts = row.attempts + 1;
      const message = (e as Error).message.slice(0, 500);
      console.error(`[ESCALATION_WORKER] send failed for ${row.id}:`, message);
      await supabase
        .from("notification_outbox")
        .update({
          // Left PENDING so the next cycle retries, until MAX_ATTEMPTS.
          status: attempts >= MAX_ATTEMPTS ? "FAILED" : "PENDING",
          attempts,
          last_error: message,
        })
        .eq("id", row.id);
      failed++;
    }
  }

  return { sent, failed, skipped };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // Fail closed. This endpoint escalates live emergencies and sends pushes to
  // every responder in a jurisdiction; it must never be open.
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (!cronSecret) {
    console.error("[ESCALATION_WORKER] CRON_SECRET is not set — refusing.");
    return json({ error: "Endpoint not configured" }, 503);
  }
  const auth = req.headers.get("authorization") || req.headers.get("x-cron-secret");
  if (auth !== `Bearer ${cronSecret}` && auth !== cronSecret) {
    return json({ error: "Unauthorized caller" }, 401);
  }

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("[ESCALATION_WORKER] Supabase service credentials missing.");
    return json({ error: "Server not configured" }, 503);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const { data: cycle, error: cycleErr } = await supabase.rpc("run_escalation_cycle");
    if (cycleErr) throw new Error(`run_escalation_cycle: ${cycleErr.message}`);

    const outbox = await drainOutbox(supabase);

    console.log(
      `[ESCALATION_WORKER] cycle=${JSON.stringify(cycle)} outbox=${JSON.stringify(outbox)}`,
    );
    return json({ success: true, cycle, outbox });
  } catch (e) {
    console.error("[ESCALATION_WORKER]", e);
    return json({ error: (e as Error).message }, 500);
  }
});
