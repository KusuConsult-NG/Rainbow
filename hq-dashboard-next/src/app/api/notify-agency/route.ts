import { NextRequest, NextResponse } from 'next/server';
import { getSupabaseAdmin, requireRole, COMMAND_ROLES } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';
import { AGENCY_CODES, AGENCY_NAMES, isAgencyCode, type AgencyCode } from '@/lib/agencies';

/**
 * Where one agency is reached, in this deployment.
 *
 * Keyed off the agency code rather than a hand-written table, so the set of
 * agencies that can be CONTACTED is the same set that can be ESCALATED TO. The
 * table it replaces listed six agencies and the escalation menu offered four
 * codes that were not among them — `NPF`, `MILITARY`, `RAINBOW`, `VGN` — so
 * handing an incident to the Police arrived here as `'NPF'` and left as
 * `400 Unknown agency 'NPF'`. Nobody read the response.
 *
 * Read per request, not captured at module load: the previous `const` table
 * snapshotted `process.env` when the server started, so a contact number added
 * in the Railway variables appeared to take effect and did not until redeploy.
 *
 * Both values are optional per agency: a deployment may have a phone and no
 * webhook, or neither yet. What must never happen is reporting a handover as
 * notified when neither existed — see `deliveryVerdict` below.
 */
function contactFor(code: AgencyCode): { phone: string; webhook: string } {
  return {
    phone: process.env[`${code}_LIAISON_PHONE`] ?? '',
    webhook: process.env[`${code}_WEBHOOK_URL`] ?? '',
  };
}

/** One attempt on one channel. `SKIPPED` is NOT a delivery. */
interface ChannelResult {
  method: 'SMS' | 'WEBHOOK';
  status: 'SENT' | 'FAILED' | 'SKIPPED';
  detail?: string;
}

/**
 * What to tell the caller, and what the caller must tell the operator.
 *
 * ## The defect this replaces
 *
 * It was `results.every(r => r.status === 'SENT' || r.status === 'SKIPPED')`,
 * returned as `success`. A deployment with no Termii key and no webhook URL —
 * which is every deployment until somebody fills those in, and this one today —
 * produced exactly one result, `SMS / SKIPPED`, and that expression is `true`.
 * So the endpoint answered `200 {"success":true}` to a request that handed a
 * kidnapping to the Nigerian Army and told nobody at all.
 *
 * The webhook leg made it worse by being invisible rather than wrong: with no
 * URL configured it pushed no result, so neither the response nor the
 * `agency_notifications` audit row recorded that a channel existed and was not
 * used.
 *
 * `SKIPPED` now means what it says — nothing was sent on that channel — and
 * only a `SENT` counts. The status code separates the two reasons a handover
 * goes undelivered, because they need different people: 503 is "this
 * deployment has no contact details for that agency" (an operator with the
 * Railway variables), 502 is "we tried and the provider refused" (someone who
 * can read the detail).
 */
