// Both layers of an offline alert, on one phone.
//
// The mesh seals to HQ's PUBLIC key, which anybody has, so the outer layer
// proves nothing about who sealed it. The inner layer is the SMS body,
// authenticated by a per-device key HQ issued. Between them: relays that can
// carry the alert and learn nothing, and an HQ that can prove which handset
// raised it.
//
// These tests assert the join between the two, which is the part neither
// layer's own tests cover.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_alert_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

void main() {
  final hq = meshGenerateHqKeypair(random: meshTestRandom(21));
  final deviceKey =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 11) % 256));
  final deviceRef = Uint8List.fromList([0x0A, 0x0B, 0x0C, 0x0D]);
  final now = DateTime.utc(2026, 9, 28, 16);

  String bodyFor({bool duress = false, int nonceSeed = 0}) => encodeSmsAlert(
        payload: SmsAlertPayload(
          categoryCode: duress ? 255 : 0,
          severityCode: 3,
          sentAt: now,
          localRef: Uint8List.fromList([9, 8, 7, 6, 5, 4]),
          latitude: 9.89654,
          longitude: 8.85831,
          isDuress: duress,
        ),
        key: deviceKey,
        deviceRef: deviceRef,
        nonce: Uint8List.fromList(
            List<int>.generate(smsNonceLength, (i) => i + nonceSeed)),
      );

  MeshEnvelope wrap(String body, {int seed = 3}) => meshEnvelopeForSmsBody(
        smsBody: body,
        hqPublicKey: hq.publicKey,
        now: now,
        random: meshTestRandom(seed),
        idRandom: Random(seed),
      );

  test('HQ opens the envelope and gets the alert, authenticated', () {
    final body = bodyFor();
    final envelope = wrap(body);

    final opened =
        meshOpen(sealed: envelope.sealed, hqPrivateKey: hq.privateKey);
    expect(opened, isNotNull);
    expect(ascii.decode(opened!), body);

    // And the inner layer still authenticates, which is what stops a relay —
    // or anyone else with the public key — inventing an emergency.
    final decoded = decodeSmsAlert(body: ascii.decode(opened), key: deviceKey);
    expect(decoded.payload, isNotNull);
    expect(decoded.payload!.latitude, closeTo(9.89654, 0.00001));
    expect(_hex(decoded.deviceRef!), '0a0b0c0d');
  });

  test('a duress alert survives the trip and stays a duress alert', () {
    final envelope = wrap(bodyFor(duress: true), seed: 4);
    final opened =
        ascii.decode(meshOpen(sealed: envelope.sealed, hqPrivateKey: hq.privateKey)!);
    expect(decodeSmsAlert(body: opened, key: deviceKey).payload!.isDuress, isTrue);
  });

  test('the frame carries no trace of the body it holds', () {
    // Not even the prefix. `OR1` in a frame would tell a relay it is carrying
    // an alert rather than anything else, which is the first half of knowing
    // who is reporting.
    final envelope = wrap(bodyFor(duress: true));
    final frame = latin1.decode(envelope.encode(), allowInvalid: true);
    for (final leak in ['OR1', 'SOS', '9.89']) {
      expect(frame, isNot(contains(leak)));
    }
  });

  test('a relay cannot open it, whatever key it tries', () {
    final envelope = wrap(bodyFor());
    expect(meshOpen(sealed: envelope.sealed, hqPrivateKey: BigInt.from(7)),
        isNull);
    expect(
        meshOpen(
            sealed: envelope.sealed,
            hqPrivateKey: meshGenerateHqKeypair(random: meshTestRandom(99))
                .privateKey),
        isNull);
  });

  test('two alerts from the same handset share no bytes', () {
    // The property that decides whether the mesh protects reporters or betrays
    // them. A stable identifier would let a hostile relay fingerprint which
    // phones in a crowd are reporting and follow them.
    final a = wrap(bodyFor(), seed: 5);
    final b = wrap(bodyFor(nonceSeed: 50), seed: 6);
    expect(a.sealed, isNot(equals(b.sealed)));
    expect(a.idHex, isNot(b.idHex));
    // Same handset, same device key, same HQ key — and the ephemeral halves
    // differ, so the sealed bodies have nothing in common from byte one.
    expect(a.sealed.sublist(1, 20), isNot(equals(b.sealed.sublist(1, 20))));
  });

  test('the same alert sealed twice is two envelopes, not one', () {
    // Which means HQ dedups on the envelope id AND on local_id inside. Neither
    // check replaces the other: this pair would pass the first and be caught by
    // the second.
    final a = wrap(bodyFor(), seed: 7);
    final b = wrap(bodyFor(), seed: 8);
    expect(a.idHex, isNot(b.idHex));
    final openedA =
        ascii.decode(meshOpen(sealed: a.sealed, hqPrivateKey: hq.privateKey)!);
    final openedB =
        ascii.decode(meshOpen(sealed: b.sealed, hqPrivateKey: hq.privateKey)!);
    expect(openedA, openedB, reason: 'the same incident, twice');
  });

  test('a sealed alert fits a radio that carries a few hundred bytes', () {
    // BLE was chosen as the cross-platform baseline on the strength of this
    // number. If a change pushed a frame over the cap, every relay would drop
    // it on sight and the mesh would fail silently in the field.
    final frame = wrap(bodyFor()).encode();
    expect(frame.length, lessThan(200));
    expect(frame.length, lessThan(meshMaxEnvelopeBytes));
  });

  test('a relay accepts it, which is the only opinion a relay may have', () {
    final relay = MeshRelay(clock: () => now);
    final decision = relay.offer(wrap(bodyFor()));
    expect(decision.action, MeshAction.accepted);
    expect(relay.length, 1);
  });

  test('a frame survives encoding and decoding unchanged', () {
    final envelope = wrap(bodyFor());
    final round = MeshEnvelope.fromBase64(envelope.toBase64());
    expect(round, isNotNull);
    expect(round!.idHex, envelope.idHex);
    expect(round.sealed, envelope.sealed);
    expect(
        ascii.decode(meshOpen(sealed: round.sealed, hqPrivateKey: hq.privateKey)!),
        bodyFor());
  });

  test('an empty body is a programming error, not a frame', () {
    expect(
      () => meshEnvelopeForSmsBody(smsBody: '', hqPublicKey: hq.publicKey),
      throwsArgumentError,
    );
  });

  test('the envelope says which HQ key sealed it, so keys can rotate', () {
    final envelope = meshEnvelopeForSmsBody(
      smsBody: bodyFor(),
      hqPublicKey: hq.publicKey,
      keyId: 4,
      now: now,
      random: meshTestRandom(9),
    );
    expect(envelope.keyId, 4);
    expect(MeshEnvelope.fromBase64(envelope.toBase64())!.keyId, 4);
  });

  test('it starts with the full hop allowance', () {
    expect(wrap(bodyFor()).ttl, meshDefaultTtl);
  });
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
