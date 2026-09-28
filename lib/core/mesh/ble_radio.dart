/// The radio, reduced to four verbs.
///
/// Everything the mesh needs from BLE is: tell me who is in range, hand me the
/// bytes they wrote, tell me how much I may write at a time, and write these
/// bytes to that peer. Nothing above this line knows what a GATT characteristic
/// is, and nothing below it knows what an alert is.
///
/// The seam sits exactly here because this is the line between what can be
/// proven in CI and what needs two handsets in a room. Chunking, reassembly,
/// hostile-peer handling, per-peer queues, backpressure and the gossip schedule
/// are all above it and all tested. Discovery, pairing, MTU negotiation,
/// background behaviour and battery cost are all below it and none of them can
/// be tested here — or, honestly, predicted here.
///
/// ## What the native implementation has to do
///
/// Written down as a specification because the Dart side is finished and the
/// native side is not, and a vague "add BLE" is how the wrong thing gets built:
///
/// * **Advertise** a fixed 128-bit service UUID with one writable, notifiable
///   characteristic. The service UUID is the only thing a scanner matches on, so
///   it must be in the advertisement itself, not only in the GATT table —
///   iOS cannot scan in the background without naming it up front.
/// * **Scan** for that UUID and connect. Both roles at once: every phone is a
///   peripheral and a central, because a mesh has no servers.
/// * **Negotiate the MTU** and report what was agreed. Do not assume it
///   succeeded; `mtuFor` returning 23 must be a working configuration, not a
///   failure mode, because that is what happens on the third phone.
/// * **Carry no identity.** No device name, no manufacturer data, no user id in
///   the advertisement. A relay that can be recognised across sightings is a
///   relay that can be followed, and the whole point of the mesh's sealing is
///   that carrying an alert reveals nothing about who is nearby.
/// * **Report disconnects promptly**, because a partially received frame is held
///   in memory until the disconnect arrives or the reassembly timeout expires.
///
/// Platform notes that will decide how well this works, and which are the reason
/// none of it is claimed as verified:
///
/// * **Android** needs `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT` and
///   `BLUETOOTH_SCAN` (the last with `neverForLocation`, or it demands location
///   permission for a feature that has nothing to do with location).
/// * **iOS** restricts background advertising to an "overflow" area that other
///   iOS devices can see and Android generally cannot, and background scanning
///   requires the service UUID up front. An iOS relay works in the foreground
///   and degrades in the background in ways that need measuring on handsets.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// The smallest MTU any BLE stack will give us, and therefore the one the mesh
/// must work at.
const int bleMinimumMtu = 23;

/// A peer appearing or disappearing.
@immutable
class BlePeerEvent {
  /// Creates an event.
  const BlePeerEvent({required this.peerId, required this.connected});

  /// An opaque handle for this link. NOT a device identity: it may differ
  /// between sightings of the same handset, and nothing above here may treat it
  /// as stable.
  final String peerId;

  /// Whether the peer is now reachable.
  final bool connected;
}

/// Bytes written to us by a peer.
@immutable
class BleInbound {
  /// Creates an inbound write.
  const BleInbound({required this.peerId, required this.bytes});

  /// Which link they arrived on.
  final String peerId;

  /// One write's worth. Never assumed to be a whole anything.
  final Uint8List bytes;
}

/// A way to reach phones in radio range.
abstract class BleRadio {
  /// Peers arriving and leaving.
  Stream<BlePeerEvent> get peers;

  /// Writes from peers.
  Stream<BleInbound> get inbound;

  /// The negotiated MTU for a peer, or [bleMinimumMtu] if nothing better was
  /// agreed.
  int mtuFor(String peerId);

  /// Begin advertising and scanning.
  Future<void> start();

  /// Stop, and release the radio. Relaying costs somebody else's battery.
  Future<void> stop();

  /// Write one chunk. Throws if the link is gone.
  Future<void> write(String peerId, Uint8List chunk);
}