function deliveryVerdict(agency: AgencyCode, results: ChannelResult[]) {
  const sent = results.filter(r => r.status === 'SENT');
  const failed = results.filter(r => r.status === 'FAILED');
  const name = AGENCY_NAMES[agency];

  if (sent.length && !failed.length) {
    return {
      delivered: true,
      status: 200,
      detail: `${name} notified by ${sent.map(r => r.method).join(' and ')}.`,
    };
  }
  if (sent.length) {
    return {
      delivered: true,
      status: 207,
      detail: `${name} notified by ${sent.map(r => r.method).join(' and ')}, but `
        + `${failed.map(r => `${r.method} failed (${r.detail ?? 'no detail'})`).join('; ')}.`,
    };
  }
  if (failed.length) {
    return {
      delivered: false,
      status: 502,
      detail: `${name} was NOT notified: `
        + `${failed.map(r => `${r.method} failed (${r.detail ?? 'no detail'})`).join('; ')}.`,
    };
  }
  return {
    delivered: false,
    status: 503,
    detail: `${name} was NOT notified: this deployment has no SMS or webhook `
      + `contact configured for ${agency}. Set ${agency}_LIAISON_PHONE with `
      + `TERMII_API_KEY, or ${agency}_WEBHOOK_URL with RAINBOW_WEBHOOK_SECRET.`,
  };
}

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
    const code = String(agency).toUpperCase();
    if (!isAgencyCode(code)) {
      return NextResponse.json(
        { error: `Unknown agency '${agency}'. Expected one of: ${AGENCY_CODES.join(', ')}` },
        { status: 400 }
      );
    }

    const supabase = getSupabaseAdmin();

    // A SECOND authorisation check used to sit here, and it was broken twice
    // over. It called `createClient` without importing it, so the deployment
    // failed to type check and nothing shipped at all. And it read the caller
    // from an `Authorization: Bearer` header, while the only caller —
    // alert-actions.ts escalateAlert — sends no such header, so once it
    // compiled it would have refused every agency notification with a 401.
    //
    // The route is already authorised: `requireRole(COMMAND_ROLES)` runs above
    // before any work, reads the session from cookies (which is what a browser
    // actually has), and looks the role up with admin privileges so a
    // permissive policy cannot spoof it.
    //
    // NOTE: that block also listed a NARROWER set — HQ_COMMAND, HQ_OFFICER,
    // ADMIN — where COMMAND_ROLES also includes LGA_COMMAND. Excluding LGA
    // command from agency escalation may well be intended, but it is a change
    // to who can do this, not a bug fix, so it is not being made silently here.

    const results: ChannelResult[] = [];

    // ── 1. SMS via Termii ──────────────────────────────────────────────────
    const agencyContact = contactFor(code);
    const { termiiApiKey: termiiKey, termiiSenderId, webhookSecret } = serverEnv();
    const senderPhone = agencyContact.phone;

    if (termiiKey && senderPhone) {
      const smsBody = [
        `[OPERATION RAINBOW — INTER-AGENCY ESCALATION]`,
        `Agency: ${code}`,
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
          // The caller awaits this route before it tells the operator anything,
          // so an unbounded wait here is a spinner on the HQ board during an
          // escalation. A timeout is reported as FAILED, which is correct: we
          // do not know that the message was sent.
          signal: AbortSignal.timeout(8_000),
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
      // Say WHICH half is missing. "No phone or Termii key configured" sent an
      // operator to the wrong settings page half the time.
      results.push({
        method: 'SMS',
        status: 'SKIPPED',
        detail: !termiiKey && !senderPhone
          ? `no TERMII_API_KEY and no ${code}_LIAISON_PHONE`
          : !termiiKey ? 'no TERMII_API_KEY' : `no ${code}_LIAISON_PHONE`,
      });
    }

    // ── 2. Webhook to agency endpoint ──────────────────────────────────────
    const webhookUrl = agencyContact.webhook;
    if (!webhookUrl) {
      // Recorded, not omitted. With no result row for this leg, a response
      // saying only `SMS / SKIPPED` read as though the webhook had worked.
      results.push({
        method: 'WEBHOOK',
        status: 'SKIPPED',
        detail: `no ${code}_WEBHOOK_URL`,
      });
    } else if (!webhookSecret) {
      // REFUSED, NOT SENT UNSIGNED.
      //
      // `X-Rainbow-Auth` is the only thing that tells the receiving agency this
      // POST came from Operation Rainbow. With RAINBOW_WEBHOOK_SECRET unset
      // this sent the header as an empty string, which is indistinguishable
      // from anyone who guessed the URL — so either the agency refuses it (and
      // we have reported SENT for a request that was thrown away) or it accepts
      // it, and the endpoint accepts forged escalations from anybody. Neither
      // is a thing to do quietly.
      results.push({
        method: 'WEBHOOK',
        status: 'FAILED',
        detail: 'RAINBOW_WEBHOOK_SECRET is not configured — refusing to send an unsigned escalation',
      });
      console.error('[AGENCY_NOTIFY] refusing unsigned webhook to', code);
    } else {
      try {
        const webhookRes = await fetch(webhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Rainbow-Auth': webhookSecret },
          // Same bound, and more likely to be needed: this is an endpoint an
          // outside agency operates.
          signal: AbortSignal.timeout(8_000),
          body: JSON.stringify({
            event: 'INTER_AGENCY_ESCALATION',
            alert_id: alertId,
            agency: code,
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

    const verdict = deliveryVerdict(code, results);

    // ── 3. Record notification in Supabase ─────────────────────────────────
    //
    // Every leg, including the skipped ones: this table is the only durable
    // record of whether an agency was told, and a row set that omits the
    // channels nobody used cannot answer that question later.
    for (const result of results) {
      await supabase.from('agency_notifications').insert({
        alert_id: alertId,
        agency: code,
        method: result.method,
        status: result.status,
        sent_at: new Date().toISOString(),
      }).then(({ error }) => {
        if (error) console.error('[AGENCY_NOTIFY_DB_ERR]', error.message);
      });
    }

    if (!verdict.delivered) console.warn('[AGENCY_NOTIFY]', verdict.detail);

    return NextResponse.json(
      { delivered: verdict.delivered, detail: verdict.detail, agency: code, results },
      { status: verdict.status },
    );

  } catch (err: any) {
    console.error('[NOTIFY_AGENCY_ERR]', err);
    return NextResponse.json({ error: err?.message || 'Internal server error' }, { status: 500 });
  }
}
