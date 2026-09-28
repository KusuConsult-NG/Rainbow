// The mesh over BLE, with the radio faked and nothing else.
//
// The fake radio is not a mock: it enforces the MTU, it can fail a write, it can
// drop one silently, and it can disconnect in the middle of a frame — the four
// things a real link does that break naive chunking. Passing here does not prove
// the radio works. Failing here proves it cannot.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/ble_mesh_transport.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/mesh_alert_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

void main() {
  final hq = meshGenerateHqKeypair(random: meshTestRandom(41));
  final deviceKey =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 3) % 256));
  var now = DateTime.utc(2026, 9, 28, 18);

  MeshEnvelope alert({int seed = 2}) => meshEnvelopeForSmsBody(
        smsBody: encodeSmsAlert(
          payload: SmsAlertPayload(
            categoryCode: 0,
            severityCode: 3,
            sentAt: now,
            localRef: Uint8List.fromList([7, 7, 7, 7, 7, 7]),
            latitude: 9.9,
            longitude: 8.9,
          ),
          key: deviceKey,
          deviceRef: Uint8List.fromList([9, 9, 9, 9]),
          nonce: newSmsNonce(),
        ),
        hqPublicKey: hq.publicKey,
        now: now,
        random: meshTestRandom(seed),
      );

  /// Lets the queue pump and the streams deliver.
  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() => now = DateTime.utc(2026, 9, 28, 18));

  test('an alert crosses to a phone in range, at the worst MTU there is', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });

    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);

    radioA.link(radioB);
    await a.start();
    await b.start();
    await settle();
    expect(a.peers, ['b'], reason: 'a peer already in range is seen');

    final envelope = alert();
    await a.offer(envelope);
    await settle();

    expect(received, hasLength(1));
    expect(received.single.idHex, envelope.idHex);
    expect(radioA.written.length, 11, reason: '166 bytes at 16 per write');
    expect(radioA.written.every((c) => c.length <= bleMinimumMtu - 3), isTrue);

    // And what arrived is still openable only by HQ.
    expect(
        meshOpen(sealed: received.single.sealed, hqPrivateKey: hq.privateKey),
        isNotNull);
  });

  test('a negotiated MTU sends it in one write', () async {
    final radioA = FakeBleRadio('a', mtu: 517);
    final radioB = FakeBleRadio('b', mtu: 517);
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);
    radioA.link(radioB);
    await a.start();
    await b.start();
    await a.offer(alert());
    await settle();
    expect(radioA.written, hasLength(1));
    expect(received, hasLength(1));
  });

  test('a peer that arrives later still gets what is offered after', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);

    await a.start();
    await b.start();
    // Offered with nobody in range: goes nowhere, and that is correct — the
    // relay keeps holding it.
    await a.offer(alert(seed: 3));
    await settle();
    expect(received, isEmpty);

    radioA.link(radioB);
    await settle();
    await a.offer(alert(seed: 4));
    await settle();
    expect(received, hasLength(1));
  });

  test('a disconnect mid-frame loses that frame and not the next one', () async {
    // The commonest thing that happens in a crowd: somebody walks off halfway
    // through. The half-frame must not be completed later by chunks from a
    // different frame, which would decode as neither.
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);

    radioA.link(radioB);
    await a.start();
    await b.start();
    await settle();

    // Six chunks reach B, then they lose each other.
    radioA.dropWrites = 5;
    await a.offer(alert(seed: 5));
    await settle();
    expect(received, isEmpty);
    radioA.unlink(radioB);
    await settle();

    // They meet again and a different alert goes across.
    radioA.link(radioB);
    await settle();
    final second = alert(seed: 6);
    await a.offer(second);
    await settle();

    expect(received, hasLength(1));
    expect(received.single.idHex, second.idHex,
        reason: 'the survivor is the whole second frame, not a splice');
  });

  test('a failed write abandons that frame, not the peer', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);

    radioA.link(radioB);
    await a.start();
    await b.start();
    await settle();

    radioA.failWrites = 1;
    await a.offer(alert(seed: 7));
    await settle();
    expect(a.failedWrites, 1);
    expect(received, isEmpty);

    final next = alert(seed: 8);
    await a.offer(next);
    await settle();
    expect(received.map((e) => e.idHex), [next.idHex],
        reason: 'the link is still usable after a failed write');
  });

  test('one dead peer does not stop the one that works', () async {
    // The whole point of relaying: the phone that still has a link is the one
    // carrying the alert out.
    final radioA = FakeBleRadio('a');
    final dead = FakeBleRadio('dead');
    final good = FakeBleRadio('good');
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(good, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await dead.dispose();
      await good.dispose();
    });
    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);

    radioA.link(dead);
    radioA.link(good);
    await a.start();
    await b.start();
    await dead.start();
    await settle();
    expect(a.peers, hasLength(2));

    // The dead link is named, so this asserts the thing that matters rather
    // than "one of them probably worked". The first version of this test used a
    // global write-failure count, which failed whichever peer happened to be
    // written to first — so it could only assert `anyOf(0, 1)`, which is true of
    // a transport that does not work at all.
    radioA.deadLinks.add('dead');
    final envelope = alert(seed: 9);
    await a.offer(envelope);
    await settle();

    expect(a.failedWrites, 1, reason: 'the dead link ate exactly one frame');
    expect(received.map((e) => e.idHex), [envelope.idHex],
        reason: 'and the phone that still had a link carried the alert out');
  });

  test('a peer that never drains cannot make this phone grow', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    radioA.link(radioB);
    await a.start();
    await radioB.start();
    await settle();

    // Every write fails, so nothing drains, while frames keep being offered.
    //
    // Offered WITHOUT awaiting each one, which is the whole point: the first
    // version of this test awaited every offer, so the pump got a turn between
    // them, kept up, and the queue never filled — it proved nothing. Real
    // pressure is many frames arriving before the radio has drained one, which
    // is exactly what a burst of alerts in a crowd looks like.
    radioA.failWrites = 10000;
    final envelope = alert(seed: 20);
    final offers = [for (var i = 0; i < 20; i++) a.offer(envelope)];
    await Future.wait(offers);
    await settle();
    expect(a.droppedFrames, greaterThan(0),
        reason: 'the queue is bounded and drops the OLDEST, so the freshest '
            'alert is the one kept');
  });

  test('rubbish from a peer is counted and discarded, never assembled', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    final received = <MeshEnvelope>[];
    b.inbound.listen(received.add);
    radioA.link(radioB);
    await b.start();
    await radioA.start();
    await settle();

    // A peer claiming a 200-chunk message, a bad version, a header with no
    // payload, and a sequence past the end.
    for (final bad in [
      Uint8List.fromList([1, 1, 0, 200, ...List<int>.filled(16, 1)]),
      Uint8List.fromList([9, 1, 0, 2, 1, 2, 3, 4]),
      Uint8List.fromList([1, 1, 0, 1]),
      Uint8List.fromList([1, 2, 9, 3, 1, 2, 3, 4]),
    ]) {
      await radioA.write('b', bad);
    }
    await settle();

    expect(received, isEmpty);
    expect(b.rejectedChunks, 4);
  });

  test('stopping releases the radio, because relaying costs battery', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    radioA.link(radioB);
    await a.start();
    // The peer's radio has to be running too, or there is nothing in range: the
    // fake only reports a link when both ends are started, which is the honest
    // behaviour and caught this test's own omission.
    await radioB.start();
    await settle();
    expect(a.peers, hasLength(1));

    await a.stop();
    expect(a.peers, isEmpty);
    // And an offer after stopping is a no-op rather than an error, because
    // sign-out and an in-flight alert can happen in either order.
    await a.offer(alert(seed: 30));
    await settle();
    expect(radioA.written, isEmpty);
  });

  test('two nodes can talk at once without contaminating each other', () async {
    final radioA = FakeBleRadio('a');
    final radioB = FakeBleRadio('b');
    final a = BleMeshTransport(radioA, clock: () => now);
    final b = BleMeshTransport(radioB, clock: () => now);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await radioA.dispose();
      await radioB.dispose();
    });
    final atA = <MeshEnvelope>[];
    final atB = <MeshEnvelope>[];
    a.inbound.listen(atA.add);
    b.inbound.listen(atB.add);
    radioA.link(radioB);
    await a.start();
    await b.start();
    await settle();

    final fromA = alert(seed: 51);
    final fromB = alert(seed: 52);
    await a.offer(fromA);
    await b.offer(fromB);
    await settle();

    expect(atB.map((e) => e.idHex), [fromA.idHex]);
    expect(atA.map((e) => e.idHex), [fromB.idHex]);
  });
}
