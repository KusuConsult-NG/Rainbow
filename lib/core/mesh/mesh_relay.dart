/// Deciding what to carry, what to pass on, and what to drop.
///
/// A relay cannot read what it carries — that is the whole design — so it
/// cannot judge an envelope on its contents. Every control here is therefore
/// blunt and structural, and each one exists because of a specific way the
/// mesh could otherwise be turned against the people using it.
///
/// | control        | what it prevents                                      |
/// |----------------|-------------------------------------------------------|
/// | deduplication  | an envelope circling a group of phones for ever        |
/// | hop limit      | unbounded amplification of one message                 |
/// | age limit      | an envelope that keeps finding fresh relays            |
/// | size cap       | the mesh used as a transport for something it is not   |
/// | bounded outbox | a flood crowding out the real alert behind it          |
///
/// The last one is the one worth dwelling on. Nobody can authenticate an
/// envelope, so anybody can fill the mesh with rubbish. **We accept that, to
/// keep reporters unidentifiable** — a signature would fix flooding and would
/// identify the sender to every relay, which is the attack the design exists
/// to prevent. So the outbox is bounded and, when it is full, it drops the
/// OLDEST entry rather than refusing the newest. An attacker who fills it wins
/// a delay; they do not win permanent silence, and the freshest alert — the
/// one most likely to still matter — is always the one kept.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';

/// What a relay decided to do with an envelope, and why.
enum MeshAction {
  /// Never seen; stored and will be offered onward.
  accepted,

  /// Seen before. Dropped without being stored again.
  duplicate,

  /// Out of hops.
  hopsExhausted,

  /// Older than the mesh carries.
  expired,

  /// Malformed, too large, or otherwise not something we carry.
  rejected,
}

/// The result of offering an envelope to a relay.
@immutable
class MeshDecision {
  /// Creates a decision.
  const MeshDecision(this.action, this.because);

  /// What happened.
  final MeshAction action;

  /// A short reason, for the log.
  final String because;

  /// Whether the envelope was taken on.
  bool get stored => action == MeshAction.accepted;
}

/// A node's store-and-forward state.
///
/// Deliberately has no transport, no timer and no I/O: it is a decision
/// machine, so the whole of the mesh's behaviour can be tested without a
/// radio. `now` is injected for the same reason.
class MeshRelay {
  /// Creates a relay.
  ///
  /// [capacity] is how many envelopes this node will hold. Small: a phone is
  /// carrying other people's traffic as a favour, and the cost of that should
  /// be bounded and predictable.
  MeshRelay({
    this.capacity = 64,
    this.maxAge = meshMaxAge,
    this.seenCapacity = 4096,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How many envelopes are held for forwarding.
  final int capacity;

  /// How long an envelope may circulate.
  final Duration maxAge;

  /// How many ids are remembered for deduplication.
  final int seenCapacity;

  final DateTime Function() _clock;

  /// Insertion-ordered, so the oldest is the first to go.
  final LinkedHashMap<String, MeshEnvelope> _outbox = LinkedHashMap();

  /// Ids seen, oldest first. Bounded, because a phone cannot remember for ever
  /// and an unbounded set is itself a way to exhaust a relay.
  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap();

  /// Envelopes waiting to be offered onward.
  List<MeshEnvelope> get pending => List.unmodifiable(_outbox.values);

  /// How many are held.
  int get length => _outbox.length;

  /// Whether this id has been seen before.
  bool hasSeen(String idHex) => _seen.containsKey(idHex);

  /// Offers an envelope to this node.
  MeshDecision offer(MeshEnvelope envelope) {
    final now = _clock();

    if (envelope.sealed.isEmpty ||
        envelope.encode().length > meshMaxEnvelopeBytes) {
      return const MeshDecision(MeshAction.rejected, 'not a size we carry');
    }

    final id = envelope.idHex;
    if (_seen.containsKey(id)) {
      // Seen is separate from held: an envelope that was carried, forwarded
      // and dropped must not be picked up again from the peer we gave it to.
      return const MeshDecision(MeshAction.duplicate, 'already seen');
    }

    final age = now.difference(envelope.createdAt);
    // Tolerate a future timestamp: phone clocks disagree, and refusing an
    // envelope because the sender's clock is ahead would silently drop alerts
    // from a whole class of handsets.
    if (age > maxAge) {
      _remember(id, now);
      return MeshDecision(MeshAction.expired, 'older than ${maxAge.inHours}h');
    }

    if (envelope.ttl <= 1) {
      // It may still be delivered by THIS node if it reaches a network — it
      // simply may not be passed to another phone. Remembering it stops it
      // being taken again.
      _remember(id, now);
      return const MeshDecision(MeshAction.hopsExhausted, 'no hops left');
    }

    _remember(id, now);
    _outbox[id] = envelope;
    while (_outbox.length > capacity) {
      // Oldest first. An attacker who floods wins a delay, not silence, and
      // the freshest alert is the one most likely to still matter.
      _outbox.remove(_outbox.keys.first);
    }
    return const MeshDecision(MeshAction.accepted, 'new');
  }

  /// What this node should offer to a peer it has just met.
  ///
  /// Each is already decremented, so a caller cannot forget to spend the hop.
  List<MeshEnvelope> toOffer() {
    final now = _clock();
    final out = <MeshEnvelope>[];
    for (final entry in _outbox.entries.toList()) {
      if (now.difference(entry.value.createdAt) > maxAge) {
        _outbox.remove(entry.key);
        continue;
      }
      final next = entry.value.forwarded();
      if (next == null) {
        _outbox.remove(entry.key);
        continue;
      }
      out.add(next);
    }
    return out;
  }

  /// Forgets an envelope once it has reached a network.
  ///
  /// The id stays in `seen`, so the node does not pick the same envelope up
  /// again from a peer that has not yet delivered it.
  void delivered(String idHex) => _outbox.remove(idHex);

  /// Drops everything held. Used when a node stops relaying, and on sign-out:
  /// a phone should not keep carrying other people's emergencies for somebody
  /// who is no longer using the app.
  void clear() {
    _outbox.clear();
    _seen.clear();
  }

  void _remember(String id, DateTime now) {
    _seen[id] = now;
    while (_seen.length > seenCapacity) {
      _seen.remove(_seen.keys.first);
    }
  }
}
