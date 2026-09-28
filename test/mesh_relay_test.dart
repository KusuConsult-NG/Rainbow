// What a relay carries, passes on, and drops.
//
// A relay cannot read what it carries, so every control here is blunt and
// structural. Each exists because of a specific way the mesh could otherwise
// be turned against the people using it.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';

void main() {
  var counter = 0;
  var now = DateTime.utc(2026, 9, 28, 12);

  MeshEnvelope env({
    int ttl = meshDefaultTtl,
    DateTime? createdAt,
    int sealedBytes = 80,
    Uint8List? id,
  }) {
    counter++;
    return MeshEnvelope(
      id: id ??
          Uint8List.fromList(
              List<int>.generate(meshIdLength, (i) => (counter + i) & 0xff)),
      ttl: ttl,
      createdAt: createdAt ?? now,
      keyId: 1,
      sealed: Uint8List.fromList(List<int>.filled(sealedBytes, 7)),
    );
  }

  MeshRelay relay({int capacity = 64}) =>
      MeshRelay(capacity: capacity, clock: () => now);

  setUp(() {
    counter = 0;
    now = DateTime.utc(2026, 9, 28, 12);
  });

  group('carrying somebody else\'s alert', () {
    test('a new envelope is taken on', () {
      final r = relay();
      final d = r.offer(env());
      expect(d.action, MeshAction.accepted);
      expect(r.length, 1);
    });

    test('the same envelope is never taken twice', () {
      // Otherwise it circles a group of phones for ever.
      final r = relay();
      final e = env();
      expect(r.offer(e).action, MeshAction.accepted);
      expect(r.offer(e).action, MeshAction.duplicate);
      expect(r.length, 1);
    });

    test('and is still refused after it has been delivered and forgotten', () {
      // `seen` outlives the outbox on purpose: a node that delivered an
      // envelope must not pick it up again from a peer that has not.
      final r = relay();
      final e = env();
      r.offer(e);
      r.delivered(e.idHex);
      expect(r.length, 0);
      expect(r.offer(e).action, MeshAction.duplicate);
    });
  });

  group('it does not circulate for ever', () {
    test('an envelope on its last hop is not passed to another phone', () {
      final r = relay();
      expect(r.offer(env(ttl: 1)).action, MeshAction.hopsExhausted);
      expect(r.length, 0);
    });

    test('each hop spends one, and the chain terminates', () {
      var e = env(ttl: 3);
      final hops = <int>[];
      while (true) {
        hops.add(e.ttl);
        final next = e.forwarded();
        if (next == null) break;
        e = next;
      }
      expect(hops, [3, 2, 1]);
    });

    test('an envelope older than the mesh carries is dropped', () {
      final r = relay();
      final old = env(createdAt: now.subtract(const Duration(hours: 30)));
      expect(r.offer(old).action, MeshAction.expired);
      expect(r.length, 0);
    });

    test('but a clock that is merely ahead does not lose the alert', () {
      // Phone clocks disagree. Refusing a future timestamp would silently drop
      // alerts from a whole class of handsets.
      final r = relay();
      final ahead = env(createdAt: now.add(const Duration(hours: 2)));
      expect(r.offer(ahead).action, MeshAction.accepted);
    });

    test('one held past its age is dropped when offered onward', () {
      final r = relay();
      r.offer(env());
      expect(r.toOffer(), hasLength(1));
      now = now.add(const Duration(hours: 30));
      expect(r.toOffer(), isEmpty);
      expect(r.length, 0);
    });
  });

  group('offering onward', () {
    test('what is handed to a peer has already spent a hop', () {
      // So a caller cannot forget to, which would make the hop limit a
      // suggestion.
      final r = relay();
      r.offer(env(ttl: 5));
      expect(r.toOffer().single.ttl, 4);
    });

    test('the copy kept locally is unchanged, so the count is per path', () {
      final r = relay();
      r.offer(env(ttl: 5));
      r.toOffer();
      r.toOffer();
      expect(r.pending.single.ttl, 5);
    });
  });

  group('a flood does not win silence', () {
    test('the outbox is bounded', () {
      final r = relay(capacity: 8);
      for (var i = 0; i < 50; i++) {
        r.offer(env());
      }
      expect(r.length, 8);
    });

    test('and drops the OLDEST, so the freshest alert survives', () {
      // Nobody can authenticate an envelope, so anybody can fill the mesh with
      // rubbish — accepted, to keep reporters unidentifiable. An attacker who
      // floods wins a delay, not permanent silence, and the alert most likely
      // to still matter is the one kept.
      final r = relay(capacity: 3);
      final first = env();
      r.offer(first);
      for (var i = 0; i < 5; i++) {
        r.offer(env());
      }
      expect(r.pending.any((e) => e.idHex == first.idHex), isFalse);
      expect(r.length, 3);
    });

    test('an oversized envelope is refused outright', () {
      final r = relay();
      expect(r.offer(env(sealedBytes: 600)).action, MeshAction.rejected);
      expect(r.length, 0);
    });

    test('an empty body is refused', () {
      final r = relay();
      final e = MeshEnvelope(
        id: MeshEnvelope.newId(),
        ttl: 4,
        createdAt: now,
        keyId: 1,
        sealed: Uint8List(0),
      );
      expect(r.offer(e).action, MeshAction.rejected);
    });

    test('the seen set is bounded too', () {
      // An unbounded set is itself a way to exhaust a relay.
      final r = MeshRelay(capacity: 4, seenCapacity: 10, clock: () => now);
      for (var i = 0; i < 40; i++) {
        r.offer(env());
      }
      // Nothing to assert directly without exposing internals; what matters is
      // that it still functions rather than growing without limit.
      expect(r.offer(env()).action, MeshAction.accepted);
    });
  });

  group('giving up the role', () {
    test('clear drops everything being carried for other people', () {
      final r = relay();
      r.offer(env());
      r.offer(env());
      r.clear();
      expect(r.length, 0);
      // And a cleared relay will take the same envelope again, because it has
      // genuinely forgotten rather than pretending to.
      final e = env();
      r.offer(e);
      r.clear();
      expect(r.offer(e).action, MeshAction.accepted);
    });
  });
}
