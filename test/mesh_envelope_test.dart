// What a relaying phone is allowed to know.
//
// The envelope carries the minimum a relay needs in order to relay, and
// nothing else. Not the reporter, not the location, not the type, not the
// severity, and not the duress flag — "there is a DURESS alert somewhere near
// here" is itself actionable intelligence for the person the alert is about.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';

void main() {
  final at = DateTime.utc(2026, 9, 28, 14, 30, 5);
  final sealedBody = Uint8List.fromList(
      List<int>.generate(90, (i) => (i * 13) & 0xff));

  MeshEnvelope make({int ttl = meshDefaultTtl, Uint8List? sealed}) =>
      MeshEnvelope(
        id: Uint8List.fromList(List<int>.generate(16, (i) => i)),
        ttl: ttl,
        createdAt: at,
        keyId: 2,
        sealed: sealed ?? sealedBody,
      );

  group('the wire form round-trips', () {
    test('every routing field survives', () {
      final decoded = MeshEnvelope.decode(make().encode())!;
      expect(decoded.id, make().id);
      expect(decoded.ttl, meshDefaultTtl);
      expect(decoded.createdAt, at);
      expect(decoded.keyId, 2);
      expect(decoded.sealed, sealedBody);
    });

    test('base64 round-trips too, for text transports', () {
      final decoded = MeshEnvelope.fromBase64(make().toBase64())!;
      expect(decoded.sealed, sealedBody);
      expect(decoded.createdAt, at);
    });

    test('the frame is small enough for a short-range radio', () {
      expect(make().encode().length, lessThan(meshMaxEnvelopeBytes));
    });
  });

  group('it carries nothing but routing metadata', () {
    test('the frame contains only the id, ttl, time, key id and the body', () {
      // 29 bytes of header. If a field is ever added, this fails, and whoever
      // adds it has to justify letting a stranger's phone see it.
      expect(make().encode().length, 29 + sealedBody.length);
    });

    test('nothing operational is legible in the frame', () {
      final text = utf8.decode(make().encode(), allowMalformed: true);
      for (final leak in ['DURESS', 'Kidnap', 'JOS', 'CRITICAL', '9.89']) {
        expect(text.toUpperCase(), isNot(contains(leak.toUpperCase())));
      }
    });
  });

  group('it will not be crashed by a stranger\'s phone', () {
    test('truncated input returns null rather than throwing', () {
      expect(MeshEnvelope.decode(Uint8List(0)), isNull);
      expect(MeshEnvelope.decode(Uint8List(28)), isNull);
    });

    test('a length that does not match the frame is refused', () {
      final frame = make().encode();
      frame[28] = 0xff; // claim a longer body than is present
      expect(MeshEnvelope.decode(frame), isNull);
    });

    test('an oversized frame is refused', () {
      final huge = MeshEnvelope(
        id: MeshEnvelope.newId(),
        ttl: 4,
        createdAt: at,
        keyId: 1,
        sealed: Uint8List(meshMaxEnvelopeBytes),
      );
      expect(MeshEnvelope.decode(huge.encode()), isNull);
    });

    test('a ttl beyond the ceiling is refused, so nobody can amplify', () {
      final frame = make().encode();
      frame[17] = 200;
      expect(MeshEnvelope.decode(frame), isNull);
    });

    test('a zero ttl is refused', () {
      final frame = make().encode();
      frame[17] = 0;
      expect(MeshEnvelope.decode(frame), isNull);
    });

    test('an absurd timestamp is refused', () {
      final frame = make().encode();
      ByteData.sublistView(frame).setUint64(18, 99999999999999);
      expect(MeshEnvelope.decode(frame), isNull);
    });

    test('a foreign version is refused', () {
      final frame = make().encode();
      frame[0] = 9;
      expect(MeshEnvelope.decode(frame), isNull);
    });

    test('rubbish base64 returns null', () {
      expect(MeshEnvelope.fromBase64('not base64 at all !!'), isNull);
      expect(MeshEnvelope.fromBase64(''), isNull);
    });
  });

  group('identity', () {
    test('a fresh id is 16 bytes and does not repeat', () {
      final a = MeshEnvelope.newId();
      final b = MeshEnvelope.newId();
      expect(a.length, meshIdLength);
      expect(a, isNot(b));
    });

    test('forwarding spends a hop but keeps the identity', () {
      final e = make(ttl: 4);
      final next = e.forwarded()!;
      expect(next.ttl, 3);
      expect(next.idHex, e.idHex);
      expect(next.sealed, e.sealed);
    });

    test('forwarding the last hop yields nothing', () {
      expect(make(ttl: 1).forwarded(), isNull);
    });
  });
}
