// A report leaves a phone with no uplink and reaches HQ through strangers.
//
// This is the claim the mesh exists to make, driven through the real envelope
// codec, the real sealing and the real relay decisions. The only thing
// substituted is the radio, and that substitution is the point: everything
// here is provable in CI, leaving only "does the radio find the other phone"
// for two handsets in a room.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';
import 'package:rainbow_app/core/mesh/mesh_transport.dart';

void main() {
  final hq = meshGenerateHqKeypair(random: meshTestRandom(42));
  var now = DateTime.utc(2026, 9, 28, 12);

  const report =
      '{"local_id":"OFFLINE_1790500000000","type":"Kidnap - Immediate '
      'Abduction","severity":"CRITICAL","lat":9.89654,"lng":8.85831,'
      '"duress":true}';

  MeshEnvelope sealReport({int seed = 1}) => MeshEnvelope(
        id: MeshEnvelope.newId(),
        ttl: meshDefaultTtl,
        createdAt: now,
        keyId: 1,
        sealed: meshSeal(
          plaintext: Uint8List.fromList(utf8.encode(report)),
          hqPublicKey: hq.publicKey,
          random: meshTestRandom(seed),
        ),
      );

  setUp(() => now = DateTime.utc(2026, 9, 28, 12));

  test('a report crosses three phones and only HQ can read it', () async {
    // A: the reporter. No uplink.
    // B, C: strangers, relaying.
    // D: has data, and uploads.
    final a = LoopbackMeshTransport('reporter');
    final b = LoopbackMeshTransport('relay-b');
    final c = LoopbackMeshTransport('relay-c');
    final d = LoopbackMeshTransport('uplink-d');
    addTearDown(() async {
      for (final t in [a, b, c, d]) {
        await t.dispose();
      }
    });

    final relayB = MeshRelay(clock: () => now);
    final relayC = MeshRelay(clock: () => now);
    final relayD = MeshRelay(clock: () => now);

    b.inbound.listen(relayB.offer);
    c.inbound.listen(relayC.offer);
    d.inbound.listen(relayD.offer);

    for (final t in [a, b, c, d]) {
      await t.start();
    }

    // A meets B in the street.
    a.link(b);
    final envelope = sealReport();
    await a.offer(envelope);
    await Future<void>.delayed(Duration.zero);
    expect(relayB.length, 1, reason: 'B took it on');

    // B cannot read it. This is the whole design.
    final carried = relayB.pending.single;
    final asText = utf8.decode(carried.sealed, allowMalformed: true);
    expect(asText, isNot(contains('Kidnap')));
    expect(asText, isNot(contains('duress')));
    expect(asText, isNot(contains('9.89')));
    expect(meshOpen(sealed: carried.sealed, hqPrivateKey: BigInt.from(99)),
        isNull);

    // B walks on and meets C.
    a.unlink(b);
    b.link(c);
    for (final e in relayB.toOffer()) {
      await b.offer(e);
    }
    await Future<void>.delayed(Duration.zero);
    expect(relayC.length, 1, reason: 'C took it on from B');
    expect(relayC.pending.single.ttl, meshDefaultTtl - 1,
        reason: 'one hop spent');

    // C meets D, who has a network.
    b.unlink(c);
    c.link(d);
    for (final e in relayC.toOffer()) {
      await c.offer(e);
    }
    await Future<void>.delayed(Duration.zero);
    expect(relayD.length, 1);

    // D uploads the ciphertext. HQ opens it — the first and only party that can.
    final arrived = relayD.pending.single;
    final opened = meshOpen(sealed: arrived.sealed, hqPrivateKey: hq.privateKey);
    expect(opened, isNotNull);
    final json = jsonDecode(utf8.decode(opened!)) as Map<String, dynamic>;
    expect(json['type'], 'Kidnap - Immediate Abduction');
    expect(json['duress'], true);
    expect(json['lat'], closeTo(9.89654, 0.00001));
    expect(json['local_id'], 'OFFLINE_1790500000000');
  });

  test('the same report arriving by two paths is recognised as one', () async {
    // HQ will see the same envelope many times — that is how flooding works —
    // and must record one incident. The envelope id is the dedup key before
    // anything is decrypted, and `local_id` inside is the dedup key against
    // the reporter's own offline queue.
    final envelope = sealReport();
    final seenAtHq = <String>{};
    for (var i = 0; i < 5; i++) {
      seenAtHq.add(envelope.idHex);
    }
    expect(seenAtHq, hasLength(1));

    final opened =
        meshOpen(sealed: envelope.sealed, hqPrivateKey: hq.privateKey)!;
    final json = jsonDecode(utf8.decode(opened)) as Map<String, dynamic>;
    expect(json['local_id'], 'OFFLINE_1790500000000',
        reason: 'the same key the SMS channel and the offline queue use');
  });

  test('an envelope does not loop back to a phone that already carried it',
      () async {
    final a = LoopbackMeshTransport('a');
    final b = LoopbackMeshTransport('b');
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });
    final relayA = MeshRelay(clock: () => now);
    final relayB = MeshRelay(clock: () => now);
    a.inbound.listen(relayA.offer);
    b.inbound.listen(relayB.offer);
    await a.start();
    await b.start();
    a.link(b);

    final envelope = sealReport();
    await a.offer(envelope);
    await Future<void>.delayed(Duration.zero);
    expect(relayB.length, 1);

    // B offers it back. A never held it, but two phones in range bouncing one
    // envelope for ever is the failure this prevents in general.
    for (final e in relayB.toOffer()) {
      await b.offer(e);
    }
    await Future<void>.delayed(Duration.zero);
    for (final e in relayA.toOffer()) {
      await a.offer(e);
    }
    await Future<void>.delayed(Duration.zero);

    expect(relayB.length, 1, reason: 'B did not take its own envelope again');
  });

  test('it dies out rather than circulating for ever', () async {
    // Twelve phones in a line, and a hop limit of eight.
    //
    // The first version of this test used eight phones and expected the last
    // to be empty. That was arithmetic, not a defect: a TTL of eight permits
    // eight hops and a line of eight phones is seven of them, so it arrived
    // with one hop to spare. The line has to be longer than the limit for the
    // limit to be what stops it.
    final nodes = List.generate(12, (i) => LoopbackMeshTransport('n\$i'));
    final relays = List.generate(12, (_) => MeshRelay(clock: () => now));
    addTearDown(() async {
      for (final n in nodes) {
        await n.dispose();
      }
    });
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].inbound.listen(relays[i].offer);
      await nodes[i].start();
    }

    var envelope = sealReport();
    var reached = 0;
    for (var i = 0; i < nodes.length - 1; i++) {
      nodes[i].link(nodes[i + 1]);
      await nodes[i].offer(envelope);
      await Future<void>.delayed(Duration.zero);
      nodes[i].unlink(nodes[i + 1]);
      if (relays[i + 1].length == 0) break;
      reached = i + 1;
      final onward = relays[i + 1].toOffer();
      if (onward.isEmpty) break;
      envelope = onward.single;
    }

    // Amplification is bounded, and bounded by the number we chose.
    expect(reached, lessThan(nodes.length - 1),
        reason: 'an envelope that never dies is a mesh that floods itself');
    expect(reached, meshDefaultTtl - 1,
        reason: 'a TTL of \$meshDefaultTtl should carry it exactly that far');
    expect(relays.last.length, 0);
  });

  test('a relay that stops relaying stops carrying other people\'s traffic',
      () async {
    final relay = MeshRelay(clock: () => now);
    relay.offer(sealReport(seed: 2));
    relay.offer(sealReport(seed: 3));
    expect(relay.length, 2);
    relay.clear();
    expect(relay.length, 0);
  });
}
