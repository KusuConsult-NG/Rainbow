/// Getting a 166-byte frame through a 20-byte pipe.
///
/// ## Why this file exists at all
///
/// A sealed alert frame is about 166 bytes. BLE's default ATT MTU is **23**,
/// of which 3 are protocol overhead, so a write carries **20 bytes** until an
/// MTU negotiation succeeds — and negotiation is exactly the kind of thing that
/// works on the two phones you tested and not on the third. So a frame has to
/// be split, carried in pieces, and put back together by the other side.
///
/// That makes this the most dangerous file in the mesh, because it is the one
/// place where bytes from a stranger's phone are assembled into a buffer whose
/// size that stranger chooses. Every rule below exists to bound that:
///
/// | rule                                    | what it stops                   |
/// |-----------------------------------------|---------------------------------|
/// | `total` is declared once and must agree | a peer growing a message forever |
/// | assembled size capped at 512            | the mesh used as a file transfer |
/// | at most 4 messages in flight per peer   | many half-messages held at once  |
/// | each incomplete message expires         | a peer parking memory and leaving |
/// | only the last chunk may be short        | a peer padding to confuse offsets |
/// | duplicate `seq` is ignored, not fatal   | a retry dropping a real message  |
///
/// ## Wire format
///
/// ```
///   0   1  version
///   1   1  message id, per-peer, wraps at 256
///   2   1  sequence number, 0-based
///   3   1  total chunks in this message
///   4   n  payload
/// ```
///
/// Four bytes of header per chunk is 20% overhead at a 20-byte MTU, and that is
/// the right trade: the alternative is a stateful stream per peer, which means
/// a connection drop mid-frame corrupts the next frame rather than losing this
/// one. A BLE link between two phones in a crowd drops constantly.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';

/// Version of the chunk header.
const int meshChunkVersion = 1;

/// Bytes of header on every chunk.
const int meshChunkHeaderLength = 4;

/// The smallest payload we will attempt to work with.
///
/// Below this the header dominates and a frame would need more than 255 chunks,
/// which the one-byte `total` cannot express.
const int meshMinChunkPayload = 4;

/// How many partially-received messages one peer may have open.
const int meshMaxOpenMessages = 4;

/// How long an incomplete message is held before it is abandoned.
const Duration meshReassemblyTimeout = Duration(seconds: 20);

/// Splits [frame] into chunks that each fit in [payloadSize] bytes of payload.
///
/// [messageId] distinguishes concurrent messages from the same peer and wraps
/// at 256; a caller passes a counter, not a random value, so two interleaved
/// messages cannot collide by chance.
List<Uint8List> meshChunk({
  required Uint8List frame,
  required int payloadSize,
  required int messageId,
}) {
  if (payloadSize < meshMinChunkPayload) {
    throw ArgumentError.value(
        payloadSize, 'payloadSize', 'at least $meshMinChunkPayload');
  }
  if (frame.isEmpty || frame.length > meshMaxEnvelopeBytes) {
    throw ArgumentError.value(frame.length, 'frame', 'not a size we carry');
  }
  final total = (frame.length + payloadSize - 1) ~/ payloadSize;
  if (total > 255) {
    // Unreachable with a 512-byte cap and a 4-byte floor, and asserted anyway:
    // a `total` that does not fit the field would silently truncate.
    throw StateError('$total chunks does not fit in one byte');
  }

  final out = <Uint8List>[];
  for (var i = 0; i < total; i++) {
    final start = i * payloadSize;
    final end = (start + payloadSize).clamp(0, frame.length);
    final chunk = Uint8List(meshChunkHeaderLength + (end - start))
      ..[0] = meshChunkVersion
      ..[1] = messageId & 0xFF
      ..[2] = i
      ..[3] = total
      ..setRange(meshChunkHeaderLength, meshChunkHeaderLength + (end - start),
          frame.sublist(start, end));
    out.add(chunk);
  }
  return out;
}

/// How much payload fits in a write, given a negotiated ATT MTU.
///
/// Three bytes of the MTU belong to ATT itself. A caller that forgets this
/// writes one byte too many and the write fails — or worse, on some stacks, is
/// silently truncated, which produces a corrupt frame rather than an error.
int meshPayloadForMtu(int mtu) => mtu - 3 - meshChunkHeaderLength;

/// Why a chunk was refused.
enum MeshChunkRejection {
  /// Not a chunk: too short, or a version we do not speak.
  malformed,

  /// Sequence beyond the declared total, or a total of zero.
  outOfRange,

  /// A chunk of a message whose declared total differs from the first one seen.
  inconsistent,

  /// Would assemble into something larger than any relay carries.
  tooLarge,

  /// A chunk we already hold. Not an error; a peer retrying.
  duplicate,
}

/// The outcome of offering one chunk to a reassembler.
@immutable
class MeshChunkResult {
  /// A chunk taken, with the message still incomplete.
  const MeshChunkResult.accepted()
      : envelope = null,
        rejection = null;

  /// The last chunk of a message, which decoded into an envelope.
  const MeshChunkResult.complete(this.envelope) : rejection = null;

  /// A chunk we will not take.
  const MeshChunkResult.rejected(this.rejection) : envelope = null;

