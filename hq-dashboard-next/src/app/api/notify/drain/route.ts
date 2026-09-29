import { NextResponse } from 'next/server';
import { getSupabaseAdmin } from '@/lib/supabase-server';
import { serverEnv } from '@/lib/env';
import {
  escalationMessage,
  recipientsFor,
  rolesForTier,
  type OfficerRow,
  type OutboxRow,
} from '@/lib/notification-recipients';

/**
 * Sends the notifications the database has queued.
 *
 * ## Where this sits
 *
 * `escalate_overdue_alerts()` runs in PostgreSQL every minute and climbs any
 * incident its tier has held too long. It writes the move and a row in
 * `notification_outbox` in ONE statement, so an escalation cannot happen
 * without its notice being owed. That is the half the database can guarantee.
 *
 * It cannot make an HTTP call, and should not: a call inside a transaction
 * cannot be rolled back, and a failure inside one has nowhere to live. So the
 * queue is drained from out here, where a failure is a row with a reason on it
 * and a later attempt.
 *
 * ## Authorisation
 *
 * A shared secret, not a signed-in operator. Nobody is signed in at 02:00 —
 * that is the entire point of the timeout job — so `requireRole` is the wrong
 * shape. The secret is compared in constant time, because a timing oracle on a
 * header is still an oracle.
 *
 * ## Running it
 *
 * Any scheduler that can make an HTTP request, once a minute:
 *
 *     curl -fsS -X POST https://<host>/api/notify/drain \
 *       -H "x-drain-secret: $NOTIFY_DRAIN_SECRET"
 *
 * On Railway that is a cron service with this one line. It is safe to run more
 * than one: `claim_notifications` uses FOR UPDATE SKIP LOCKED, so two workers
 * take different rows rather than both sending everything.
 */

/** Never prerendered, never cached: it has side effects and reads live rows. */
export const dynamic = 'force-dynamic';

/** How many notices one run will take. Bounded so a backlog cannot time out. */
const BATCH = 20;

function secretsMatch(given: string, expected: string): boolean {
  if (given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i += 1) {
    diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

export async function POST(request: Request) {
  const expected = process.env.NOTIFY_DRAIN_SECRET ?? '';
  if (!expected) {
    // Refuse rather than run unauthenticated. An open drain endpoint lets
    // anyone empty the queue — every row marked delivered, nobody notified.
    console.error('[DRAIN] NOTIFY_DRAIN_SECRET is not configured');
    return NextResponse.json({ error: 'Not configured' }, { status: 503 });
  }

  const given = request.headers.get('x-drain-secret') ?? '';
  if (!secretsMatch(given, expected)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const supabase = getSupabaseAdmin();

  const { data: claimed, error: claimErr } = await supabase
    .rpc('claim_notifications', { p_limit: BATCH });

  if (claimErr) {
    console.error('[DRAIN] claim failed', claimErr);
    return NextResponse.json({ error: 'Could not claim notifications' }, { status: 500 });
  }

  const rows = (claimed ?? []) as OutboxRow[];
  if (rows.length === 0) {
    return NextResponse.json({ ok: true, claimed: 0, sent: 0 });
  }

  const { oneSignalAppId, oneSignalRestKey } = serverEnv();
  let sent = 0;
  let failed = 0;
  let noRecipients = 0;

  for (const row of rows) {
    try {
      const roles = rolesForTier(row.payload?.to_tier);
      if (roles.length === 0) {
        // A notice nobody can be addressed from is not a delivery failure to
        // retry for ever. Record it and stop.
        await supabase.rpc('mark_notification_failed', {
          p_id: row.id,
          p_error: `no roles hold tier ${row.payload?.to_tier}`,
        });
        failed += 1;
        continue;
      }

      const { data: officers } = await supabase
        .from('profiles')
        .select('id, role, geo_lga, geo_ward, geo_pu, onesignal_player_id')
        .in('role', roles);

      const recipients = recipientsFor((officers ?? []) as OfficerRow[], row);
      const playerIds = recipients
        .map(r => r.onesignal_player_id)
        .filter((id): id is string => Boolean(id && id.length > 5));

      if (playerIds.length === 0) {
        // NOT marked sent. Nobody was told, and recording it as delivered
        // would reproduce the silence this whole mechanism exists to end —
        // one layer further out, where it is harder to see.
        await supabase.rpc('mark_notification_failed', {
          p_id: row.id,
          p_error: recipients.length === 0
            ? `no officer holds ${row.payload?.to_tier} for this incident`
            : `${recipients.length} officer(s) at ${row.payload?.to_tier} have no push subscription`,
        });
        noRecipients += 1;
        continue;
      }

      if (!oneSignalAppId || !oneSignalRestKey) {
        await supabase.rpc('mark_notification_failed', {
          p_id: row.id,
          p_error: 'OneSignal is not configured on this deployment',
        });
        failed += 1;
        continue;
      }

      const { heading, body } = escalationMessage(row);
      const response = await fetch('https://onesignal.com/api/v1/notifications', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Basic ${oneSignalRestKey}`,
        },
        body: JSON.stringify({
          app_id: oneSignalAppId,
          include_player_ids: playerIds,
          headings: { en: heading },
          contents: { en: body },
          data: {
            alertId: row.payload?.alert_id ?? row.alert_id,
            type: 'TIER_ESCALATION',
            toTier: row.payload?.to_tier,
          },
        }),
      });

      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        await supabase.rpc('mark_notification_failed', {
          p_id: row.id,
          p_error: `OneSignal ${response.status}: ${detail.slice(0, 200)}`,
        });
        failed += 1;
        continue;
      }

      await supabase.rpc('mark_notification_sent', { p_id: row.id });
      sent += 1;
    } catch (e) {
      // One bad row must not abandon the rest of the batch: the others are
      // emergencies waiting to be handed on.
      console.error('[DRAIN] row failed', row.id, e);
      await supabase.rpc('mark_notification_failed', {
        p_id: row.id,
        p_error: String(e).slice(0, 200),
      });
      failed += 1;
    }
  }

  return NextResponse.json({
    ok: true,
    claimed: rows.length,
    sent,
    failed,
    noRecipients,
  });
}
