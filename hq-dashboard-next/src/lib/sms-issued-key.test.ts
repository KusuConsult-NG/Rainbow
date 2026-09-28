// The HQ half of scripts/verify_sms_end_to_end.sh.
//
// It decodes a message body sealed by the Dart encoder with a key a real
// PostgreSQL issued through `register_sms_device()`, using that key exactly as
// `api/sms/inbound` receives it from the RPC — a `\x`-prefixed hex string.
//
// Why this exists as well as `sms-alert-codec.test.ts`: that one decodes vectors
// with a key from a fixture, so it proves the two codecs agree. It cannot prove
// that the key the DATABASE issues survives bytea → `\x`-hex → Buffer, which is
// three encodings deep and is somewhere the channel could fail silently while
// every other test stayed green.
//
// Skips unless the harness supplies the environment, so an ordinary suite run
// neither fails nor prints key material.
import { describe, expect, it } from 'vitest';

import { categoryLabel, decodeSmsAlert, readDeviceRef, severityLabel } from './sms-alert-codec';

const body = process.env.SMS_BODY;
const ingestKey = process.env.INGEST_KEY;
const expectedRef = process.env.SMS_REF_HEX;

describe.skipIf(!body || !ingestKey)('a message sealed with a database-issued key', () => {
  // Exactly the line api/sms/inbound uses on what the RPC returned.
  const secret = Buffer.from(String(ingestKey).replace(/^\\x/, ''), 'hex');

  it('the key survived bytea, hex and Buffer', () => {
    expect(secret.length).toBe(32);
  });

  it('carries the device reference in the clear, matching the one issued', () => {
    expect(readDeviceRef(body!)).toBe(expectedRef);
  });

  it('decodes, and every field survived', () => {
    const a = decodeSmsAlert(body!, secret);
    expect(a).not.toBeNull();
    expect(categoryLabel(a!.categoryCode)).toBe('Kidnap');
    expect(severityLabel(a!.severityCode)).toBe('CRITICAL');
    expect(a!.latitude).toBeCloseTo(9.89654, 5);
    expect(a!.longitude).toBeCloseTo(8.85831, 5);
    expect(a!.isDuress).toBe(true);
    expect(a!.localRef).toBe('aabbccddeeff');
  });

  it('and a wrong key opens nothing, so the tag is doing its job', () => {
    expect(decodeSmsAlert(body!, Buffer.alloc(32, 9))).toBeNull();
  });

  it('prints what HQ would record', () => {
    const a = decodeSmsAlert(body!, secret)!;
    console.log(
      'HQ_WOULD_RECORD ' +
        JSON.stringify({
          type: categoryLabel(a.categoryCode),
          severity: a.isDuress ? 'CRITICAL' : severityLabel(a.severityCode),
          latitude: a.latitude,
          longitude: a.longitude,
          created_at: a.sentAt.toISOString(),
          local_id: a.localRef,
          arrived_via: 'SMS',
        }),
    );
    expect(a).toBeTruthy();
  });
});
