/**
 * The HQ half of the mesh wire frame.
 *
 * A mirror of `lib/core/mesh/mesh_envelope.dart`. The two must agree byte for
 * byte, so the layout is repeated here rather than described, and
 * `mesh-envelope.test.ts` decodes frames produced by the Dart encoder.
 *
 * Frame layout:
 *
 *   offset  size  field
 *        0     1  version
 *        1    16  id — 128 random bits, the only identity a message has
 *       17     1  ttl, hops remaining
 *       18     8  createdAt, unix milliseconds, big-endian
 *       26     1  keyId, which HQ key sealed it
 *       27     2  sealed length
 *       29     n  sealed body, opaque to everything that is not HQ
 *
 * Note what is NOT here: no reporter, no location, no type, no severity, no
 * duress flag. A relay is a stranger's phone and may belong to the other side
 * of the conflict; "there is a DURESS alert somewhere near here" is itself
 * actionable intelligence about the person the alert concerns.
 *
 * Every malformation returns null rather than throwing. These bytes arrive from
 * an unauthenticated POST, so a frame that crashes the handler is a denial of
 * service on an emergency system.
 */

export const MESH_FRAME_VERSION = 1;
export const MESH_ID_LENGTH = 16;
export const MESH_HEADER_LENGTH = 29;
export const MESH_DEFAULT_TTL = 8;
export const MESH_MAX_ENVELOPE_BYTES = 512;

/** Matches `meshMaxAge` in the Dart relay: the longest a frame may circulate. */
export const MESH_MAX_AGE_MS = 24 * 60 * 60 * 1000;

/**
 * How far into the future a frame's own timestamp may be.
 *
 * Handset clocks disagree, and a relay tolerates a future timestamp rather than
 * silently dropping alerts from a whole class of phones. HQ does the same, with
 * a bound: hours of skew is a wrong clock, days of it is somebody extending an
 * envelope's life.
 */
export const MESH_MAX_SKEW_MS = 60 * 60 * 1000;

export interface MeshFrame {
  /** Hex of the 16 random bytes. The deduplication key, before decryption. */
  id: string;
  ttl: number;
  createdAt: Date;
  keyId: number;
  /** Ephemeral public key, nonce, ciphertext and tag. Opaque until opened. */
  sealed: Buffer;
}

/** Reads a frame, or null if these bytes are not one. */
export function decodeMeshFrame(bytes: Buffer): MeshFrame | null {
  if (bytes.length < MESH_HEADER_LENGTH) return null;
  if (bytes.length > MESH_MAX_ENVELOPE_BYTES) return null;
  if (bytes[0] !== MESH_FRAME_VERSION) return null;

  const sealedLength = bytes.readUInt16BE(27);
  if (sealedLength === 0) return null;
  if (MESH_HEADER_LENGTH + sealedLength !== bytes.length) return null;

  const ttl = bytes.readUInt8(17);
  // A ttl above the limit every phone starts from means somebody minted a frame
  // by hand to buy extra amplification.
  if (ttl === 0 || ttl > MESH_DEFAULT_TTL) return null;

  // readBigUInt64BE, not readUInt32BE: milliseconds since 1970 passed 2^32 in
  // 1970 plus 49 days.
  const millis = Number(bytes.readBigUInt64BE(18));
  if (millis <= 0 || millis > 4102444800000) return null; // year 2100

  return {
    id: bytes.subarray(1, 1 + MESH_ID_LENGTH).toString('hex'),
    ttl,
    createdAt: new Date(millis),
    keyId: bytes.readUInt8(26),
    sealed: Buffer.from(bytes.subarray(MESH_HEADER_LENGTH)),
  };
}

/** Reads a base64url frame, as a relay uploads it. */
export function decodeMeshFrameBase64(value: string): MeshFrame | null {
  if (typeof value !== 'string' || !value) return null;
  // A cheap bound before allocating: base64 is 4 characters per 3 bytes.
  if (value.length > Math.ceil((MESH_MAX_ENVELOPE_BYTES * 4) / 3) + 4) return null;
  try {
    const raw = Buffer.from(value.trim(), 'base64url');
    if (!raw.length) return null;
    return decodeMeshFrame(raw);
  } catch {
    return null;
  }
}

/**
 * Whether a frame is fresh enough to act on.
 *
 * Separate from decoding, because "well-formed" and "worth recording" are
 * different questions and a caller may want to count the second without the
 * first being in doubt.
 */
export function meshFrameIsFresh(frame: MeshFrame, now: Date = new Date()): boolean {
  const age = now.getTime() - frame.createdAt.getTime();
  if (age > MESH_MAX_AGE_MS) return false;
  if (age < -MESH_MAX_SKEW_MS) return false;
  return true;
}
