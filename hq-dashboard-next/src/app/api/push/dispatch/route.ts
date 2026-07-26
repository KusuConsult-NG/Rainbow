import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';
const supabase = createClient(supabaseUrl, supabaseKey);

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { alertId, responderUids } = body;

    if (!alertId || !responderUids || !Array.isArray(responderUids) || responderUids.length === 0) {
      return NextResponse.json({ error: 'Invalid payload: alertId and responderUids array required' }, { status: 400 });
    }

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
    const oneSignalAppId = process.env.ONESIGNAL_APP_ID || '885be8b2-5f31-4627-a618-685f54dd266a';
    const oneSignalRestKey = process.env.ONESIGNAL_REST_API_KEY || process.env.NEXT_PUBLIC_ONESIGNAL_REST_API_KEY || '';

    if (!oneSignalRestKey) {
      console.warn('[PUSH_API_WARN] OneSignal REST API Key not configured. Push skipped.');
      return NextResponse.json({ 
        success: true, 
        message: 'OneSignal REST API Key unconfigured in server environment', 
        notifiedCount: 0 
      });
    }

    const response = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${oneSignalRestKey}`,
      },
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