/// A radio that carries bytes between in-process nodes.
///
/// Not a mock: it enforces the MTU, it can drop writes, it can disconnect in the
/// middle of a frame, and it delivers out of order — the four things a real BLE
/// link does that break naive chunking. Anything that passes here is not
/// guaranteed to work on a handset, but anything that fails here certainly will
/// not.
class FakeBleRadio implements BleRadio {
  /// Creates a fake radio for one node.
  FakeBleRadio(
    this.name, {
    this.mtu = bleMinimumMtu,
  });

  /// A label, for readable failures.
  final String name;

  /// The MTU this node reports for every peer.
  final int mtu;

  final _peers = StreamController<BlePeerEvent>.broadcast();
  final _inbound = StreamController<BleInbound>.broadcast();
  final _links = <String, FakeBleRadio>{};

  /// Every chunk this node was asked to write, in order.
  final List<Uint8List> written = [];

  /// Set to fail the next [failWrites] writes, as a busy link does.
  int failWrites = 0;

  /// Set to silently drop the next [dropWrites] writes, as a lossy link does.
  int dropWrites = 0;

  /// Peers whose every write fails — a link that is up as far as the OS is
  /// concerned and carries nothing. Targeted rather than global, so a test can
  /// assert that the peer which still works received the alert, instead of
  /// asserting that one of them might have.
  final Set<String> deadLinks = {};

  bool _started = false;

  @override
  Stream<BlePeerEvent> get peers => _peers.stream;

  @override
  Stream<BleInbound> get inbound => _inbound.stream;

  @override
  int mtuFor(String peerId) => mtu;

  /// Brings two nodes into range of each other.
  void link(FakeBleRadio other) {
    _links[other.name] = other;
    other._links[name] = this;
    if (_started && other._started) {
      _peers.add(BlePeerEvent(peerId: other.name, connected: true));
      other._peers.add(BlePeerEvent(peerId: name, connected: true));
    }
  }

  /// Takes two nodes out of range — a phone in a pocket, a person walking off.
  void unlink(FakeBleRadio other) {
    _links.remove(other.name);
    other._links.remove(name);
    _peers.add(BlePeerEvent(peerId: other.name, connected: false));
    other._peers.add(BlePeerEvent(peerId: name, connected: false));
  }

  @override
  Future<void> start() async {
    _started = true;
    for (final peer in _links.values) {
      if (!peer._started) continue;
      // BOTH sides. The first version of this announced the new peer only to
      // the node that was starting, so in a test that linked two radios and then
      // started them in order, the first one never learned about the second and
      // nothing was ever sent. Every phone scans continuously, so discovery is
      // symmetric; a fake that is asymmetric tests a mesh that does not exist.
      _peers.add(BlePeerEvent(peerId: peer.name, connected: true));
      peer._peers.add(BlePeerEvent(peerId: name, connected: true));
    }
  }

  @override
  Future<void> stop() async => _started = false;

  @override
  Future<void> write(String peerId, Uint8List chunk) async {
    if (!_started) throw StateError('$name: radio is not started');
    final peer = _links[peerId];
    if (peer == null) throw StateError('$name: no link to $peerId');
    if (chunk.length > mtu - 3) {
      // A real stack either rejects this or — worse, on some of them — truncates
      // it silently, which produces a corrupt frame instead of an error. Better
      // to be strict here than to discover that on a handset.
      throw ArgumentError('$name: ${chunk.length} bytes exceeds the MTU');
    }
    written.add(Uint8List.fromList(chunk));
    if (deadLinks.contains(peerId)) {
      throw StateError('$name: link to $peerId carries nothing');
    }
    if (failWrites > 0) {
      failWrites--;
      throw StateError('$name: write failed');
    }
    if (dropWrites > 0) {
      dropWrites--;
      return;
    }
    peer._inbound.add(BleInbound(peerId: name, bytes: chunk));
  }

  /// Releases the streams.
  Future<void> dispose() async {
    await _peers.close();
    await _inbound.close();
  }
}
