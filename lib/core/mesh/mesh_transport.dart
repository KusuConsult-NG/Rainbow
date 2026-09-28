/// The radio, abstracted away so the protocol can be proven without one.
///
/// Everything above this line — sealing, deduplication, hop limits, expiry,
/// the bounded outbox — is testable in a unit test. Everything below it needs
/// two handsets in a room. Keeping the seam here is what lets the whole of the
/// mesh's BEHAVIOUR be verified in CI, leaving only "does the radio find the
/// other phone" for a field test.
///
/// Three implementations are planned:
///
/// | implementation | platform      | notes                                  |
/// |----------------|---------------|----------------------------------------|
/// | BLE            | Android + iOS | the baseline, chosen for cross-platform |
/// | Nearby         | Android only  | optional accelerator, better range     |
/// | Loopback       | tests         | in-process peers                       |
library;

import 'dart:async';

import 'package:rainbow_app/core/mesh/mesh_envelope.dart';

/// A way to reach nearby phones.
abstract class MeshTransport {
  /// Envelopes arriving from peers.
  Stream<MeshEnvelope> get inbound;

  /// Begin advertising and scanning.
  Future<void> start();

  /// Stop, and release the radio.
  Future<void> stop();

  /// Offer an envelope to whoever is in range.
  Future<void> offer(MeshEnvelope envelope);
}

/// In-process peers, for tests.
///
/// Not a mock: it carries real encoded frames through `MeshEnvelope.decode`,
/// so a change that breaks the wire format breaks these tests too.
class LoopbackMeshTransport implements MeshTransport {
  /// Creates one node of a loopback mesh.
  LoopbackMeshTransport(this.name);

  /// A label, for readable test failures.
  final String name;

  final _controller = StreamController<MeshEnvelope>.broadcast();
  final _peers = <LoopbackMeshTransport>[];
  bool _started = false;

  /// Everything this node was asked to send, in order.
  final List<MeshEnvelope> sent = [];

  @override
  Stream<MeshEnvelope> get inbound => _controller.stream;

  /// Puts two nodes in range of each other.
  void link(LoopbackMeshTransport other) {
    if (!_peers.contains(other)) _peers.add(other);
    if (!other._peers.contains(this)) other._peers.add(this);
  }

  /// Takes two nodes out of range.
  void unlink(LoopbackMeshTransport other) {
    _peers.remove(other);
    other._peers.remove(this);
  }

  @override
  Future<void> start() async => _started = true;

  @override
  Future<void> stop() async => _started = false;

  @override
  Future<void> offer(MeshEnvelope envelope) async {
    sent.add(envelope);
    if (!_started) return;
    // Through the real encoder and decoder, so a wire-format regression shows
    // up here rather than only on a handset.
    final frame = envelope.encode();
    for (final peer in _peers) {
      if (!peer._started) continue;
      final decoded = MeshEnvelope.decode(frame);
      if (decoded != null) peer._controller.add(decoded);
    }
  }

  /// Releases the stream.
  Future<void> dispose() => _controller.close();
}
