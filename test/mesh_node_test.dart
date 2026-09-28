// A crowd, over the real chunking and a faked radio.
//
// The other mesh tests each prove one piece. This proves the schedule: that an
// alert actually moves from the phone that raised it, through phones that cannot
// read it, to a phone that has a network — and that it stops when it should.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/ble_mesh_transport.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/mesh_alert_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_node.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

void main() {
  final hq = meshGenerateHqKeypair(random: meshTestRandom(61));
  final deviceKey =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 13) % 256));
  var now = DateTime.utc(2026, 9, 28, 19);

  MeshEnvelope alert({int seed = 2}) => meshEnvelopeForSmsBody(
        smsBody: encodeSmsAlert(
          payload: SmsAlertPayload(
            categoryCode: 255,
            severityCode: 3,
            sentAt: now,
            localRef: Uint8List.fromList([4, 4, 4, 4, 4, 4]),
            latitude: 9.89,
            longitude: 8.85,
            isDuress: true,
          ),
          key: deviceKey,
          deviceRef: Uint8List.fromList([5, 5, 5, 5]),
          nonce: newSmsNonce(),
        ),
        hqPublicKey: hq.publicKey,
        now: now,
        random: meshTestRandom(seed),
      );

  Future<void> settle() async {
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() => now = DateTime.utc(2026, 9, 28, 19));

  test('a duress alert crosses two strangers to a phone with a network',
      () async {
    // A raises it with no uplink. B and C are strangers. D has data.
    final radios = {
      for (final n in ['a', 'b', 'c', 'd']) n: FakeBleRadio(n),
    };
    final transports = {
      for (final e in radios.entries)
        e.key: BleMeshTransport(e.value, clock: () => now),
    };
    final uploaded = <String>[];
    final nodes = {
      for (final e in transports.entries)
        e.key: MeshNode(
          relay: MeshRelay(clock: () => now),
          transport: e.value,
          // Only D has a network, so only D's callback uploads. Every other node
          // carries it and can do nothing with it.
          onEnvelope: e.key == 'd' ? (env) => uploaded.add(env.idHex) : null,
        ),
    };
    addTearDown(() async {
      for (final t in transports.values) {
        await t.dispose();
      }
      for (final r in radios.values) {
        await r.dispose();
      }
    });

    for (final n in nodes.values) {
      await n.start();
    }

    // A meets B in the street.
    radios['a']!.link(radios['b']!);
    await settle();
    await nodes['a']!.send(alert());
    await settle();
    expect(nodes['b']!.accepted, 1, reason: 'B took it on');
    expect(uploaded, isEmpty, reason: 'B has no network and cannot read it');

    // B cannot read what it is carrying. This is the whole design.
    final carried = nodes['b']!.relay.pending.single;
    expect(meshOpen(sealed: carried.sealed, hqPrivateKey: BigInt.from(3)),
        isNull);
    expect(String.fromCharCodes(carried.sealed).contains('OR1'), isFalse);

    // A walks off; B meets C.
    radios['a']!.unlink(radios['b']!);
    radios['b']!.link(radios['c']!);
    await settle();
    await nodes['b']!.gossip();
    await settle();
    expect(nodes['c']!.accepted, 1);
    expect(nodes['c']!.relay.pending.single.ttl, meshDefaultTtl - 2,
        reason: 'two hops spent: A to B, B to C');

    // C meets D, who has data.
    radios['b']!.unlink(radios['c']!);
    radios['c']!.link(radios['d']!);
    await settle();
    await nodes['c']!.gossip();
    await settle();

    expect(uploaded, hasLength(1), reason: 'D uploaded it to HQ');
    // And once it is delivered, D stops carrying it.
    nodes['d']!.delivered(uploaded.single);
    expect(nodes['d']!.relay.pending, isEmpty);
  });

  test('a node does not take back an envelope it already handled', () async {
    final ra = FakeBleRadio('a');
    final rb = FakeBleRadio('b');
    final ta = BleMeshTransport(ra, clock: () => now);
    final tb = BleMeshTransport(rb, clock: () => now);
    final a = MeshNode(relay: MeshRelay(clock: () => now), transport: ta);
    final b = MeshNode(relay: MeshRelay(clock: () => now), transport: tb);
    addTearDown(() async {
      await ta.dispose();
      await tb.dispose();
      await ra.dispose();
      await rb.dispose();
    });
    await a.start();
    await b.start();
    ra.link(rb);
    await settle();

    await a.send(alert(seed: 3));
    await settle();
    expect(b.accepted, 1);

    // B offers it back to A, repeatedly. Two phones in range bouncing one
    // envelope for ever is the failure this prevents.
    for (var i = 0; i < 3; i++) {
      await b.gossip();
      await settle();
      await a.gossip();
      await settle();
    }
    expect(b.accepted, 1, reason: 'B never took it a second time');
    expect(a.accepted, 0, reason: 'nor did A take back its own');
  });

  test('signing out stops relaying and drops what was held', () async {
    // A phone should not keep carrying strangers' emergencies for somebody who
    // is no longer using the app, and the radio costs battery that is not ours.
    final ra = FakeBleRadio('a');
    final rb = FakeBleRadio('b');
    final ta = BleMeshTransport(ra, clock: () => now);
    final tb = BleMeshTransport(rb, clock: () => now);
    final a = MeshNode(relay: MeshRelay(clock: () => now), transport: ta);
    final b = MeshNode(relay: MeshRelay(clock: () => now), transport: tb);
    addTearDown(() async {
      await ta.dispose();
      await tb.dispose();
      await ra.dispose();
      await rb.dispose();
    });
    await a.start();
    await b.start();
    ra.link(rb);
    await settle();
    await a.send(alert(seed: 4));
    await settle();
    expect(b.relay.length, 1);

    await b.stop();
    expect(b.isRelaying, isFalse);
    expect(b.relay.length, 0);
    expect(tb.peers, isEmpty);

    // And it carries nothing further.
    await a.send(alert(seed: 5));
    await settle();
    expect(b.accepted, 1, reason: 'still just the one from before it stopped');
  });

  test('an alert sealed with nobody in range is still held', () async {
    // The case the mesh exists for: a phone alone. It must not discard the
    // alert simply because there is no peer at the moment it is raised.
    final ra = FakeBleRadio('a');
    final ta = BleMeshTransport(ra, clock: () => now);
    final a = MeshNode(relay: MeshRelay(clock: () => now), transport: ta);
    addTearDown(() async {
      await ta.dispose();
      await ra.dispose();
    });
    await a.start();
    await a.send(alert(seed: 6));
    await settle();
    expect(a.relay.length, 1);
    expect(ra.written, isEmpty);

    // And it goes out the moment somebody walks past.
    final rb = FakeBleRadio('b');
    final tb = BleMeshTransport(rb, clock: () => now);
    final b = MeshNode(relay: MeshRelay(clock: () => now), transport: tb);
    addTearDown(() async {
      await tb.dispose();
      await rb.dispose();
    });
    await b.start();
    ra.link(rb);
    await settle();
    await a.gossip();
    await settle();
    expect(b.accepted, 1);
  });

  test('a stopped node does not gossip', () async {
    final ra = FakeBleRadio('a');
    final ta = BleMeshTransport(ra, clock: () => now);
    final a = MeshNode(relay: MeshRelay(clock: () => now), transport: ta);
    addTearDown(() async {
      await ta.dispose();
      await ra.dispose();
    });
    a.relay.offer(alert(seed: 7));
    await a.gossip();
    expect(ra.written, isEmpty);
  });
}
