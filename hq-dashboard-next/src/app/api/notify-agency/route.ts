import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

// Agency liaison contacts — configure per deployment
// In production, move these to Supabase config table or environment variables
const AGENCY_CONTACTS: Record<string, { phone: string; webhook?: string }> = {
  'POLICE': {
    phone: process.env.POLICE_LIAISON_PHONE || '',
    webhook: process.env.POLICE_WEBHOOK_URL || '',
  },
  'ARMY': {
    phone: process.env.ARMY_LIAISON_PHONE || '',
    webhook: process.env.ARMY_WEBHOOK_URL || '',
  },
  'DSS': {
    phone: process.env.DSS_LIAISON_PHONE || '',
    webhook: process.env.DSS_WEBHOOK_URL || '',
  },
  'NSCDC': {
    phone: process.env.NSCDC_LIAISON_PHONE || '',
    webhook: process.env.NSCDC_WEBHOOK_URL || '',
  },
  'FRSC': {
    phone: process.env.FRSC_LIAISON_PHONE || '',
    webhook: process.env.FRSC_WEBHOOK_URL || '',
  },
  'AMOTEKUN': {
    phone: process.env.AMOTEKUN_LIAISON_PHONE || '',
  },
};

export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as {
      alertId: string;
      agency: string;
      targetLga: string;
      reason: string;
      sentBy: string;
    };

    const { alertId, agency, targetLga, reason, sentBy } = body;

    if (!alertId || !agency) {
      return NextResponse.json({ error: 'alertId and agency are required' }, { status: 400 });
    }

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const results: { method: string; status: string; detail?: string }[] = [];

    // ── 1. SMS via Termii ──────────────────────────────────────────────────
    const agencyContact = AGENCY_CONTACTS[agency.toUpperCase()];
    const termiiKey = process.env.TERMII_API_KEY;
    const senderPhone = agencyContact?.phone;

    if (termiiKey && senderPhone) {
      const smsBody = [
        `[OPERATION RAINBOW — INTER-AGENCY ESCALATION]`,
        `Agency: ${agency}`,
        `Sector: ${targetLga}`,
        `Alert ID: ${alertId.slice(0, 8).toUpperCase()}`,
        `Reason: ${reason}`,
        `Raised by: ${sentBy}`,
        `Time: ${new Date().toLocaleString('en-NG', { timeZone: 'Africa/Lagos' })}`,
        ``,
        `Immediate coordination required. Contact HQ on command channel.`,
      ].join('\n');

      try {
        const termiiRes = await fetch('https://v3.api.termii.com/api/sms/send', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            to: senderPhone,
            from: process.env.TERMII_SENDER_ID || 'RainbowHQ',
            sms: smsBody,
            type: 'plain',
            api_key: termiiKey,
            channel: 'dnd',
          }),
        });
        const termiiData = await termiiRes.json();
        results.push({
          method: 'SMS',
          status: termiiRes.ok ? 'SENT' : 'FAILED',
          detail: termiiRes.ok ? termiiData.message_id : JSON.stringify(termiiData),
        });
      } catch (smsErr: any) {
        results.push({ method: 'SMS', status: 'FAILED', detail: smsErr?.message });
      }
    } else {
      results.push({ method: 'SMS', status: 'SKIPPED', detail: 'No phone or Termii key configured' });
    }

    // ── 2. Webhook to agency endpoint ──────────────────────────────────────
    const webhookUrl = agencyContact?.webhook;
    if (webhookUrl) {
      try {
        const webhookRes = await fetch(webhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Rainbow-Auth': process.env.RAINBOW_WEBHOOK_SECRET || '' },
          body: JSON.stringify({
            event: 'INTER_AGENCY_ESCALATION',
            alert_id: alertId,
            agency,
            target_lga: targetLga,
            reason,
            sent_by: sentBy,
            timestamp: new Date().toISOString(),
          }),
        });
        results.push({
          method: 'WEBHOOK',
          status: webhookRes.ok ? 'SENT' : 'FAILED',
          detail: `HTTP ${webhookRes.status}`,
        });
      } catch (whErr: any) {
        results.push({ method: 'WEBHOOK', status: 'FAILED', detail: whErr?.message });
      }
    }

    // ── 3. Record notification in Supabase ─────────────────────────────────
    for (const result of results) {
      await supabase.from('agency_notifications').insert({
        alert_id: alertId,
        agency,
        method: result.method,
        status: result.status,
        sent_at: new Date().toISOString(),
      }).then(({ error }) => {
        if (error) console.error('[AGENCY_NOTIFY_DB_ERR]', error.message);
      });
    }

    const allSent = results.every(r => r.status === 'SENT' || r.status === 'SKIPPED');
    return NextResponse.json({ success: allSent, results }, { status: allSent ? 200 : 207 });

  } catch (err: any) {
    console.error('[NOTIFY_AGENCY_ERR]', err);
    return NextResponse.json({ error: err?.message || 'Internal server error' }, { status: 500 });
  }
}
