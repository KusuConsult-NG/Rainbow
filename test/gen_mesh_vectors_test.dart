// Not a test: a generator, run as one because `flutter test` is the only way
// to execute Dart with this project's dependencies resolved.
//
// It writes the vectors that `hq-dashboard-next` opens, so the Dart sealer and
// the TypeScript one are proven to agree on real bytes rather than on two
// readings of the same prose. Exactly the arrangement the SMS codec uses, and
// for the same reason: ECIES has four places to disagree silently — point
// compression, the HKDF info string, whether the shared secret is left-padded,
// and where the GCM tag lives — and every one of them fails as
// "authentication failed" with no clue which.
//
//   flutter test test/gen_sms_vectors_test.dart   # first: the inner payload
//   flutter test test/gen_mesh_vectors_test.dart  # then: the envelope
//
// The HQ keypair here is derived from a fixed seed and is TEST MATERIAL. The
// real one is generated offline and its private half never leaves the HQ
// server; see docs/OFFLINE_CHANNELS_DESIGN.md.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_alert_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bigIntToBytes(BigInt v, int length) {
  final out = Uint8List(length);
  var x = v;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

void main() {
  test('write the cross-implementation mesh vectors', () {
    // The inner payload comes from the SMS vectors rather than being rebuilt
    // here, so the two fixtures cannot describe different alerts. If that file
    // is missing or stale, regenerate it first.
    final smsFile = File('test/fixtures/sms_alert_vectors.json');
    expect(smsFile.existsSync(), isTrue,
        reason: 'run flutter test test/gen_sms_vectors_test.dart first');
    final sms = jsonDecode(smsFile.readAsStringSync()) as Map<String, dynamic>;
    final smsCases = (sms['cases'] as Map).cast<String, String>();

    final hq = meshGenerateHqKeypair(random: meshTestRandom(7));
    final other = meshGenerateHqKeypair(random: meshTestRandom(8));
    final at = DateTime.utc(2026, 9, 28, 15, 0, 0);

    MeshEnvelope seal(String body,
            {int seed = 11, int ttl = meshDefaultTtl, Uint8List? key}) =>
        meshEnvelopeForSmsBody(
          smsBody: body,
          hqPublicKey: key ?? hq.publicKey,
          ttl: ttl,
          now: at,
          random: meshTestRandom(seed),
          idRandom: _FixedRandom(seed),
        );

    final ordinary = seal(smsCases['ordinary']!);
    final duress = seal(smsCases['duress']!, seed: 12);
    // What a relay actually hands on: one hop spent. HQ must not care.
    final forwarded = ordinary.forwarded()!;
    // A relay that alters the body it cannot read. HQ must refuse it.
    final tamperedSealed = Uint8List.fromList(ordinary.sealed)
      ..[ordinary.sealed.length - 1] ^= 0xFF;
    final tampered = MeshEnvelope(
      id: ordinary.id,
      ttl: ordinary.ttl,
      createdAt: ordinary.createdAt,
      keyId: ordinary.keyId,
      sealed: tamperedSealed,
    );
    // Sealed to a key HQ does not hold — a rotation gone wrong, or somebody
    // else's deployment. Must be indistinguishable from a forgery.
    final foreign = seal(smsCases['ordinary']!, seed: 13, key: other.publicKey);

    final blob = {
      'generatedBy': 'test/gen_mesh_vectors_test.dart',
      'note': 'TEST KEYPAIR from a fixed seed. Not the production HQ key.',
      'hqPublicKeyHex': _hex(hq.publicKey),
      'hqPrivateKeyHex': _hex(_bigIntToBytes(hq.privateKey, 32)),
      'createdAtIso': at.toIso8601String(),
      'innerBodies': {
        'ordinary': smsCases['ordinary'],
        'duress': smsCases['duress'],
      },
      'frames': {
        'ordinary': ordinary.toBase64(),
        'duress': duress.toBase64(),
        'forwarded': forwarded.toBase64(),
        'tampered': tampered.toBase64(),
        'sealedToAnotherKey': foreign.toBase64(),
      },
      'ids': {
        'ordinary': ordinary.idHex,
        'duress': duress.idHex,
      },
      'frameBytes': {
        for (final e in {
          'ordinary': ordinary,
          'duress': duress,
        }.entries)
          e.key: e.value.encode().length,
      },
    };

    File('test/fixtures/mesh_envelope_vectors.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(blob)}\n');

    // A frame that no relay would carry is a vector that proves nothing.
    for (final n in (blob['frameBytes']! as Map).values) {
      expect(n as int, lessThan(meshMaxEnvelopeBytes));
    }
  });
}

/// A fixed sequence, so envelope ids are stable across regenerations.
///
/// Envelope ids must be unpredictable in production — that is why
/// `MeshEnvelope.newId` defaults to `Random.secure()` — but a vector file whose
/// ids change on every run produces a diff on every run and stops being
/// reviewable.
class _FixedRandom implements Random {
  _FixedRandom(this.seed);

  final int seed;
  int _n = 0;

  @override
  int nextInt(int max) => (seed * 31 + _n++ * 17) % max;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 20) / (1 << 20);
}
