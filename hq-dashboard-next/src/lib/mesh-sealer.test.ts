// Opening what a Dart handset sealed — both layers, on real bytes.
//
// This is the test the mesh design rests on, and it is deliberately arranged so
// that it cannot pass by agreeing with itself. Every frame was produced by
// `flutter test test/gen_mesh_vectors_test.dart`; nothing here encrypts
// anything. ECIES has four places where two implementations diverge silently —
// point compression, the HKDF info string, padding the shared secret, and where
// the GCM tag lives — and all four fail identically as "authentication failed".
//
// It also proves the two-layer claim end to end: the outer seal hides the
// payload from relays, and the payload inside is the SAME device-authenticated
// SMS body the other offline channel carries, so HQ knows which handset raised
// the alert and no relay ever could.
import { describe, expect, it } from 'vitest';

import meshVectors from '@/lib/__fixtures__/mesh_envelope_vectors.json';
import smsVectors from '@/lib/__fixtures__/sms_alert_vectors.json';
import { decodeMeshFrameBase64 } from './mesh-envelope';
import { meshOpen, meshPrivateKeyFromHex } from './mesh-sealer';
import { decodeSmsAlert, readDeviceRef } from './sms-alert-codec';

const frames = meshVectors.frames as Record<string, string>;
const inner = meshVectors.innerBodies as Record<string, string>;
const hqKey = Buffer.from(meshVectors.hqPrivateKeyHex, 'hex');
const deviceKey = Buffer.from(smsVectors.keyBase64, 'base64');

function sealedOf(name: string): Buffer {
  return decodeMeshFrameBase64(frames[name])!.sealed;
}

describe('opening a sealed mesh payload', () => {
  it('HQ opens what the app sealed', () => {
    const opened = meshOpen(sealedOf('ordinary'), hqKey);
    expect(opened).not.toBeNull();
    expect(opened!.toString('ascii')).toBe(inner.ordinary);
  });

  it('and a duress one', () => {
    expect(meshOpen(sealedOf('duress'), hqKey)!.toString('ascii')).toBe(inner.duress);
  });

  it('a frame that spent a hop opens the same', () => {
    // Hop count lives in the envelope, outside the seal, so a relay decrementing
    // it cannot invalidate the payload. If it could, only a direct upload would
    // ever work and the mesh would be pointless.
    expect(meshOpen(sealedOf('forwarded'), hqKey)!.toString('ascii')).toBe(
      inner.ordinary,
    );
  });
});

describe('what comes out is an alert HQ can trust', () => {
  // The whole reason the mesh plaintext is an SMS body: the outer seal proves
  // nothing about who sealed it, because anybody has the public key. The inner
  // per-device tag is what makes the alert unforgeable.
  it('the payload is authenticated by the reporter device key', () => {
    const body = meshOpen(sealedOf('ordinary'), hqKey)!.toString('ascii');
    expect(readDeviceRef(body)).toBe(smsVectors.deviceRefHex);

    const alert = decodeSmsAlert(body, deviceKey);
    expect(alert).not.toBeNull();
    expect(alert!.latitude).toBeCloseTo(9.89654, 5);
    expect(alert!.longitude).toBeCloseTo(8.85831, 5);
    expect(alert!.sentAt.toISOString()).toBe(smsVectors.sentAtIso);
    expect(alert!.localRef).toBe(smsVectors.localRefHex);
  });

  it('a duress payload says so, to HQ and to nobody in between', () => {
    const body = meshOpen(sealedOf('duress'), hqKey)!.toString('ascii');
    expect(decodeSmsAlert(body, deviceKey)!.isDuress).toBe(true);
  });

  it('the inner payload cannot be read with the wrong device key', () => {
    // A relay that somehow opened the outer seal still could not forge the
    // inner one, and HQ still could not be fed a lie by the relay.
    const body = meshOpen(sealedOf('ordinary'), hqKey)!.toString('ascii');
    expect(decodeSmsAlert(body, Buffer.alloc(32, 7))).toBeNull();
  });
});

describe('refusing everything else, indistinguishably', () => {
  it('a body tampered with in transit', () => {
    expect(meshOpen(sealedOf('tampered'), hqKey)).toBeNull();
  });

  it('a frame sealed to a key HQ does not hold', () => {
    // A rotation gone wrong, or somebody else's deployment. Must look exactly
    // like a forgery.
    expect(meshOpen(sealedOf('sealedToAnotherKey'), hqKey)).toBeNull();
  });

  it('the wrong private key', () => {
    expect(meshOpen(sealedOf('ordinary'), Buffer.alloc(32, 1))).toBeNull();
  });

  it('a private key that is not 32 bytes', () => {
    expect(meshOpen(sealedOf('ordinary'), Buffer.alloc(16, 1))).toBeNull();
  });

  it('a truncated seal', () => {
    expect(meshOpen(sealedOf('ordinary').subarray(0, 50), hqKey)).toBeNull();
  });

  it('nothing at all', () => {
    expect(meshOpen(Buffer.alloc(0), hqKey)).toBeNull();
    expect(meshOpen(Buffer.alloc(46, 1), hqKey)).toBeNull();
  });

  it('a foreign seal version', () => {
    const s = Buffer.from(sealedOf('ordinary'));
    s[0] = 2;
    expect(meshOpen(s, hqKey)).toBeNull();
  });

  it('an ephemeral point that is not on the curve', () => {
    // The check that stops an invalid-curve attack reaching key derivation.
    const s = Buffer.from(sealedOf('ordinary'));
    s.fill(0xaa, 1, 34);
    expect(meshOpen(s, hqKey)).toBeNull();
  });

  it('every failure is the same value, not a different error', () => {
    const results = [
      meshOpen(sealedOf('tampered'), hqKey),
      meshOpen(sealedOf('sealedToAnotherKey'), hqKey),
      meshOpen(Buffer.alloc(80, 1), hqKey),
    ];
    expect(new Set(results)).toEqual(new Set([null]));
  });
});

describe('reading HQ_s private key from configuration', () => {
  it('accepts 32 bytes of hex', () => {
    expect(meshPrivateKeyFromHex(meshVectors.hqPrivateKeyHex)?.length).toBe(32);
  });

  it('refuses anything else, so a misconfigured deployment refuses traffic', () => {
    // Rather than throwing 500s that tell a caller the endpoint exists and is
    // broken, or worse, silently deriving a key from a truncated value.
    for (const bad of [undefined, '', 'nonsense', 'ab', 'zz'.repeat(32)]) {
      expect(meshPrivateKeyFromHex(bad)).toBeNull();
    }
  });

  it('tolerates surrounding whitespace, which env files collect', () => {
    expect(meshPrivateKeyFromHex(` ${meshVectors.hqPrivateKeyHex}\n`)).not.toBeNull();
  });
});
