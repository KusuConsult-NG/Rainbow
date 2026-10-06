// The request a phone with a network makes on behalf of everyone it carried for.
//
// The endpoint's side of this is tested in
// hq-dashboard-next/src/app/api/mesh/ingest/route.test.ts against frames the
// Dart encoder produced. This is the other half: that the phone asks in the
// shape the endpoint reads, and reads the answer defensively.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_uplink.dart';

void main() {
  MeshEnvelope envelope(int seed) => MeshEnvelope(
        id: Uint8List.fromList(List<int>.generate(meshIdLength, (i) => (seed * 31 + i) % 256)),
        ttl: meshDefaultTtl,
        createdAt: DateTime.utc(2026, 10, 5, 12),
        keyId: 1,
        sealed: Uint8List.fromList(List<int>.generate(40, (i) => (seed + i) % 256)),
      );

  group('meshIngestBody', () {
    test('carries each envelope as the base64url frame the endpoint decodes', () {
      final a = envelope(1);
      final b = envelope(2);
      final body = jsonDecode(meshIngestBody([a, b])) as Map<String, dynamic>;
      expect(body.keys, ['frames']);
      expect(body['frames'], [a.toBase64(), b.toBase64()]);
      // And the frames round-trip, so HQ reads back the same envelope.
      final first = MeshEnvelope.fromBase64((body['frames'] as List).first as String);
      expect(first?.idHex, a.idHex);
    });

    test('stops at the endpoint limit rather than sending frames it ignores', () {
      final many = [for (var i = 0; i < meshIngestMaxFrames + 5; i++) envelope(i)];
      final body = jsonDecode(meshIngestBody(many)) as Map<String, dynamic>;
      expect((body['frames'] as List).length, meshIngestMaxFrames);
    });

    test('says nothing about the phone that is uploading', () {
      final body = jsonDecode(meshIngestBody([envelope(3)])) as Map<String, dynamic>;
      // No device id, no user, no position: the endpoint takes frames from
      // anybody precisely so the uploader need not be identified.
      expect(body.keys.toSet(), {'frames'});
    });
  });

  group('meshIngestDone', () {
    final id = envelope(4).idHex;

    test('reads the ids HQ is finished with', () {
      expect(meshIngestDone(jsonEncode({'ok': true, 'done': [id]})), {id});
    });

    test('anything unreadable means keep carrying, never a crash', () {
      for (final body in [
        '',
        'not json',
        '[]',
        '{"ok": true}',
        '{"done": "abc"}',
        '{"ok": false, "retryAfter": 60}',
      ]) {
        expect(meshIngestDone(body), isEmpty, reason: body);
      }
    });

    test('ignores entries that are not envelope ids', () {
      final body = jsonEncode({
        'done': [id, 42, null, 'XYZ', id.toUpperCase(), '${id}00'],
      });
      expect(meshIngestDone(body), {id});
    });
  });
}
