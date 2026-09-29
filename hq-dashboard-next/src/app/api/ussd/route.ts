/**
 * The USSD gateway callback.
 *
 * One HTTP request per screen. The aggregator POSTs the session, the caller's
 * MSISDN and their latest keypress; this answers with the next screen and
 * whether the session continues.
 *
 * ## Everything here is shaped by two facts
 *
 * **The session has seconds.** Gateways commonly allow 10–20s per screen. So the
 * work per request is bounded and deliberate: at most one identity lookup, one
 * session read, the reducer (which is pure and does no I/O), and one write. The
 * caller's account is created only on the request that actually files a report,
 * never speculatively while somebody is still reading a menu.
 *
 * **A timeout is answered with a retry, not an error.** The gateway re-POSTs the
 * same session with the same keypress. Two things make that harmless: the cached
 * screen below, which answers a repeat without re-running anything, and
 * `ussd_file_report()`, which holds the session row's lock and returns the
 * report it already filed. The cache is the fast path; the lock is the one that
 * is actually correct under concurrency.
 *
 * ## What it never does
 *
 * It does not tell the caller a unit is coming, and the status screen carries no
 * unit, position or ETA — see ussd-menu.ts. And a report filed here is held out
 * of the escalation ladder until a named officer confirms it
 * (20261011000000), because USSD is the cheapest way to lure responders to a
 * chosen place and no timer may do that on its own.
 */

import { NextRequest } from 'next/server';
import { timingSafeEqual } from 'node:crypto';

import { getSupabaseAdmin } from '@/lib/supabase-server';
import { plateauTacticalMap } from '@/lib/tactical_mapping';
import {
  INITIAL_STATE,
  type UssdCaller,
  type UssdState,
  filedScreen,
  filingFailedScreen,
  lastReportScreen,
  ussdTurn,
} from '@/lib/ussd-menu';
import { type ReplyFormat, normalise, renderReply } from '@/lib/ussd-gateway';

/** The reply convention the aggregator expects. See ussd-gateway.ts. */
const FORMAT: ReplyFormat =
  (process.env.USSD_REPLY_FORMAT ?? 'AT_TEXT') === 'JSON' ? 'JSON' : 'AT_TEXT';

const PLACES = {
  lgas: plateauTacticalMap.map(l => l.name),
  wardsFor: (lga: string) =>
    plateauTacticalMap.find(l => l.name === lga)?.wards.map(w => w.name) ?? [],
};

function reply(screen: string, terminal: boolean) {
  const { body, contentType } = renderReply(screen, terminal, FORMAT);
  return new Response(body, { status: 200, headers: { 'content-type': contentType } });
}

/**
 * What a caller sees when this endpoint cannot do its job.
 *
 * Always a terminating screen that names an alternative, never a menu. A person
 * left on a dead menu presses keys until the session times out; a person told to
 * ring 112 can act. And never an HTTP error: a gateway that sees one shows the
 * handset a carrier error page with no words of ours on it at all.
 */
const unavailable = () =>
  reply('Service unavailable. If this is life-threatening, call 112.', true);

