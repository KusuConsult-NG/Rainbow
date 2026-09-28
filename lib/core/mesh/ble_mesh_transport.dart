/// The mesh over BLE: everything above the radio, and none of the radio.
///
/// This is the `MeshTransport` the app will use, written against [BleRadio] so
/// the whole of its behaviour can be tested without a radio. What it adds over
/// the interface is the four things a BLE link makes necessary:
///
/// **Chunking.** A frame is ~166 bytes and a default write carries 20, so every
/// frame is split and reassembled. `mesh_chunking.dart` owns that.
///
/// **One write at a time, per peer.** BLE stacks do not take parallel writes on
/// one link; a second write before the first completes is dropped or errors,
/// depending on the platform. So each peer has a queue and a pump.
///
/// **A bounded queue.** A peer that stops draining must not make this phone grow
/// a buffer. When the queue is full the OLDEST frame is dropped, the same choice
/// the relay outbox and the reassembler make: a flood wins a delay, not the
/// ability to block the alert behind it.
///
/// **Isolation between peers.** One peer's failure — a dead link, a hostile
/// chunk, a mid-frame disconnect — must not affect the others. The phone in
/// range that still works is the one carrying the alert out.
///
/// ## What is NOT here, deliberately
///
/// No retries and no acknowledgements. A frame that fails to reach a peer is
/// simply not sent; the relay still holds it and will offer it to the next peer
/// it meets, and to this one again if they meet again. Acknowledgement would mean
/// state per frame per peer, on a link that drops constantly, to solve a problem
/// the flood already solves.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/mesh_chunking.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_transport.dart';

/// How many frames may be queued for one peer before the oldest is dropped.
const int bleMaxQueuedFramesPerPeer = 4;

/// A mesh transport over Bluetooth Low Energy.
class BleMeshTransport implements MeshTransport {
  /// Creates a transport over [radio].
  BleMeshTransport(this.radio, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// The radio. Everything platform-specific lives behind it.
  final BleRadio radio;

  final DateTime Function() _clock;
  final _out = StreamController<MeshEnvelope>.broadcast();
  final _links = <String, _Link>{};
  StreamSubscription<BlePeerEvent>? _peerSub;
  StreamSubscription<BleInbound>? _inboundSub;
  bool _started = false;

  /// Envelopes reassembled from peers.
  @override
  Stream<MeshEnvelope> get inbound => _out.stream;

  /// Which peers are currently reachable.
  List<String> get peers => List.unmodifiable(_links.keys);

  /// Chunks that could not be written, for the log and for the tests.
  int failedWrites = 0;

  /// Frames dropped because a peer's queue was full.
  int droppedFrames = 0;

  /// Chunks refused because a peer sent something we will not assemble.
  int rejectedChunks = 0;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    // Subscribe BEFORE starting the radio, or a peer that is already in range
    // announces itself into nothing and is never seen until it leaves and
    // returns.
    _peerSub = radio.peers.listen(_onPeer);
    _inboundSub = radio.inbound.listen(_onBytes);
    await radio.start();
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _peerSub?.cancel();
    await _inboundSub?.cancel();
    _peerSub = null;
    _inboundSub = null;
    _links.clear();
    await radio.stop();
  }

  @override
  Future<void> offer(MeshEnvelope envelope) async {
    if (!_started) return;
    final frame = envelope.encode();
    for (final link in _links.values) {
      link.enqueue(frame);
      if (link.queue.length > bleMaxQueuedFramesPerPeer) {
        link.queue.removeFirst();
        droppedFrames++;
      }
      _pump(link);
    }
  }

  void _onPeer(BlePeerEvent event) {
    if (event.connected) {
      _links.putIfAbsent(
        event.peerId,
        () => _Link(
          peerId: event.peerId,
          reassembler: MeshReassembler(clock: _clock),
        ),
      );
      return;
    }
    // A disconnect abandons what was in flight in BOTH directions. Half a frame
    // kept across a reconnection could be completed by chunks from after it,
    // splicing two frames into one that decodes as neither.
    _links.remove(event.peerId)?.reassembler.clear();
  }

  void _onBytes(BleInbound event) {
    final link = _links[event.peerId];
    if (link == null) {
      // Bytes from a peer we have no record of. Happens legitimately when a
      // write races the disconnect that follows it.
      return;
    }
    final result = link.reassembler.offer(event.bytes);
    if (result.isRejected) {
      rejectedChunks++;
      return;
    }
    final envelope = result.envelope;
    if (envelope != null) _out.add(envelope);
  }

  /// Drains one peer's queue, one write at a time.
  ///
  /// Not awaited by the caller: a peer whose link has gone quiet would otherwise
  /// hold up every other peer, including the one that can actually carry the
  /// alert out.
  void _pump(_Link link) {
    if (link.pumping) return;
    link.pumping = true;
    unawaited(_drain(link));
  }

  Future<void> _drain(_Link link) async {
    try {
      while (_started && link.queue.isNotEmpty && _links.containsKey(link.peerId)) {
        final frame = link.queue.removeFirst();
        final payload = meshPayloadForMtu(radio.mtuFor(link.peerId));
        if (payload < meshMinChunkPayload) {
          // An MTU this small cannot carry anything. Nothing to do but skip the
          // peer; the relay still holds the envelope.
          continue;
        }
        final chunks = meshChunk(
          frame: frame,
          payloadSize: payload,
          messageId: link.nextMessageId(),
        );
        for (final chunk in chunks) {
          try {
            await radio.write(link.peerId, chunk);
          } on Object catch (_) {
            // `on Object`, not `on Exception`. The first version caught
            // Exception, and a platform channel is at least as likely to give
            // back a StateError — which is an Error, not an Exception — so every
            // failed write escaped this pump, left `pumping` true in the
            // `finally`'s absence and killed relaying for that peer for good.
            // Found by the test below that fails one write.
            //
            // Abandon THIS frame, not the queue and not the peer: a single
            // failed write usually means a momentarily busy link, and the next
            // frame may well go. The relay still holds this one, and will offer
            // it again at the next meeting.
            failedWrites++;
            break;
          }
        }
      }
    } finally {
      link.pumping = false;
    }
  }

  /// Releases the outbound stream.
  Future<void> dispose() async {
    await stop();
    await _out.close();
  }
}

class _Link {
  _Link({required this.peerId, required this.reassembler});

  final String peerId;
  final MeshReassembler reassembler;
  final Queue<Uint8List> queue = Queue<Uint8List>();
  bool pumping = false;
  int _messageId = 0;

  void enqueue(Uint8List frame) => queue.add(frame);

  /// A counter rather than a random value: two interleaved messages must not be
  /// able to collide by chance, and this needs to be unpredictable to nobody.
  int nextMessageId() => _messageId = (_messageId + 1) & 0xFF;
}
