// What HQ can read off a mesh frame, and — the part that matters — what it
// cannot.
//
// Every frame here was produced by the Dart encoder
// (`test/gen_mesh_vectors_test.dart`), not by this file's own mirror of it.
// Two implementations of one wire format that are only checked against each
// other's prose agree right up until a handset is in the field.
import { describe, expect, it } from 'vitest';

import vectors from '@/lib/__fixtures__/mesh_envelope_vectors.json';
import {
  MESH_DEFAULT_TTL,
  MESH_MAX_ENVELOPE_BYTES,
  decodeMeshFrame,
  decodeMeshFrameBase64,
  meshFrameIsFresh,
} from './mesh-envelope';

const frames = vectors.frames as Record<string, string>;
const ids = vectors.ids as Record<string, string>;

function bytes(name: string): Buffer {
  return Buffer.from(frames[name], 'base64url');
}

describe('reading a mesh frame the app produced', () => {
  it('decodes one', () => {
    const frame = decodeMeshFrameBase64(frames.ordinary);
    expect(frame).not.toBeNull();
    expect(frame!.id).toBe(ids.ordinary);
    expect(frame!.ttl).toBe(MESH_DEFAULT_TTL);
    expect(frame!.keyId).toBe(1);
    expect(frame!.createdAt.toISOString()).toBe(vectors.createdAtIso);
  });

  it('a frame is small enough for a radio that carries a few hundred bytes', () => {
    expect(bytes('ordinary').length).toBeLessThan(MESH_MAX_ENVELOPE_BYTES);
  });

  it('a forwarded frame has spent a hop and is otherwise identical', () => {
    // What a relay actually hands to HQ. It must not matter how far it came.
    const first = decodeMeshFrameBase64(frames.ordinary)!;
    const onward = decodeMeshFrameBase64(frames.forwarded)!;
    expect(onward.ttl).toBe(first.ttl - 1);
    expect(onward.id).toBe(first.id);
    expect(onward.sealed.equals(first.sealed)).toBe(true);
  });

  it('a duress frame is indistinguishable from an ordinary one', () => {
    // The property the whole envelope design exists for. If a hostile relay
    // could tell, "there is a DURESS alert somewhere near here" is actionable
    // intelligence about the person the alert concerns.
    const ordinary = decodeMeshFrameBase64(frames.ordinary)!;
    const duress = decodeMeshFrameBase64(frames.duress)!;
    expect(duress.sealed.length).toBe(ordinary.sealed.length);
    expect(bytes('duress').length).toBe(bytes('ordinary').length);
    expect(duress.ttl).toBe(ordinary.ttl);
    expect(duress.keyId).toBe(ordinary.keyId);
  });

  it('nothing operational is legible in the frame', () => {
    const raw = bytes('duress').toString('latin1');
    for (const leak of ['OR1', 'Kidnap', 'DURESS', 'SOS', '9.89']) {
      expect(raw).not.toContain(leak);
    }
  });

  it('two frames from the same phone share no sealed bytes', () => {
    // A fresh ephemeral keypair per message. A relay that saw both cannot tell
    // they came from one handset, so it cannot follow that handset.
    const a = decodeMeshFrameBase64(frames.ordinary)!.sealed;
    const b = decodeMeshFrameBase64(frames.duress)!.sealed;
    expect(a.equals(b)).toBe(false);
    // Not even the leading byte after the version: that is the compressed
    // point's sign, and beyond it everything differs.
    expect(a.subarray(1, 9).equals(b.subarray(1, 9))).toBe(false);
  });
});

describe('refusing bytes that are not a frame', () => {
  // These arrive from an unauthenticated POST by a phone nobody controls. A
  // malformation that throws is a way to take the endpoint down.
  const cases: Record<string, Buffer> = {
    empty: Buffer.alloc(0),
    'shorter than the header': bytes('ordinary').subarray(0, 20),
    truncated: bytes('ordinary').subarray(0, 60),
    'a foreign version': (() => {
      const b = bytes('ordinary');
      b[0] = 9;
      return b;
    })(),
    'no sealed body': (() => {
      const b = Buffer.alloc(29);
      b[0] = 1;
      b[17] = 4;
      b.writeBigUInt64BE(BigInt(Date.now()), 18);
      return b;
    })(),
    'a ttl of zero': (() => {
      const b = bytes('ordinary');
      b[17] = 0;
      return b;
    })(),
    'a ttl above the limit': (() => {
      // Minted by hand to buy extra amplification.
      const b = bytes('ordinary');
      b[17] = 200;
      return b;
    })(),
    'a length that disagrees with the body': (() => {
      const b = bytes('ordinary');
      b.writeUInt16BE(9, 27);
      return b;
    })(),
    'a timestamp of zero': (() => {
      const b = bytes('ordinary');
      // BigInt(0), not 0n: this project's tsconfig targets below ES2020.
      b.writeBigUInt64BE(BigInt(0), 18);
      return b;
    })(),
    'a timestamp after 2100': (() => {
      const b = bytes('ordinary');
      b.writeBigUInt64BE(BigInt(9999999999999), 18);
      return b;
    })(),
    'larger than any relay carries': Buffer.alloc(MESH_MAX_ENVELOPE_BYTES + 1, 1),
  };

  for (const [name, buf] of Object.entries(cases)) {
    it(`returns null for ${name}`, () => {
      expect(decodeMeshFrame(buf)).toBeNull();
    });
  }

  it('returns null rather than throwing on text that is not base64', () => {
    expect(decodeMeshFrameBase64('!!!! not base64 !!!!')).toBeNull();
    expect(decodeMeshFrameBase64('')).toBeNull();
    expect(decodeMeshFrameBase64('x'.repeat(5000))).toBeNull();
  });
});

describe('freshness', () => {
  const frame = decodeMeshFrameBase64(frames.ordinary)!;
  const sealedAt = frame.createdAt.getTime();

  it('a frame from minutes ago is fresh', () => {
    expect(meshFrameIsFresh(frame, new Date(sealedAt + 20 * 60_000))).toBe(true);
  });

  it('a frame from twenty hours ago is still fresh', () => {
    // An emergency is not less real for being old, and a mesh crossing a town
    // by short hops is slow. This bound matches what a relay will carry.
    expect(meshFrameIsFresh(frame, new Date(sealedAt + 20 * 3600_000))).toBe(true);
  });

  it('a frame from three days ago is not', () => {
    // No relay would still be carrying it, so this is somebody replaying a
    // captured frame.
    expect(meshFrameIsFresh(frame, new Date(sealedAt + 72 * 3600_000))).toBe(false);
  });

  it('a modestly wrong clock is tolerated', () => {
    // Handset clocks disagree. Dropping alerts from phones whose clock is
    // half an hour fast would be an invisible failure affecting whole batches
    // of handsets.
    expect(meshFrameIsFresh(frame, new Date(sealedAt - 30 * 60_000))).toBe(true);
  });

  it('but a timestamp days in the future is not', () => {
    expect(meshFrameIsFresh(frame, new Date(sealedAt - 48 * 3600_000))).toBe(false);
  });
});