function secretMatches(provided: string | null, expected: string): boolean {
  if (!provided || !expected) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  // timingSafeEqual throws on a length mismatch, which would leak the length.
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export async function POST(req: NextRequest) {
  const expected = process.env.USSD_GATEWAY_SECRET ?? '';
  if (!expected) {
    // Refusing to run unconfigured rather than accepting anything that arrives.
    // An open USSD endpoint lets anybody inject emergencies with a forged
    // MSISDN, which removes the one thing this channel's trust rests on: that
    // the CARRIER asserted the number.
    console.error('[USSD] USSD_GATEWAY_SECRET is not set — refusing');
    return unavailable();
  }
  if (!secretMatches(req.headers.get('x-gateway-secret'), expected)) {
    console.warn('[USSD] rejected: gateway secret');
    return unavailable();
  }

  let raw: Record<string, unknown>;
  try {
    const ct = req.headers.get('content-type') ?? '';
    if (ct.includes('application/x-www-form-urlencoded')) {
      // Africa's Talking and several carrier integrations post a form, not JSON.
      // Reading only JSON here would fail every single callback.
      raw = Object.fromEntries(new URLSearchParams(await req.text()));
    } else {
      raw = (await req.json()) as Record<string, unknown>;
    }
  } catch {
    console.warn('[USSD] rejected: unreadable body');
    return unavailable();
  }

  const parsed = normalise(raw);
  if (!parsed.ok) {
    // The field names are wrong for this aggregator. Logged loudly with the keys
    // that DID arrive, because this is a provisioning mistake that otherwise
    // presents as "the menu restarts every time" with nothing to go on.
    console.error(
      `[USSD] rejected: ${parsed.reason}. keys seen: ${Object.keys(raw).join(', ')}`,
    );
    return unavailable();
  }
  const { sessionId, msisdn, input } = parsed.request;
  const supabase = getSupabaseAdmin();

  // ── The session ─────────────────────────────────────────────────────────
  const { data: session, error: sessionErr } = await supabase
    .from('ussd_sessions')
    .select('state, last_input, last_screen, filed_alert')
    .eq('session_id', sessionId)
    .maybeSingle();

  if (sessionErr) {
    console.error('[USSD] session read failed', sessionErr);
    return unavailable();
  }

  // A retry of the keypress we have already answered. Answered from the cache
  // without re-running anything — including, importantly, without asking the
  // database to file anything again.
  if (session && session.last_screen && session.last_input === input) {
    console.warn(`[USSD] ${sessionId}: repeat of input "${input}", replaying`);
    return reply(session.last_screen, Boolean(session.filed_alert));
  }

  if (!session) {
    const { error } = await supabase
      .from('ussd_sessions')
      .insert({ session_id: sessionId, msisdn, state: INITIAL_STATE });
    if (error) {
      console.error('[USSD] could not open the session', error);
      return unavailable();
    }
  }

  // ── Who is dialling ─────────────────────────────────────────────────────
  const { data: callerRows } = await supabase.rpc('ussd_caller', { p_msisdn: msisdn });
  const known = Array.isArray(callerRows) && callerRows.length > 0
    ? (callerRows[0] as { user_id: string; geo_lga: string | null; geo_ward: string | null })
    : null;

  const caller: UssdCaller = {
    msisdn,
    known: Boolean(known),
    geoLga: known?.geo_lga ?? null,
    geoWard: known?.geo_ward ?? null,
  };

  const state: UssdState = (session?.state as UssdState | null) ?? INITIAL_STATE;
  const turn = ussdTurn(state, input, caller, PLACES);

  // ── Whatever the reducer asked for ──────────────────────────────────────
  let screen = turn.screen;
  let terminal = turn.terminal;

  if (turn.action.type === 'lookup_last') {
    const { data, error } = await supabase.rpc('ussd_last_report', { p_msisdn: msisdn });
    if (error) {
      console.error('[USSD] last-report lookup failed', error);
      // Not "no report found": that would tell somebody their emergency was
      // never recorded, which is a different and much worse claim than "we
      // could not read it just now".
      screen = 'Could not check that just now. Please dial again.';
    } else {
      const row = Array.isArray(data) && data.length > 0
        ? (data[0] as { reference: string; kind: string; status: string; age_minutes: number })
        : null;
      screen = lastReportScreen(
        row
          ? {
              reference: row.reference,
              kind: row.kind,
              status: row.status,
              ageMinutes: row.age_minutes,
            }
          : null,
      );
    }
  }

  if (turn.action.type === 'file') {
    const { kind, emergency, lga, ward, callback } = turn.action;

    // The account is created HERE, on the request that files — not while the
    // caller was still reading menus. Somebody who dials, looks and hangs up
    // should leave no account behind.
    //
    // Through the Admin API rather than SQL: `auth.users` is Supabase's table
    // and its required columns have changed across releases, so a migration
    // that hand-inserts into it works in staging and fails on an upgrade.
    let reporter: string | null = known?.user_id ?? null;
    if (!reporter) {
      reporter = await selfRegister(supabase, msisdn, lga, ward);
    }

    const { data, error } = await supabase.rpc('ussd_file_report', {
      p_session_id: sessionId,
      p_msisdn: msisdn,
      p_reporter: reporter,
      p_type: kind,
      p_emergency: emergency,
      p_lga: lga ?? null,
      p_ward: ward ?? null,
      p_callback: callback,
    });

    const row = Array.isArray(data) && data.length > 0
      ? (data[0] as { reference: string; alert_id: string; already_filed: boolean })
      : null;

    if (error || !row) {
      // NOT SENT, with no reference and no reassurance. Somebody who believes
      // their report went through stops trying.
      console.error(`[USSD] ${sessionId}: filing failed`, error);
      screen = filingFailedScreen();
    } else {
      if (row.already_filed) {
        console.warn(`[USSD] ${sessionId}: filing was a retry, same ref ${row.reference}`);
      } else {
        console.warn(
          `[USSD] ${sessionId}: filed ${row.reference} (${emergency ? 'EMERGENCY' : 'report'})`,
        );
      }
      screen = filedScreen(row.reference, emergency);
    }
    terminal = true;
  }

  // ── Remember where we are ───────────────────────────────────────────────
  const { error: saveErr } = await supabase
    .from('ussd_sessions')
    .update({
      state: turn.state,
      last_input: input,
      last_screen: screen,
      updated_at: new Date().toISOString(),
    })
    .eq('session_id', sessionId);

  if (saveErr) {
    // The screen is still correct and the caller still gets it. Only the retry
    // cache is lost, and `ussd_file_report()`'s lock covers the case that
    // matters, so this is worth a log and not worth failing the session over.
    console.error('[USSD] could not save the session state', saveErr);
  }

  return reply(screen, terminal);
}

/**
 * Give a caller an account, on the strength of the number the carrier asserted.
 *
 * This is the registration answer for USSD, and it needs no OTP. The app onboards
 * with phone + SMS OTP, which proves somebody could read a code sent to that
 * SIM; USSD proves the same thing more directly, because the MSISDN arrives in
 * the session metadata from the network rather than from anything the user typed.
 * There is no code to phish or forward.
 *
 * What it creates is deliberately thin: a CITIZEN with a proven-reachable number
 * and, if they chose one, an area. No name, and no claim about who they are.
 *
 * A failure here does NOT stop the report. An unattributed emergency is worth
 * far more than a tidy `reported_by`, and `reporter_msisdn` on the alert keeps
 * the reachable number regardless.
 */
async function selfRegister(
  supabase: ReturnType<typeof getSupabaseAdmin>,
  msisdn: string,
  lga?: string,
  ward?: string,
): Promise<string | null> {
  try {
    const { data, error } = await supabase.auth.admin.createUser({
      phone: msisdn.replace(/^\+/, ''),
      phone_confirm: true,
      user_metadata: { registered_via: 'USSD' },
    });
    if (error || !data?.user) {
      console.error('[USSD] self-registration failed', error);
      return null;
    }
    const { error: profileErr } = await supabase.from('profiles').insert({
      id: data.user.id,
      phone: msisdn,
      role: 'CITIZEN',
      geo_lga: lga ?? null,
      geo_ward: ward ?? null,
    });
    if (profileErr) {
      // The auth user exists without a profile. RLS reads `profiles`, so this
      // account can do nothing at all — which is the safe direction, and the
      // report below is still filed with its MSISDN.
      console.error('[USSD] profile insert failed after self-registration', profileErr);
      return null;
    }
    console.warn(`[USSD] registered a new citizen from ${msisdn}`);
    return data.user.id;
  } catch (e) {
    console.error('[USSD] self-registration threw', e);
    return null;
  }
}
