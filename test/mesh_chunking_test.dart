// A frame through a 20-byte pipe, and the ways a stranger's phone can abuse it.
//
// This is the one place in the mesh where bytes chosen by somebody else are
// assembled into a buffer whose size they choose, so most of these tests are
// about refusing rather than about carrying.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_alert_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_chunking.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

void main() {
  final hq = meshGenerateHqKeypair(random: meshTestRandom(31));
  final deviceKey =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 5) % 256));
  var now = DateTime.utc(2026, 9, 28, 17);

  MeshEnvelope sampleEnvelope({int seed = 2}) => meshEnvelopeForSmsBody(
        smsBody: encodeSmsAlert(
          payload: SmsAlertPayload(
            categoryCode: 9,
            severityCode: 3,
            sentAt: now,
            localRef: Uint8List.fromList([1, 1, 2, 2, 3, 3]),
            latitude: 9.8,
            longitude: 8.8,
          ),
          key: deviceKey,
          deviceRef: Uint8List.fromList([1, 2, 3, 4]),
          nonce: newSmsNonce(),
        ),
        hqPublicKey: hq.publicKey,
        now: now,
        random: meshTestRandom(seed),
      );

  setUp(() => now = DateTime.utc(2026, 9, 28, 17));

  group('what BLE actually forces on us', () {
    test('a default-MTU write carries 16 bytes of frame', () {
      // 23 byte MTU − 3 ATT − 4 header. If a caller forgets the ATT overhead
      // the write fails, or on some stacks is silently truncated, which yields
      // a corrupt frame rather than an error.
      expect(meshPayloadForMtu(23), 16);
      expect(meshPayloadForMtu(517), 510);
    });

    test('a sealed alert needs eleven writes at the default MTU', () {
      final frame = sampleEnvelope().encode();
      final chunks = meshChunk(
          frame: frame, payloadSize: meshPayloadForMtu(23), messageId: 1);
      expect(frame.length, 166);
      expect(chunks.length, 11);
      // Which is the number that makes chunking mandatory rather than an
      // optimisation, and is why this file exists.
      expect(chunks.first.length, lessThanOrEqualTo(20));
    });

    test('and one write at a negotiated MTU', () {
      final chunks = meshChunk(
          frame: sampleEnvelope().encode(),
          payloadSize: meshPayloadForMtu(517),
          messageId: 1);
      expect(chunks, hasLength(1));
    });
  });

  group('carrying a frame', () {
    test('reassembles, and decodes to the same envelope', () {
      final original = sampleEnvelope();
      final chunks = meshChunk(
          frame: original.encode(), payloadSize: 16, messageId: 7);
      final r = MeshReassembler(clock: () => now);

      MeshEnvelope? out;
      for (final c in chunks) {
        final result = r.offer(c);
        if (result.isComplete) out = result.envelope;
      }
      expect(out, isNotNull);
      expect(out!.idHex, original.idHex);
      expect(out.sealed, original.sealed);
      expect(r.openCount, 0, reason: 'nothing held once complete');
    });

    test('and the reassembled frame still opens at HQ', () {
      // The end of the chain: split across eleven BLE writes, put back
      // together, and the alert inside is still readable by HQ and nobody else.
      final original = sampleEnvelope();
      final r = MeshReassembler(clock: () => now);
      MeshEnvelope? out;
      for (final c in meshChunk(
          frame: original.encode(), payloadSize: 16, messageId: 3)) {
        final result = r.offer(c);
        if (result.isComplete) out = result.envelope;
      }
      final opened =
          meshOpen(sealed: out!.sealed, hqPrivateKey: hq.privateKey);
      expect(opened, isNotNull);
      expect(String.fromCharCodes(opened!), startsWith('OR1'));
    });

    test('out of order arrives fine — BLE does not promise ordering', () {
      final original = sampleEnvelope();
      final chunks = meshChunk(
          frame: original.encode(), payloadSize: 16, messageId: 1)
        ..shuffle(_Fixed(4));
      final r = MeshReassembler(clock: () => now);
      MeshEnvelope? out;
      for (final c in chunks) {
        final result = r.offer(c);
        if (result.isComplete) out = result.envelope;
      }
      expect(out?.idHex, original.idHex);
    });

    test('two messages interleaved do not contaminate each other', () {
      final a = sampleEnvelope(seed: 11);
      final b = sampleEnvelope(seed: 12);
      final ca = meshChunk(frame: a.encode(), payloadSize: 16, messageId: 1);
      final cb = meshChunk(frame: b.encode(), payloadSize: 16, messageId: 2);
      final r = MeshReassembler(clock: () => now);

      final done = <String>[];
      for (var i = 0; i < ca.length; i++) {
        for (final result in [r.offer(ca[i]), r.offer(cb[i])]) {
          if (result.isComplete) done.add(result.envelope!.idHex);
        }
      }
      expect(done, hasLength(2));
      expect(done, containsAll([a.idHex, b.idHex]));
    });

    test('a retried chunk is ignored rather than breaking the message', () {
      // A peer that did not see our acknowledgement resends. Treating that as
      // fatal would drop real alerts on a link that drops constantly.
      final original = sampleEnvelope();
      final chunks =
          meshChunk(frame: original.encode(), payloadSize: 16, messageId: 5);
      final r = MeshReassembler(clock: () => now);
      MeshEnvelope? out;
      var duplicates = 0;
      for (final c in chunks) {
        // Both results matter, and the first version of this test only looked
        // at the second one — so `out` was never set and the test failed on its
        // own bookkeeping. The completion comes from the FIRST copy of the final
        // chunk; the retry of it finds nothing left to complete, because the
        // partial is already gone.
        for (final result in [r.offer(c), r.offer(c)]) {
          if (result.isComplete) out = result.envelope;
          if (result.rejection == MeshChunkRejection.duplicate) duplicates++;
        }
      }
      expect(out?.idHex, original.idHex);
      expect(duplicates, chunks.length - 1,
          reason: 'every retry but the last was seen as a duplicate; the last '
              'one arrives after the message is complete and is simply a chunk '
              'of nothing');
    });
  });

  group('refusing what a hostile peer sends', () {
    late MeshReassembler r;
    setUp(() => r = MeshReassembler(clock: () => now));

    Uint8List chunk(int id, int seq, int total, int payloadLength,
            {int version = meshChunkVersion}) =>
        Uint8List.fromList([
          version,
          id,
          seq,
          total,
          ...List<int>.filled(payloadLength, 0xAB),
        ]);

    test('a header with no payload', () {
      expect(r.offer(Uint8List.fromList([1, 0, 0, 1])).rejection,
          MeshChunkRejection.malformed);
    });

    test('a version we do not speak', () {
      expect(r.offer(chunk(1, 0, 2, 8, version: 9)).rejection,
          MeshChunkRejection.malformed);
    });

    test('a total of zero', () {
      expect(r.offer(chunk(1, 0, 0, 8)).rejection,
          MeshChunkRejection.outOfRange);
    });

    test('a sequence beyond the total', () {
      expect(r.offer(chunk(1, 5, 3, 8)).rejection,
          MeshChunkRejection.outOfRange);
    });

    test('a peer that changes its mind about the length', () {
      // Abandoned rather than reconciled: reconciling is how a buffer grows
      // without limit.
      expect(r.offer(chunk(1, 0, 4, 8)).rejection, isNull);
      expect(r.offer(chunk(1, 1, 9, 8)).rejection,
          MeshChunkRejection.inconsistent);
      expect(r.openCount, 0, reason: 'and the partial is dropped');
    });

    test('a message that would assemble larger than any relay carries', () {
      expect(r.offer(chunk(1, 0, 200, 100)).rejection,
          MeshChunkRejection.tooLarge);
      expect(r.bufferedBytes, 0, reason: 'refused before a byte is stored');
    });

    test('a short chunk in the middle, which would shift every later byte', () {
      expect(r.offer(chunk(2, 0, 5, 16)).rejection, isNull);
      expect(r.offer(chunk(2, 1, 5, 4)).rejection,
          MeshChunkRejection.inconsistent);
    });

    test('a long chunk anywhere', () {
      expect(r.offer(chunk(3, 0, 5, 16)).rejection, isNull);
      expect(r.offer(chunk(3, 1, 5, 40)).rejection,
          MeshChunkRejection.inconsistent);
    });

    test('bytes that assemble cleanly into something that is not a frame', () {
      // The peer is on a different version, or is not this app at all.
      final result = [
        r.offer(chunk(4, 0, 2, 16)),
        r.offer(chunk(4, 1, 2, 16)),
      ].last;
      expect(result.rejection, MeshChunkRejection.malformed);
      expect(result.envelope, isNull);
    });

    test('a peer that opens messages and abandons them holds only four', () {
      for (var id = 0; id < 12; id++) {
        r.offer(chunk(id, 0, 8, 16));
        now = now.add(const Duration(milliseconds: 10));
      }
      expect(r.openCount, meshMaxOpenMessages);
    });

    test('and the oldest is the one dropped, not the newest', () {
      // The same choice the relay outbox makes. An attacker who floods wins a
      // delay; they do not get to block the frame arriving behind them.
      r.offer(chunk(1, 0, 8, 16));
      now = now.add(const Duration(seconds: 1));
      for (var id = 2; id <= 5; id++) {
        r.offer(chunk(id, 0, 8, 16));
      }
      // Message 1 is gone, so its second chunk starts a fresh partial rather
      // than completing anything.
      expect(r.offer(chunk(1, 1, 8, 16)).rejection, isNull);
      expect(r.openCount, meshMaxOpenMessages);
    });

    test('a half-sent message is abandoned rather than parked for ever', () {
      r.offer(chunk(1, 0, 8, 16));
      expect(r.openCount, 1);
      now = now.add(meshReassemblyTimeout + const Duration(seconds: 1));
      r.offer(chunk(2, 0, 2, 16));
      expect(r.openCount, 1, reason: 'the expired one went, the new one stayed');
      expect(r.bufferedBytes, 16);
    });

    test('a disconnect drops what was in flight', () {
      // Otherwise a peer that reconnects completes a message with chunks from
      // before the drop, which is a way to splice two frames together.
      r.offer(chunk(1, 0, 8, 16));
      r.clear();
      expect(r.openCount, 0);
      expect(r.bufferedBytes, 0);
    });
  });

  group('refusing to produce something unsendable', () {
    test('an MTU too small to make progress', () {
      expect(
        () => meshChunk(
            frame: sampleEnvelope().encode(), payloadSize: 2, messageId: 1),
        throwsArgumentError,
      );
    });

    test('an empty frame', () {
      expect(
        () => meshChunk(frame: Uint8List(0), payloadSize: 16, messageId: 1),
        throwsArgumentError,
      );
    });

    test('a frame larger than the mesh carries', () {
      expect(
        () => meshChunk(
            frame: Uint8List(meshMaxEnvelopeBytes + 1),
            payloadSize: 16,
            messageId: 1),
        throwsArgumentError,
      );
    });

    test('a message id wraps rather than overflowing its byte', () {
      final chunks = meshChunk(
          frame: sampleEnvelope().encode(), payloadSize: 16, messageId: 259);
      expect(chunks.first[1], 3);
    });
  });
}

/// A fixed shuffle, so an out-of-order failure is reproducible.
class _Fixed implements Random {
  _Fixed(this.seed);
  final int seed;
  int _n = 0;

  @override
  int nextInt(int max) => (seed * 7 + _n++ * 13) % max;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 16) / (1 << 16);
}
