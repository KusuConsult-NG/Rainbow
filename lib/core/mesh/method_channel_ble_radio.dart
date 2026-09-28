/// The [BleRadio] that talks to the platform — and the contract the native
/// halves must implement.
///
/// ## Read this before writing the Kotlin or the Swift
///
/// This file is finished. The Android and iOS implementations are **not
/// written**, and nothing about BLE in this project has been run on a handset.
/// The contract lives here rather than in a document so that the remaining work
/// is "implement these five messages" instead of "add Bluetooth".
///
/// **Method channel** `com.operationrainbow.app/mesh_ble`, Dart → native:
///
/// | method  | arguments                          | returns          |
/// |---------|------------------------------------|------------------|
/// | `start` | `{serviceUuid: String}`            | null             |
/// | `stop`  | —                                  | null             |
/// | `write` | `{peerId: String, bytes: Uint8List}` | null; throw to fail |
///
/// **Event channel** `com.operationrainbow.app/mesh_ble/events`, native → Dart,
/// each event a map with an `event` key:
///
/// | event  | fields                                   | when                  |
/// |--------|------------------------------------------|-----------------------|
/// | `peer` | `peerId: String, connected: bool, mtu: int?` | connect / disconnect |
/// | `mtu`  | `peerId: String, mtu: int`               | negotiation completes |
/// | `data` | `peerId: String, bytes: Uint8List`       | a peer wrote to us    |
///
/// Four requirements on the native side that are easy to miss and expensive to
/// discover in the field:
///
/// 1. **`peerId` need not be stable across sightings, and must not be an identity.**
///    Do not derive it from a MAC address, an advertised name, or anything that
///    survives a reconnection in a way an observer could correlate. Nothing above
///    this file treats it as stable.
/// 2. **Report the MTU you actually negotiated**, and report 23 if negotiation
///    failed. 23 is a working configuration here — the chunker handles it — and a
///    native side that optimistically reports 517 will have its writes rejected
///    or, on some stacks, silently truncated into corrupt frames.
/// 3. **Advertise no identity.** No device name, no manufacturer data. A relay
///    that can be recognised across sightings can be followed, which is the
///    attack the sealing exists to prevent; it would be undone by the
///    advertisement.
/// 4. **Report disconnects promptly.** A half-received frame is held until the
///    disconnect arrives or the reassembly timeout expires.
///
/// ## Why this Dart half is worth having before the native half exists
///
/// Because decoding platform messages is where the bugs are. A platform channel
/// hands over `Map<Object?, Object?>` with nothing checked, and this project has
/// `avoid_dynamic_calls` promoted to an error precisely because that shape
/// invites a crash on the first surprising message. Every field here is read
/// defensively and a malformed event is dropped rather than thrown, and that
/// behaviour IS testable in CI — `method_channel_ble_radio_test.dart` drives it
/// with a mock platform, including messages no correct native side would send.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';

/// The service UUID both platforms advertise and scan for.
///
/// A fixed 128-bit UUID. It is the only thing a scanner matches on, and it is
/// not a secret: anybody can see that a phone is running this app. That is
/// accepted — it is the same information as having the app installed — and it is
/// why no other identifying data goes in the advertisement.
///
/// The first version of this constant had six hex digits in the first group
/// instead of eight. Both platforms parse this string at runtime and would have
/// thrown on a handset and nowhere else, so it has a test.
const String meshServiceUuid = '6f726e62-6f77-4d65-7368-000000000001';

/// The channel the native side implements.
const String meshBleMethodChannel = 'com.operationrainbow.app/mesh_ble';

/// The channel the native side pushes events on.
const String meshBleEventChannel = 'com.operationrainbow.app/mesh_ble/events';

/// A radio backed by the platform's Bluetooth stack.
class MethodChannelBleRadio implements BleRadio {
  /// Creates a radio over the platform channels.
  ///
  /// The channels are injectable so tests can drive a mock platform rather than
  /// a real one.
  MethodChannelBleRadio({
    MethodChannel? methods,
    EventChannel? events,
    this.serviceUuid = meshServiceUuid,
  })  : _methods = methods ?? const MethodChannel(meshBleMethodChannel),
        _events = events ?? const EventChannel(meshBleEventChannel);

  /// What to advertise and scan for.
  final String serviceUuid;

  final MethodChannel _methods;
  final EventChannel _events;

  final _peers = StreamController<BlePeerEvent>.broadcast();
  final _inbound = StreamController<BleInbound>.broadcast();
  final _mtus = <String, int>{};
  StreamSubscription<dynamic>? _sub;

  /// Events the platform sent that we could not make sense of.
  ///
  /// Counted rather than thrown. A native side on a different version, or a
  /// stack sending something undocumented, must not be able to crash the relay —
  /// but silently ignoring it would make the eventual debugging session
  /// impossible.
  int malformedEvents = 0;

  @override
  Stream<BlePeerEvent> get peers => _peers.stream;

  @override
  Stream<BleInbound> get inbound => _inbound.stream;

  @override
  int mtuFor(String peerId) => _mtus[peerId] ?? bleMinimumMtu;

  @override
  Future<void> start() async {
    _sub ??= _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object error) => malformedEvents++,
        );
    await _methods.invokeMethod<void>('start', {'serviceUuid': serviceUuid});
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _mtus.clear();
    await _methods.invokeMethod<void>('stop');
  }

  @override
  Future<void> write(String peerId, Uint8List chunk) =>
      _methods.invokeMethod<void>('write', {
        'peerId': peerId,
        'bytes': chunk,
      });

  void _onEvent(Object? raw) {
    // Read field by field with explicit types. A platform channel hands over
    // Map<Object?, Object?> with nothing checked, and a dynamic call on it is
    // one surprising message away from taking the relay down.
    if (raw is! Map) {
      malformedEvents++;
      return;
    }
    final map = raw.cast<Object?, Object?>();
    final kind = map['event'];
    final peerId = map['peerId'];
    if (kind is! String || peerId is! String || peerId.isEmpty) {
      malformedEvents++;
      return;
    }

    switch (kind) {
      case 'peer':
        final connected = map['connected'];
        if (connected is! bool) {
          malformedEvents++;
          return;
        }
        if (connected) {
          _mtus[peerId] = _readMtu(map['mtu']);
        } else {
          _mtus.remove(peerId);
        }
        _peers.add(BlePeerEvent(peerId: peerId, connected: connected));
      case 'mtu':
        // A renegotiation. Only accept it for a peer we know about, or a stray
        // event would grow this map without bound.
        if (!_mtus.containsKey(peerId)) {
          malformedEvents++;
          return;
        }
        _mtus[peerId] = _readMtu(map['mtu']);
      case 'data':
        final bytes = map['bytes'];
        if (bytes is! Uint8List || bytes.isEmpty) {
          malformedEvents++;
          return;
        }
        _inbound.add(BleInbound(peerId: peerId, bytes: bytes));
      default:
        malformedEvents++;
    }
  }

  /// Clamps whatever the platform claims into something writable.
  ///
  /// A native side that optimistically reports a large MTU it did not negotiate
  /// gets its writes rejected — or, on some stacks, silently truncated, which
  /// produces a corrupt frame rather than an error. Clamping low is always safe:
  /// it costs more writes and nothing else.
  int _readMtu(Object? value) {
    if (value is! int || value < bleMinimumMtu) return bleMinimumMtu;
    // 517 is the largest ATT MTU any stack negotiates.
    return value > 517 ? 517 : value;
  }

  /// Releases the streams.
  Future<void> dispose() async {
    await _sub?.cancel();
    await _peers.close();
    await _inbound.close();
  }
}
