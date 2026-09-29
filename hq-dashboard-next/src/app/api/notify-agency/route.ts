import { NextRequest, NextResponse } from 'next/server';
import { getSupabaseAdmin, requireRole, COMMAND_ROLES } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';

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
  // Operation Safe Haven — the joint task force covering Plateau. Amotekun,
  // which was here, is a South-West outfit and has no liaison in this state, so
  // an escalation to it would have been addressed to nobody.
  'OPSH': {
    phone: process.env.OPSH_LIAISON_PHONE || '',
    webhook: process.env.OPSH_WEBHOOK_URL || '',
  },
};

export async function POST(req: NextRequest) {
  try {
    // Authorise BEFORE any work. Unauthenticated callers could previously trigger
    // real SMS to Police/Army/DSS liaison numbers with attacker-controlled text.
    const auth = await requireRole(COMMAND_ROLES);
    if (!auth.ok) {
      return NextResponse.json({ error: auth.error }, { status: auth.status });
    }

    let body: { alertId?: string; agency?: string; targetLga?: string; reason?: string; sentBy?: string };
    try {
      body = await req.json();
    } catch {
      return NextResponse.json({ error: 'Malformed JSON body' }, { status: 400 });
    }

    const { alertId, agency, targetLga, reason, sentBy } = body;

    if (!alertId || !agency) {
      return NextResponse.json({ error: 'alertId and agency are required' }, { status: 400 });
    }

    // Reject unknown agencies instead of silently returning success:true / SKIPPED.
    if (!Object.prototype.hasOwnProperty.call(AGENCY_CONTACTS, agency.toUpperCase())) {
      return NextResponse.json(
        { error: `Unknown agency '${agency}'. Expected one of: ${Object.keys(AGENCY_CONTACTS).join(', ')}` },
        { status: 400 }
      );
    }

    const supabase = getSupabaseAdmin();

    // Verify caller is authenticated with a valid Supabase session
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
    const token = authHeader.replace('Bearer ', '');
    const authClient = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    );
    const { data: { user }, error: authErr } = await authClient.auth.getUser(token);
    if (authErr || !user) {
      return NextResponse.json({ error: 'Unauthorized: Invalid session' }, { status: 401 });
    }

    const { data: callerProfile } = await supabase.from('profiles').select('role').eq('id', user.id).maybeSingle();
    const allowedRoles = ['HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'];
    if (!callerProfile || !allowedRoles.includes(callerProfile.role)) {
      return NextResponse.json({ error: 'Forbidden: Insufficient role' }, { status: 403 });
    }

    const results: { method: string; status: string; detail?: string }[] = [];

    // ── 1. SMS via Termii ──────────────────────────────────────────────────
    const agencyContact = AGENCY_CONTACTS[agency.toUpperCase()];
    const { termiiApiKey: termiiKey, termiiSenderId, webhookSecret } = serverEnv();
    const senderPhone = agencyContact?.phone;

    if (termiiKey && senderPhone) {
      const smsBody = [
        `[OPERATION RAINBOW — INTER-AGENCY ESCALATION]`,
        `Agency: ${agency}`,
        `Sector: ${targetLga}`,
        `Alert ID: ${alertId.slice(0, 8).toUpperCase()}`,
        `Reason: ${reason}`,
        `Raised by: ${sentBy ?? auth.userId}`,
        `Time: ${new Date().toLocaleString('en-NG', { timeZone: 'Africa/Lagos' })}`,
        ``,
        `Immediate coordination required. Contact HQ on command channel.`,
      ].join('\n');

      try {
        const termiiRes = await fetch('https://v4.api.termii.com/api/sms/send', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            to: senderPhone,
            from: termiiSenderId,
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
          headers: { 'Content-Type': 'application/json', 'X-Rainbow-Auth': webhookSecret },
          body: JSON.stringify({
            event: 'INTER_AGENCY_ESCALATION',
            alert_id: alertId,
            agency,
            target_lga: targetLga,
            reason,
            sent_by: sentBy ?? auth.userId,
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
