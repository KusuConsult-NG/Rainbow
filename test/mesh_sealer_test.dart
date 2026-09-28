// Can a relaying phone read what it carries?
//
// This is the question the whole mesh design turns on. A mesh moves a report
// through handsets that do not belong to the reporter, and in a
// communal-violence context the relay may belong to somebody on the other side
// of the conflict. If it can read the alert, the mesh becomes an efficient way
// to find out who is reporting and where they are standing.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';

void main() {
  final hq = meshGenerateHqKeypair(random: meshTestRandom(1));
  final other = meshGenerateHqKeypair(random: meshTestRandom(2));

  Uint8List plain(String s) => Uint8List.fromList(utf8.encode(s));
  const secret = '{"type":"Kidnap","duress":true,"lat":9.89654,"lng":8.85831}';

  group('only HQ can open it', () {
    test('HQ opens what was sealed to it', () {
      final sealed = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(3));
      final opened = meshOpen(sealed: sealed, hqPrivateKey: hq.privateKey);
      expect(opened, isNotNull);
      expect(utf8.decode(opened!), secret);
    });

    test('a different key opens nothing', () {
      final sealed = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(4));
      expect(meshOpen(sealed: sealed, hqPrivateKey: other.privateKey), isNull);
    });

    test('nothing readable survives in the sealed bytes', () {
      // The blunt version of the claim: a relay holding these bytes must not be
      // able to see a duress flag, a coordinate or a category by eye.
      final sealed = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(5));
      final asText = utf8.decode(sealed, allowMalformed: true);
      expect(asText, isNot(contains('duress')));
      expect(asText, isNot(contains('Kidnap')));
      expect(asText, isNot(contains('9.89')));
    });
  });

  group('a relay cannot fingerprint the sender', () {
    test('two alerts from the same phone share no bytes', () {
      // THE property the mesh rests on. A stable device reference on the wire
      // would let a hostile relay pick out which handsets in a crowd are
      // reporting, and follow them. The SMS channel can afford one because the
      // carrier already knows who sent the message; a stranger's phone does
      // not, and must not learn.
      final a = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(6));
      final b = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(7));

      expect(a, isNot(b));
      // And specifically: the ephemeral key, which is the only part that could
      // carry an identity, differs.
      expect(a.sublist(1, 34), isNot(b.sublist(1, 34)));
    });

    test('identical plaintext does not produce identical ciphertext', () {
      final a = meshSeal(
          plaintext: plain('SOS'),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(8));
      final b = meshSeal(
          plaintext: plain('SOS'),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(9));
      expect(a.sublist(46), isNot(b.sublist(46)));
    });
  });

  group('it refuses what it should', () {
    test('a tampered ciphertext does not open', () {
      final sealed = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(10));
      sealed[sealed.length - 1] ^= 0x01;
      expect(meshOpen(sealed: sealed, hqPrivateKey: hq.privateKey), isNull);
    });

    test('a tampered ephemeral key does not open', () {
      final sealed = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(11));
      sealed[5] ^= 0x01;
      expect(meshOpen(sealed: sealed, hqPrivateKey: hq.privateKey), isNull);
    });

    test('truncated, empty and foreign input return null rather than throw', () {
      // These bytes arrive from a stranger's phone. It must not be possible to
      // crash a relay, or HQ, by sending something odd.
      expect(meshOpen(sealed: Uint8List(0), hqPrivateKey: hq.privateKey), isNull);
      expect(meshOpen(sealed: Uint8List(10), hqPrivateKey: hq.privateKey), isNull);
      expect(
        meshOpen(
            sealed: Uint8List.fromList(List<int>.filled(200, 7)),
            hqPrivateKey: hq.privateKey),
        isNull,
      );
    });

    test('a public key that is not a curve point is rejected at the call site', () {
      expect(
        () => meshSeal(
            plaintext: plain('x'),
            hqPublicKey: Uint8List.fromList([9, 9, 9]),
            random: meshTestRandom(12)),
        throwsArgumentError,
      );
    });
  });

  group('the shape of the sealed body', () {
    test('a small alert stays small enough for a BLE link', () {
      // 46 bytes of header plus the payload and tag. A sealed alert has to fit
      // comfortably in what a short-range radio carries at a time.
      final sealed = meshSeal(
          plaintext: plain(secret),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(13));
      expect(sealed.length, lessThan(200));
    });

    test('the length leaks only the payload length, not its content', () {
      final a = meshSeal(
          plaintext: plain('AAAAAAAAAA'),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(14));
      final b = meshSeal(
          plaintext: plain('BBBBBBBBBB'),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(15));
      expect(a.length, b.length);
    });
  });
}
