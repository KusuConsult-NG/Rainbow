import { NextResponse } from 'next/server';
import { getSupabaseAdmin, requireRole, COMMAND_ROLES } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';
import { ONESIGNAL_ENDPOINT, oneSignalHeaders } from '@/lib/onesignal';

export async function POST(request: Request) {
  try {
    // Authorise BEFORE any work. This route previously ran its full dispatch logic
    // for completely unauthenticated callers.
    const auth = await requireRole(COMMAND_ROLES);
    if (!auth.ok) {
      return NextResponse.json({ error: auth.error }, { status: auth.status });
    }

    // Parse separately so malformed JSON is a 400, not a 500 echoing the parser message.
    let body: { alertId?: unknown; responderUids?: unknown };
    try {
      body = await request.json();
    } catch {
      return NextResponse.json({ error: 'Malformed JSON body' }, { status: 400 });
    }

    const { alertId, responderUids } = body as { alertId?: string; responderUids?: string[] };

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
    const { oneSignalAppId, oneSignalRestKey, oneSignalAuthScheme } = serverEnv();

    if (!oneSignalAppId || !oneSignalRestKey) {
      console.warn('[PUSH_API_WARN] OneSignal REST API Key not configured. Push skipped.');
      return NextResponse.json({ 
        success: true, 
        message: 'OneSignal REST API Key unconfigured in server environment', 
        notifiedCount: 0 
      });
    }

    const response = await fetch(ONESIGNAL_ENDPOINT, {
      method: 'POST',
      headers: oneSignalHeaders(oneSignalRestKey, oneSignalAuthScheme),
      body: JSON.stringify({
        app_id: oneSignalAppId,
        include_player_ids: playerIds,
        headings: { en: '⚡ TACTICAL MISSION DISPATCH' },
        contents: { en: `You have been dispatched to Emergency Incident #${alertId.substring(0, 8)}. Report immediately.` },
        data: { alertId, type: 'DISPATCH' }
      })
    });

    const resData = await response.json();
    return NextResponse.json({ 
      success: true, 
      notifiedCount: playerIds.length, 
      oneSignalResponse: resData 
    });

  } catch (err: any) {
    console.error('[PUSH_API_ERR]', err);
    return NextResponse.json({ error: err?.message || 'Server error dispatching push notification' }, { status: 500 });
  }
}
