/// One phone's participation in the mesh.
///
/// Every piece of the mesh has been built and tested separately — the envelope,
/// the sealing, the relay's decisions, the chunking, the transport — and none of
/// them decides *when* anything happens. That is this file, and it is small on
/// purpose: it holds the schedule and nothing else.
///
/// ```
///   MeshNode
///     ├── MeshRelay      what to carry, what to drop        (decisions)
///     └── MeshTransport  who is in range, bytes in and out  (radio)
/// ```
///
/// Three rules, and each one is a decision that was made explicitly rather than
/// falling out of the code:
///
/// **On meeting a peer, offer everything held.** Not "offer new things" — a phone
/// that has been out of range for an hour has never seen any of it. This is the
/// whole mechanism by which an alert crosses a crowd.
///
/// **On receiving, decide and then pass on.** The relay's rules — deduplication,
/// hop limit, age, size — apply before anything is stored, so a node that has
/// seen an envelope does not take it again and the flood dies out.
///
/// **On sign-out, stop and forget.** A phone should not keep carrying strangers'
/// emergencies for somebody who is no longer using the app, and the radio costs
/// battery that is not ours to spend.
///
/// ## What it deliberately does not do
///
/// It does not decide whether this phone should relay at all. That is a policy
/// question with a legal edge — carrying somebody else's emergency traffic is not
/// neutral everywhere — so it is decided in one place, `MeshService`
/// (responders by default, citizens by opt-in). The node relays when it is
/// started and does not start itself.
library;

import 'dart:async';

import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';
import 'package:rainbow_app/core/mesh/mesh_transport.dart';

/// Wires a relay to a transport.
class MeshNode {
  /// Creates a node.
  MeshNode({
    required this.relay,
    required this.transport,
    this.onEnvelope,
  });

  /// What to carry, and what to drop.
  final MeshRelay relay;

  /// How to reach nearby phones.
  final MeshTransport transport;

  /// Called for every envelope this node accepted.
  ///
  /// The hook by which a phone WITH a network uploads to HQ: the app passes a
  /// callback that POSTs to `/api/mesh/ingest` and, on success, calls
  /// [delivered]. Deliberately a callback rather than a dependency — this file
  /// must not know that HQ exists, so it can be tested without a server and so
  /// that "reaching HQ" stays one replaceable thing.
  final void Function(MeshEnvelope envelope)? onEnvelope;

  StreamSubscription<MeshEnvelope>? _sub;
  bool _started = false;

  /// How many envelopes this node accepted from peers.
  int accepted = 0;

  /// How many it declined, for any reason.
  int declined = 0;

  /// Whether this node is participating.
  bool get isRelaying => _started;

  /// Starts relaying.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = transport.inbound.listen(_onEnvelope);
    await transport.start();
  }

  /// Stops relaying and drops everything held.
  ///
  /// Called on sign-out, and by whatever the relaying policy turns out to be.
  Future<void> stop() async {
    _started = false;
    await _sub?.cancel();
    _sub = null;
    await transport.stop();
    relay.clear();
  }

  /// Offers everything held to a peer that has just come into range.
  ///
  /// Called by whatever watches for peers. It is not wired to a peer stream here
  /// because `MeshTransport` deliberately does not expose one — a transport
  /// reports bytes, not sociology — so the app calls this when its radio says a
  /// peer appeared, and a test calls it directly.
  Future<void> gossip() async {
    if (!_started) return;
    // `toOffer` has already spent a hop on each, so a caller cannot forget to.
    for (final envelope in relay.toOffer()) {
      await transport.offer(envelope);
    }
  }

  /// Puts this phone's own freshly sealed alert into the mesh.
  ///
  /// It goes through the relay rather than straight to the radio, so that our own
  /// alert is carried onward at the next meeting exactly like anybody else's —
  /// and so a phone that seals an alert with nobody in range still holds it.
  Future<void> send(MeshEnvelope envelope) async {
    relay.offer(envelope);
    await gossip();
  }

  /// Marks an envelope as having reached a network, so this node stops carrying
  /// it. The id stays in the relay's `seen` set, so a peer that has not yet
  /// delivered it cannot hand it back.
  void delivered(String idHex) => relay.delivered(idHex);

  void _onEnvelope(MeshEnvelope envelope) {
    final decision = relay.offer(envelope);
    if (!decision.stored) {
      declined++;
      return;
    }
    accepted++;
    onEnvelope?.call(envelope);
  }
}
