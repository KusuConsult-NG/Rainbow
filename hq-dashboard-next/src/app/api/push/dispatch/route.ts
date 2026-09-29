import { NextResponse } from 'next/server';
import { getSupabaseAdmin, requireRole, COMMAND_ROLES } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';
import { postNotification } from '@/lib/onesignal-auth';

export async function POST(request: Request) {
  try {
    // Authorise BEFORE any work. This route previously ran its full dispatch logic
    // for completely unauthenticated callers.
    const auth = await requireRole(COMMAND_ROLES);
    if (!auth.ok) {
      return NextResponse.json({ error: auth.error }, { status: auth.status });
    }

    // Parse separately so malformed JSON is a 400, not a 500 echoing the parser message.
    let body: { alertId?: unknown; responderUids?: unknown; kind?: unknown };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: 'Malformed JSON body' }, { status: 400 });
    }

    const { alertId, responderUids, kind } = body as {
      alertId?: string; responderUids?: string[]; kind?: string;
    };

    // A stand-down and a dispatch carry OPPOSITE instructions, so they must not
    // share a message. An officer taken off an incident used to be told
    // nothing at all; telling them "report immediately" would be worse than
    // that. Anything other than the exact token is treated as a dispatch —
    // defaulting an unrecognised value to "stand down" could silently cancel a
    // real deployment.
    const isStandDown = kind === 'STAND_DOWN';

    if (!alertId || !responderUids || !Array.isArray(responderUids) || responderUids.length === 0) {
      return NextResponse.json({ error: 'Invalid payload: alertId and responderUids array required' }, { status: 400 });
    }

    // Client constructed here, not at module scope — a module-scope createClient()
    // with missing env crashed `next build` during page-data collection.
    const supabase = getSupabaseAdmin();

    // 1. Fetch OneSignal Player IDs for target officer profiles
    const { data: profiles, error: dbErr } = await supabase
      .from('profiles')
      .select('id, onesignal_player_id, full_name')
      .in('id', responderUids);

    if (dbErr) {
      console.error('[PUSH_API_DB_ERR]', dbErr);
      return NextResponse.json({ error: 'Database error fetching officer profiles' }, { status: 500 });
    }

    const playerIds = (profiles || [])
      .map(p => p.onesignal_player_id)
      .filter((id): id is string => Boolean(id && id.length > 5));

    if (playerIds.length === 0) {
      return NextResponse.json({ 
        success: true, 
        message: 'No registered OneSignal push subscription IDs found for selected officers', 
        notifiedCount: 0 
      });
    }

    // 2. Dispatch push notification via OneSignal REST API
    const { oneSignalAppId, oneSignalRestKey } = serverEnv();

    if (!oneSignalAppId || !oneSignalRestKey) {
      console.warn('[PUSH_API_WARN] OneSignal REST API Key not configured. Push skipped.');
      return NextResponse.json({ 
        success: true, 
        message: 'OneSignal REST API Key unconfigured in server environment', 
        notifiedCount: 0 
      });
    }

    // The scheme is decided in ONE place now, and a refused credential is retried
    // under the other one. This route sent `Basic` while
    // supabase/functions/notify-alert sent `Key` for the SAME key, so at least
    // one of them had never authenticated. See lib/onesignal-auth.ts.
    const outcome = await postNotification(
      oneSignalRestKey,
      {
        app_id: oneSignalAppId,
        include_player_ids: playerIds,
        headings: { en: isStandDown ? '🛑 STAND DOWN' : '⚡ TACTICAL MISSION DISPATCH' },
        contents: {
          en: isStandDown
            ? `You have been STOOD DOWN from Emergency Incident #${alertId.substring(0, 8)}. Do not proceed. Await further orders.`
            : `You have been dispatched to Emergency Incident #${alertId.substring(0, 8)}. Report immediately.`,
        },
        data: { alertId, type: isStandDown ? 'STAND_DOWN' : 'DISPATCH' },
      },
      { configuredScheme: process.env.ONESIGNAL_AUTH_SCHEME },
    );

    if (!outcome.ok) {
      // This used to return `{ success: true, notifiedCount: N }` WITHOUT looking
      // at response.ok, so a 401 from OneSignal was reported to the console as N
      // notifications delivered. A dispatcher believed a stand-down had reached a
      // team that never heard it.
      //
      // 200 with success:false rather than a 5xx: the assignment itself is
      // already committed in the database, and the caller distinguishes "they are
      // assigned but not notified" from "the dispatch failed". Telling it the
      // dispatch failed would invite a second one.
      console.error('[PUSH_API_ERR] OneSignal refused the push', outcome.status, outcome.body);
      return NextResponse.json({
        success: false,
        notifiedCount: 0,
        error: outcome.error ?? 'The push was not delivered.',
      });
    }

    return NextResponse.json({
      success: true,
      notifiedCount: playerIds.length,
      scheme: outcome.scheme,
      oneSignalResponse: outcome.body,
    });

  } catch (err: any) {
    console.error('[PUSH_API_ERR]', err);
    return NextResponse.json({ error: err?.message || 'Server error dispatching push notification' }, { status: 500 });
  }
}
