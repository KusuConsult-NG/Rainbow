/**
 * Opening a mesh envelope. The only place in the system that can.
 *
 * A mirror of the reading half of `lib/core/mesh/mesh_sealer.dart`: ECIES over
 * P-256 — an ephemeral keypair per message, ECDH against HQ's long-lived key,
 * HKDF-SHA256 to an AES-256 key, then AES-GCM.
 *
 * Sealed body layout:
 *
 *   offset  size  field
 *        0     1  version
 *        1    33  ephemeral public key, compressed P-256
 *       34    12  AES-GCM nonce
 *       46     n  ciphertext + 16-byte tag
 *
 * ## Four ways two implementations of this silently disagree
 *
 * Every one of them fails as "authentication failed", with nothing to say which
 * — which is why `mesh-sealer.test.ts` opens frames the Dart encoder produced
 * rather than frames this file produced:
 *
 *   1. **Point compression.** Dart emits a compressed point (33 bytes, leading
 *      0x02 or 0x03). Node's `computeSecret` accepts it; a mirror that assumed
 *      65 uncompressed bytes would read the nonce as key material.
 *   2. **The HKDF info string.** One character apart derives a different key.
 *   3. **Left-padding the shared secret.** A secret whose big-integer form is
 *      short must still be 32 bytes, or roughly one message in 256 derives a
 *      different key on the two sides and the failure looks random. Node hands
 *      back a padded buffer and pointycastle is padded explicitly; both are
 *      fixed-width, which is what makes them agree.
 *   4. **Tag position.** pointycastle appends the tag to the ciphertext; Node
 *      wants it handed over separately.
 *
 * ## HQ's private key
 *
 * Thirty-two bytes, hex, in `MESH_HQ_PRIVATE_KEY`. It is the single most
 * sensitive value in the deployment: it opens every mesh alert ever sent, past
 * ones included, because the ephemeral halves are long gone. It exists on the
 * HQ server and nowhere else — not in the app, not in the console bundle, not in
 * a repository. Only the public half ships to handsets.
 *
 * This file does not read it. It takes the key as an argument and holds no
 * state, so it is testable directly; the one place that touches the environment
 * is the ingest route, which is server-only by construction.
 */

import { createDecipheriv, createECDH, hkdfSync } from 'node:crypto';

const SEAL_VERSION = 1;
const EPHEMERAL_LENGTH = 33;
const NONCE_LENGTH = 12;
const TAG_LENGTH = 16;
const SEAL_HEADER = 1 + EPHEMERAL_LENGTH + NONCE_LENGTH;

/**
 * The HKDF info string. Byte-identical to `_hkdfInfo` in mesh_sealer.dart.
 *
 * It separates this key from any other derived from the same ECDH secret for a
 * different purpose, so a future channel reusing the HQ keypair cannot be used
 * to attack this one.
 */
const HKDF_INFO = Buffer.from('operation-rainbow/mesh/v1');

/**
 * Opens a sealed body with HQ's private scalar.
 *
 * Returns null for EVERY failure — a tampered body, a frame sealed to a key we
 * do not hold, a truncated one, a foreign version. The caller must not be able
 * to tell them apart, and must not relay the difference onward: a caller who
 * learns which frames are addressed to us learns something about which key is
 * live, and an unauthenticated endpoint that answers differently is an oracle.
 */
export function meshOpen(sealed: Buffer, hqPrivateKey: Buffer): Buffer | null {
  if (hqPrivateKey.length !== 32) return null;
  if (sealed.length <= SEAL_HEADER + TAG_LENGTH) return null;
  if (sealed[0] !== SEAL_VERSION) return null;
  try {
    const ephemeral = sealed.subarray(1, 1 + EPHEMERAL_LENGTH);
    const nonce = sealed.subarray(1 + EPHEMERAL_LENGTH, SEAL_HEADER);
    const body = sealed.subarray(SEAL_HEADER);

    const ecdh = createECDH('prime256v1');
    ecdh.setPrivateKey(hqPrivateKey);
    // Throws on a point that is not on the curve, which is the check that stops
    // an invalid-curve attack reaching the key derivation.
    const shared = ecdh.computeSecret(ephemeral);

    // Empty salt, matching pointycastle's null salt. Not an oversight and not a
    // difference: HMAC zero-pads its key to the block size, so an empty salt and
    // HashLen zero bytes produce the same PRK (RFC 5869 §2.2).
    const key = Buffer.from(
      hkdfSync('sha256', shared, Buffer.alloc(0), HKDF_INFO, 32),
    );

    const ciphertext = body.subarray(0, body.length - TAG_LENGTH);
    const tag = body.subarray(body.length - TAG_LENGTH);
    const decipher = createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch {
    return null;
  }
}

/**
 * Reads a 32-byte key from hex, or null if that is not what it is.
 *
 * Null rather than a throw, so a deployment with no mesh key configured refuses
 * mesh traffic quietly instead of returning 500s that tell a caller the endpoint
 * exists and is misconfigured.
 */
export function meshPrivateKeyFromHex(hex: string | undefined): Buffer | null {
  const trimmed = (hex ?? '').trim();
  if (!/^[0-9a-fA-F]{64}$/.test(trimmed)) return null;
  return Buffer.from(trimmed, 'hex');
}
