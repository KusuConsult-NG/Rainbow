// The two halves of the SMS wire format, checked against each other.
//
// `lib/core/offline/sms_alert_payload.dart` encodes on the phone and this
// decodes at HQ. They are separate implementations in separate languages, so
// agreeing on the prose is not enough — these vectors were produced by the
// Dart encoder (`flutter test test/gen_sms_vectors_test.dart`) and are decoded
// here. If either side's layout drifts, these fail.
import { describe, expect, it } from 'vitest';

import vectors from './__fixtures__/sms_alert_vectors.json';
import {
  categoryLabel,
  decodeSmsAlert,
  readDeviceRef,
  severityLabel,
  SMS_ALERT_PREFIX,
} from './sms-alert-codec';

const key = Buffer.from(vectors.keyBase64, 'base64');
const cases = vectors.cases as Record<string, string>;

describe('decoding what the phone actually sent', () => {
  it('reads an ordinary alert', () => {
    const alert = decodeSmsAlert(cases.ordinary, key)!;
    expect(alert).not.toBeNull();
    expect(alert.categoryCode).toBe(9);
    expect(categoryLabel(alert.categoryCode)).toBe('Community attack');
    expect(severityLabel(alert.severityCode)).toBe('CRITICAL');
    expect(alert.isDuress).toBe(false);
  });

  it('recovers the coordinates to about a metre', () => {
    const alert = decodeSmsAlert(cases.ordinary, key)!;
    expect(alert.latitude).toBeCloseTo(9.89654, 5);
    expect(alert.longitude).toBeCloseTo(8.85831, 5);
  });

  it('recovers WHEN THE PHONE RAISED IT, not when the SMS arrived', () => {
    // An SMS can sit in a carrier queue for minutes. A dispatcher looking at a
    // five-minute-old kidnapping needs to know it is five minutes old.
    const alert = decodeSmsAlert(cases.ordinary, key)!;
    expect(alert.sentAt.toISOString()).toBe(vectors.sentAtIso);
  });

  it('carries the duress flag across the language boundary', () => {
    // The decision was to carry it; this is the proof that it survives.
    const alert = decodeSmsAlert(cases.duress, key)!;
    expect(alert.isDuress).toBe(true);
    expect(categoryLabel(alert.categoryCode)).toBe('SOS');
  });

  it('keeps "no GPS fix" as no fix, rather than inventing a position', () => {
    // Null island is a real bug in this system's history: an SOS with no fix
    // was reported at a fabricated location.
    const alert = decodeSmsAlert(cases.noFix, key)!;
    expect(alert.latitude).toBeNull();
    expect(alert.longitude).toBeNull();
  });

  it('handles negative and fractional coordinates', () => {
    const alert = decodeSmsAlert(cases.anonymous, key)!;
    expect(alert.latitude).toBeCloseTo(-1.5, 5);
    expect(alert.longitude).toBeCloseTo(30.25, 5);
    expect(alert.isAnonymous).toBe(true);
  });

  it('recovers the local ref, so the offline queue can be deduplicated', () => {
    const alert = decodeSmsAlert(cases.ordinary, key)!;
    expect(alert.localRef).toBe(vectors.localRefHex);
  });

  it('reads the device ref without needing the key', () => {
    // Ingest has to know WHICH key to fetch before it can decrypt anything.
    expect(readDeviceRef(cases.ordinary)).toBe(vectors.deviceRefHex);
  });
});

describe('it refuses everything else', () => {
  const wrongKey = Buffer.alloc(32, 9);

  it('the wrong key opens nothing', () => {
    expect(decodeSmsAlert(cases.ordinary, wrongKey)).toBeNull();
  });

  it('a tampered body is rejected, so HQ cannot be fed a forgery', () => {
    // The endpoint this replaces accepted anything that reached it.
    const body = cases.ordinary;
    const tampered = `${body.slice(0, body.length - 2)}AA`;
    expect(decodeSmsAlert(tampered, key)).toBeNull();
  });

  it('a truncated body is rejected', () => {
    expect(decodeSmsAlert(cases.ordinary.slice(0, 40), key)).toBeNull();
  });

  it('something that is not ours at all is rejected', () => {
    expect(decodeSmsAlert('hello mum', key)).toBeNull();
    expect(decodeSmsAlert('', key)).toBeNull();
  });

  it('a key of the wrong size is rejected rather than throwing', () => {
    expect(decodeSmsAlert(cases.ordinary, Buffer.alloc(16))).toBeNull();
  });

  it('every failure is the same answer, so this is not an oracle', () => {
    // If a wrong key and a malformed body were distinguishable, an attacker
    // could search for valid device refs.
    for (const bad of [
      decodeSmsAlert(cases.ordinary, wrongKey),
      decodeSmsAlert('OR1notbase64!!!', key),
      decodeSmsAlert('nope', key),
      decodeSmsAlert(cases.ordinary, Buffer.alloc(16)),
    ]) {
      expect(bad).toBeNull();
    }
  });

  it('readDeviceRef does not leak on a bad body either', () => {
    expect(readDeviceRef('nope')).toBeNull();
    expect(readDeviceRef('')).toBeNull();
  });
});

describe('the wire format itself', () => {
  it('every vector is one GSM-7 segment', () => {
    // The number that decides the bill.
    for (const [name, body] of Object.entries(cases)) {
      expect(body.length, name).toBeLessThanOrEqual(160);
      expect(body.length, name).toBe(75);
    }
  });

  it('a duress message is the same length as an ordinary one', () => {
    // Otherwise it is distinguishable by size, which defeats encrypting it.
    expect(cases.duress.length).toBe(cases.ordinary.length);
  });

  it('carries the prefix, so a gateway can route without decrypting', () => {
    for (const body of Object.values(cases)) {
      expect(body.startsWith(SMS_ALERT_PREFIX)).toBe(true);
    }
  });

  it('never spells out what it is', () => {
    for (const body of Object.values(cases)) {
      expect(body.toUpperCase()).not.toContain('DURESS');
      expect(body).not.toContain('9.89');
    }
  });
});
