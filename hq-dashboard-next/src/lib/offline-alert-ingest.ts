/**
 * Recording an alert that arrived over a degraded channel.
 *
 * ## Why this is shared rather than written twice
 *
 * Two channels reach HQ without the internet — SMS, and the mesh — and they
 * carry **the same payload**. The mesh plaintext is literally the SMS message
 * body: the outer envelope hides it from relays, and the inner per-device
 * AES-GCM tag proves to HQ which handset raised it. See
 * `lib/core/mesh/mesh_alert_envelope.dart` for why it is built that way.
 *
 * So the decisions about what to record are identical, and writing them twice
 * would mean two chances to get each one wrong. Three of them matter enough to
 * name:
 *
 *   * **`created_at` is when the PHONE raised it**, not when it reached us. An
 *     SMS can sit in a carrier queue for minutes and a mesh envelope can cross a
 *     crowd for an hour. A dispatcher must not read a stale kidnapping as new.
 *   * **A duress alert is CRITICAL** whatever severity the phone encoded.
 *   * **An anonymous report is not attributed**, even though the device key
 *     tells us exactly who sent it. Anonymity that the server quietly discards
 *     is worse than no anonymity, because the reporter believes they have it.
 *
 * ## Every failure returns the same thing
 *
 * `rejected` carries no reason to the caller. Both endpoints answer identically
 * whatever went wrong, because a distinguishable rejection lets somebody search
 * for valid device references or confirm that a particular handset is
 * registered. The reasons go to the server log, where the people who need them
 * are.
 */

import type { SupabaseClient } from '@supabase/supabase-js';

import {
  categoryLabel,
  decodeSmsAlert,
  readDeviceRef,
  severityLabel,
} from './sms-alert-codec';

/** Which degraded channel a report came in over. Written to `arrived_via`. */
export type OfflineChannel = 'SMS' | 'MESH';

export type OfflineIngestOutcome = 'accepted' | 'duplicate' | 'rejected';

/**
 * Authenticates an offline-channel payload and records it as one alert.
 *
 * [body] is the `OR1…` message body, identical in both channels. [channel] is
 * only used for `arrived_via` and the log — it grants no different trust, since
 * both channels are authenticated by the same per-device key.
 */
export async function recordOfflineAlert(
  supabase: SupabaseClient,
  body: string,
  channel: OfflineChannel,
): Promise<OfflineIngestOutcome> {
  const tag = `[${channel}_INGEST]`;
  if (typeof body !== 'string') return 'rejected';

  const deviceRef = readDeviceRef(body);
  if (!deviceRef) return 'rejected';

  // Which key sealed this? Service-role only; a phone or a browser cannot reach
  // this function at all.
  const { data: keyRows, error: keyErr } = await supabase.rpc('sms_key_for_ingest', {
    p_ref: `\\x${deviceRef}`,
  });
  if (keyErr || !Array.isArray(keyRows) || keyRows.length === 0) {
    console.warn(`${tag} rejected: no live key for that device`);
    return 'rejected';
  }
  const row = keyRows[0] as { user_id: string; secret: string };
  const secret = Buffer.from(String(row.secret).replace(/^\\x/, ''), 'hex');

  const alert = decodeSmsAlert(body, secret);
  if (!alert) {
    // A forgery, a replay under a revoked key, or corruption in transit. All the
    // same from here.
    console.warn(`${tag} rejected: message did not authenticate`);
    return 'rejected';
  }

  // Deduplicate against the reporter's own offline queue, and against the same
  // report arriving over the other channel. The same incident will very often
  // arrive more than once: by SMS now, by mesh through a stranger's phone, and
  // again when the reporter's handset regains data and replays its queue.
  // `local_id` is the shared identity, and both channels carry its first six
  // bytes.
  const { data: existing } = await supabase
    .from('alerts')
    .select('id')
    .eq('reported_by', row.user_id)
    .like('local_id', `%${alert.localRef}%`)
    .limit(1);
  if (existing && existing.length > 0) return 'duplicate';

  const { error: insertErr } = await supabase.from('alerts').insert({
    type: categoryLabel(alert.categoryCode),
    description: describe(alert.isDuress, channel),
    severity: alert.isDuress ? 'CRITICAL' : severityLabel(alert.severityCode),
    reported_by: alert.isAnonymous ? null : row.user_id,
    latitude: alert.latitude,
    longitude: alert.longitude,
    created_at: alert.sentAt.toISOString(),
    local_id: alert.localRef,
    arrived_via: channel,
  });
  if (insertErr) {
    console.error(`${tag} could not record the alert:`, insertErr);
    return 'rejected';
  }

  console.warn(
    `${tag} accepted ${alert.isDuress ? 'DURESS ' : ''}alert from device ${deviceRef}`,
  );
  return 'accepted';
}

/**
 * What a dispatcher reads first.
 *
 * It says how the report reached us, because that changes what the dispatcher
 * should assume: a phone that could not open a data connection cannot be called
 * back through the app, and nothing more is coming from it.
 */
function describe(isDuress: boolean, channel: OfflineChannel): string {
  const how =
    channel === 'SMS'
      ? 'The reporter had no data connection and sent this by SMS.'
      : 'The reporter had no network at all. This reached us through nearby ' +
        'phones, so their position may be some minutes old.';
  return isDuress ? `DURESS alert. ${how}` : `Reported offline. ${how}`;
}
