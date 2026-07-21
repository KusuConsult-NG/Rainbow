import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.16.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") || "885be8b2-5f31-4627-a618-685f54dd266a";
const ONESIGNAL_REST_API_KEY =
  Deno.env.get("ONESIGNAL_REST_API_KEY") ||
  "os_v2_app_rbn6rms7gfdcpjqynbpvjxjgnimvyuzlhkxe36nxbisp7qaxnoqml67czqs6gmmxvs7j3rbzmplqr7ucsijpw4zyvmkphyufoi6f4pa";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const webhookSecret = Deno.env.get("WEBHOOK_SECRET");
    if (webhookSecret) {
      const authHeader = req.headers.get("authorization") || req.headers.get("x-webhook-secret");
      if (authHeader !== `Bearer ${webhookSecret}` && authHeader !== webhookSecret) {
        return new Response(JSON.stringify({ error: "Unauthorized caller" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    const payload = await req.json();
    const record = payload.record || payload;

    if (!record || !record.id) {
      return new Response(JSON.stringify({ error: "Missing alert record payload" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Query field responders / command staff with registered OneSignal Player IDs
    const { data: agents, error } = await supabase
      .from("profiles")
      .select("onesignal_player_id, id, full_name, role")
      .neq("role", "CITIZEN")
      .not("onesignal_player_id", "is", null);

    if (error) {
      console.error("Supabase query error:", error);
    }

    const playerIds = (agents || [])
      .map((a: { onesignal_player_id?: string }) => a.onesignal_player_id)
      .filter((id?: string) => id && id.trim().length > 0);

    const category = record.category || "EMERGENCY";
    const severity = record.severity || "CRITICAL";
    const lga = record.geo_lga || "PLATEAU STATE";

    // Prepare OneSignal Push Notification Body
    const notificationBody = {
      app_id: ONESIGNAL_APP_ID,
      headings: { en: `🚨 ${severity} ALERT: ${category.toUpperCase()}` },
      contents: { en: `Location: ${lga}. Immediate responder dispatch required.` },
      data: {
        alert_id: record.id,
        category: category,
        severity: severity,
        latitude: record.latitude,
        longitude: record.longitude,
      },
      // Target specific player IDs if present, or send to all active subscriptions
      ...(playerIds.length > 0 ? { include_player_ids: playerIds } : { included_segments: ["Active Users"] }),
    };

    // Dispatch to OneSignal REST API
    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Authorization: `Key ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify(notificationBody),
    });

    const resData = await response.json();

    return new Response(
      JSON.stringify({
        success: response.ok,
        alert_id: record.id,
        notified_devices: playerIds.length,
        onesignal_response: resData,
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
