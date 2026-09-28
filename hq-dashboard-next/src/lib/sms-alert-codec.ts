/**
 * The HQ half of the encrypted SMS fallback.
 *
 * A mirror of `lib/core/offline/sms_alert_payload.dart`. The two must agree
 * byte for byte, so the layout is repeated here rather than referenced, and
 * `sms-alert-codec.test.ts` decodes vectors produced by the Dart side.
 *
 * Wire format, 54 bytes, base64url without padding behind an `OR1` prefix:
 *
 *   offset  size  field
 *        0     1  version
 *        1     4  device ref, in the clear so we know which key to try
 *        5    12  AES-GCM nonce
 *       17    37  ciphertext (21 bytes) + tag (16 bytes)
 *
 * And the 21 plaintext bytes:
 *
 *        0     1  flags: bit0 duress, bit1 anonymous, bit2 has location
 *        1     1  category
 *        2     1  severity
 *        3     4  latitude,  int32, degrees x 1e5
 *        7     4  longitude, int32, degrees x 1e5
 *       11     4  sent-at, unix seconds
 *       15     6  first six bytes of the reporter's local_id
 */

import { createDecipheriv } from 'node:crypto';

export const SMS_ALERT_PREFIX = 'OR1';
export const SMS_ALERT_VERSION = 1;

const NONCE_LENGTH = 12;
const TAG_LENGTH = 16;
const PLAINTEXT_LENGTH = 21;
const HEADER_LENGTH = 1 + 4 + NONCE_LENGTH;
const COORD_SCALE = 100000;

const FLAG_DURESS = 0x01;
const FLAG_ANONYMOUS = 0x02;
const FLAG_HAS_LOCATION = 0x04;

export interface SmsAlert {
  categoryCode: number;
  severityCode: number;
  /** When the PHONE raised it, not when the SMS arrived. */
  sentAt: Date;
  /** Hex of the six bytes of local_id, for dedup against the offline queue. */
  localRef: string;
  latitude: number | null;
  longitude: number | null;
  isDuress: boolean;
  isAnonymous: boolean;
}

/** The four bytes a message carries in the clear, as hex. */
export function readDeviceRef(body: string): string | null {
  const raw = decodeBase64Body(body);
  if (!raw || raw.length < HEADER_LENGTH) return null;
  if (raw[0] !== SMS_ALERT_VERSION) return null;
  return Buffer.from(raw.subarray(1, 5)).toString('hex');
}

function decodeBase64Body(body: string): Buffer | null {
  if (!body || !body.startsWith(SMS_ALERT_PREFIX)) return null;
  try {
    const b64 = body.slice(SMS_ALERT_PREFIX.length).trim();
    const raw = Buffer.from(b64, 'base64url');
    return raw.length ? raw : null;
  } catch {
    return null;
  }
}

/**
 * Opens a message with the device's key.
 *
 * Returns null for EVERY failure — a wrong key, a bad tag, a truncated body,
 * a foreign version. The caller must not be able to tell them apart and must
 * not relay the difference onward, or the endpoint becomes an oracle that
 * tells an attacker when they have guessed a valid device ref.
 */
export function decodeSmsAlert(body: string, key: Buffer): SmsAlert | null {
  if (key.length !== 32) return null;
  const raw = decodeBase64Body(body);
  if (!raw) return null;
  if (raw.length !== HEADER_LENGTH + PLAINTEXT_LENGTH + TAG_LENGTH) return null;
  if (raw[0] !== SMS_ALERT_VERSION) return null;

  const nonce = raw.subarray(5, HEADER_LENGTH);
  const sealed = raw.subarray(HEADER_LENGTH);
  const ciphertext = sealed.subarray(0, sealed.length - TAG_LENGTH);
  const tag = sealed.subarray(sealed.length - TAG_LENGTH);

  let plain: Buffer;
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAuthTag(tag);
    plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch {
    // A forged or tampered message lands here. This is the property the old
    // `smsWebhook` lacked entirely: it accepted anything that reached it, so
    // anyone who knew the number could inject an emergency.
    return null;
  }
  if (plain.length !== PLAINTEXT_LENGTH) return null;

  const flags = plain.readUInt8(0);
  const hasLocation = (flags & FLAG_HAS_LOCATION) !== 0;
  return {
    categoryCode: plain.readUInt8(1),
    severityCode: plain.readUInt8(2),
    latitude: hasLocation ? plain.readInt32BE(3) / COORD_SCALE : null,
    longitude: hasLocation ? plain.readInt32BE(7) / COORD_SCALE : null,
    sentAt: new Date(plain.readUInt32BE(11) * 1000),
    localRef: Buffer.from(plain.subarray(15, 21)).toString('hex'),
    isDuress: (flags & FLAG_DURESS) !== 0,
    isAnonymous: (flags & FLAG_ANONYMOUS) !== 0,
  };
}

/** Severity codes, in the order the phone encodes them. */
export const SMS_SEVERITIES = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'] as const;

/**
 * Categories, in the order of `lib/core/constants/alert_categories.dart`.
 *
 * The index IS the wire value, so this list is append-only: reordering it
 * would silently relabel every alert already in flight.
 */
export const SMS_CATEGORIES = [
  'Kidnap',
  'Fire',
  'Drug abuse',
  'Police brutality',
  'Flood',
  'Cyber crime',
  'Child abuse',
  'Domestic violence',
  'Cattle rustling',
  'Community attack',
] as const;

/** 255 means an SOS with no category chosen. */
export const SMS_CATEGORY_SOS = 255;

/** A human label for a wire category code. */
export function categoryLabel(code: number): string {
  if (code === SMS_CATEGORY_SOS) return 'SOS';
  return SMS_CATEGORIES[code] ?? `UNKNOWN (${code})`;
}

/** A human label for a wire severity code. */
export function severityLabel(code: number): string {
  return SMS_SEVERITIES[code] ?? 'MEDIUM';
}