  /// The assembled envelope, when this chunk completed one.
  final MeshEnvelope? envelope;

  /// Why it was refused, when it was.
  final MeshChunkRejection? rejection;

  /// Whether a complete envelope came out.
  bool get isComplete => envelope != null;

  /// Whether the chunk was refused.
  bool get isRejected => rejection != null;
}

/// Reassembles chunks from ONE peer.
///
/// One instance per peer, deliberately: message ids are per-peer, so sharing a
/// reassembler across peers would let one peer's chunk complete another's
/// message — which is a way to inject bytes into somebody else's frame.
class MeshReassembler {
  /// Creates a reassembler for one peer.
  MeshReassembler({
    this.maxOpenMessages = meshMaxOpenMessages,
    this.timeout = meshReassemblyTimeout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How many partial messages may be open at once.
  final int maxOpenMessages;

  /// How long a partial message is held.
  final Duration timeout;

  final DateTime Function() _clock;
  final Map<int, _Partial> _open = {};

  /// How many messages are partially received.
  int get openCount => _open.length;

  /// Total bytes currently held for this peer.
  int get bufferedBytes =>
      _open.values.fold(0, (sum, p) => sum + p.received);

  /// Offers one chunk.
  MeshChunkResult offer(Uint8List chunk) {
    _expire();

    if (chunk.length <= meshChunkHeaderLength) {
      return const MeshChunkResult.rejected(MeshChunkRejection.malformed);
    }
    if (chunk[0] != meshChunkVersion) {
      return const MeshChunkResult.rejected(MeshChunkRejection.malformed);
    }
    final id = chunk[1];
    final seq = chunk[2];
    final total = chunk[3];
    final payload = Uint8List.sublistView(chunk, meshChunkHeaderLength);

    if (total == 0 || seq >= total) {
      return const MeshChunkResult.rejected(MeshChunkRejection.outOfRange);
    }
    // An upper bound before a single byte is stored: the largest this message
    // could possibly become is total × this chunk's payload.
    if (total * payload.length > meshMaxEnvelopeBytes + payload.length) {
      return const MeshChunkResult.rejected(MeshChunkRejection.tooLarge);
    }

    var partial = _open[id];
    if (partial == null) {
      if (_open.length >= maxOpenMessages) {
        // Drop the oldest rather than refuse the newest, for the same reason
        // the relay outbox does: a peer that opens messages and abandons them
        // wins a delay, not the ability to block the next real frame.
        final oldest = _open.entries
            .reduce((a, b) => a.value.startedAt.isBefore(b.value.startedAt) ? a : b);
        _open.remove(oldest.key);
      }
      partial = _Partial(total: total, startedAt: _clock());
      _open[id] = partial;
    } else if (partial.total != total) {
      // A peer changing its mind about how long the message is. Abandon it
      // rather than trying to reconcile: reconciling is how a buffer grows.
      _open.remove(id);
      return const MeshChunkResult.rejected(MeshChunkRejection.inconsistent);
    }

    if (partial.chunks.containsKey(seq)) {
      return const MeshChunkResult.rejected(MeshChunkRejection.duplicate);
    }
    // Only the LAST chunk may be short. A short chunk anywhere else would shift
    // every byte after it, so the frame would decode as garbage — or, worse,
    // decode as a different valid frame.
    final first = partial.chunks.values.isEmpty ? null : partial.payloadSize;
    if (first != null) {
      final isLast = seq == total - 1;
      if (payload.length > first || (!isLast && payload.length < first)) {
        _open.remove(id);
        return const MeshChunkResult.rejected(MeshChunkRejection.inconsistent);
      }
    }

    partial.chunks[seq] = Uint8List.fromList(payload);
    partial.received += payload.length;
    if (partial.payloadSize == 0 || seq < total - 1) {
      partial.payloadSize = payload.length;
    }
    if (partial.received > meshMaxEnvelopeBytes) {
      _open.remove(id);
      return const MeshChunkResult.rejected(MeshChunkRejection.tooLarge);
    }

    if (partial.chunks.length < total) {
      return const MeshChunkResult.accepted();
    }

    _open.remove(id);
    final assembled = BytesBuilder(copy: false);
    for (var i = 0; i < total; i++) {
      assembled.add(partial.chunks[i]!);
    }
    final envelope = MeshEnvelope.decode(assembled.toBytes());
    if (envelope == null) {
      // Assembled cleanly and is not a frame. Nothing to do but drop it: the
      // peer is running a different version, or is not the app at all.
      return const MeshChunkResult.rejected(MeshChunkRejection.malformed);
    }
    return MeshChunkResult.complete(envelope);
  }

  /// Abandons everything held. Called on disconnect, so a peer that reconnects
  /// does not complete a message with chunks from before the drop.
  void clear() => _open.clear();

  void _expire() {
    final now = _clock();
    _open.removeWhere((_, p) => now.difference(p.startedAt) > timeout);
  }
}

class _Partial {
  _Partial({required this.total, required this.startedAt});

  final int total;
  final DateTime startedAt;
  final Map<int, Uint8List> chunks = {};
  int received = 0;

  /// The payload size seen on a non-final chunk, which every other non-final
  /// chunk must match.
  int payloadSize = 0;
}
