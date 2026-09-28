// The platform boundary, driven by a mock platform.
//
// The native halves are not written, so nothing here proves BLE works. What it
// does prove is the half that CAN be proven: that this side reads the platform's
// messages defensively. A platform channel hands over Map<Object?, Object?> with
// nothing checked, which is one surprising message away from taking the relay
// down — and the relay is what is carrying somebody's duress alert.
//
// So most of these tests send things a correct native side would never send.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/method_channel_ble_radio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('test/mesh_ble');
  const events = EventChannel('test/mesh_ble/events');
  late List<MethodCall> calls;
  late MockStreamHandler handler;
  late MethodChannelBleRadio radio;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    calls = [];
    sink = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'write' && _peerOf(call) == 'broken') {
        // A real stack fails a write to a link that has gone.
        throw PlatformException(code: 'write_failed');
      }
      return null;
    });
    handler = MockStreamHandler.inline(
      onListen: (arguments, eventSink) => sink = eventSink,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(events, handler);
    radio = MethodChannelBleRadio(methods: methods, events: events);
  });

  tearDown(() async {
    await radio.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(events, null);
  });

  Future<void> emit(Object? event) async {
    sink?.success(event);
    await Future<void>.delayed(Duration.zero);
  }

  group('asking the platform to do things', () {
    test('start names the service UUID, because iOS cannot scan without it',
        () async {
      await radio.start();
      expect(calls.single.method, 'start');
      final args = (calls.single.arguments as Map).cast<Object?, Object?>();
      expect(args['serviceUuid'], meshServiceUuid);
    });

    test('the service UUID is one both platforms can parse', () {
      // Android's ParcelUuid.fromString and iOS's CBUUID both throw on a
      // malformed UUID, at runtime, on a handset and nowhere else. The first
      // version of this constant had six hex digits in its first group instead
      // of eight, and nothing in the Dart tests would ever have noticed.
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
            .hasMatch(meshServiceUuid),
        isTrue,
        reason: '$meshServiceUuid is not a UUID',
      );
    });

    test('stop releases the radio', () async {
      await radio.start();
      await radio.stop();
      expect(calls.map((c) => c.method), ['start', 'stop']);
    });

    test('a write carries the bytes and the peer', () async {
      await radio.start();
      await radio.write('peer-1', Uint8List.fromList([1, 2, 3]));
      final args = (calls.last.arguments as Map).cast<Object?, Object?>();
      expect(args['peerId'], 'peer-1');
      expect(args['bytes'], Uint8List.fromList([1, 2, 3]));
    });

    test('a platform failure surfaces rather than being swallowed', () async {
      // The transport counts it and abandons that frame; it must not be hidden
      // here, or a peer that carries nothing would look like one that works.
      await radio.start();
      await expectLater(
        radio.write('broken', Uint8List.fromList([1])),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('reading what the platform says', () {
    test('a peer arriving and leaving', () async {
      final seen = <String>[];
      radio.peers.listen((e) => seen.add('${e.peerId}:${e.connected}'));
      await radio.start();
      await emit({'event': 'peer', 'peerId': 'p1', 'connected': true, 'mtu': 185});
      await emit({'event': 'peer', 'peerId': 'p1', 'connected': false});
      expect(seen, ['p1:true', 'p1:false']);
    });

    test('the negotiated MTU is remembered, and forgotten on disconnect',
        () async {
      await radio.start();
      await emit({'event': 'peer', 'peerId': 'p1', 'connected': true, 'mtu': 185});
      expect(radio.mtuFor('p1'), 185);
      await emit({'event': 'peer', 'peerId': 'p1', 'connected': false});
      expect(radio.mtuFor('p1'), bleMinimumMtu,
          reason: 'a stale MTU for a peer that left would size the next frame '
              'for a link that no longer exists');
    });

    test('a renegotiation is taken', () async {
      await radio.start();
      await emit({'event': 'peer', 'peerId': 'p1', 'connected': true, 'mtu': 23});
      await emit({'event': 'mtu', 'peerId': 'p1', 'mtu': 512});
      expect(radio.mtuFor('p1'), 512);
    });

    test('bytes from a peer arrive as bytes', () async {
      final got = <BleInbound>[];
      radio.inbound.listen(got.add);
      await radio.start();
      await emit({
        'event': 'data',
        'peerId': 'p1',
        'bytes': Uint8List.fromList([9, 8, 7]),
      });
      expect(got.single.peerId, 'p1');
      expect(got.single.bytes, Uint8List.fromList([9, 8, 7]));
    });

    test('an unknown peer defaults to the worst MTU there is', () async {
      // 23 must be a working configuration, not a failure mode: it is what
      // happens on the third handset.
      expect(radio.mtuFor('never-seen'), bleMinimumMtu);
    });
  });

  group('refusing what no correct native side would send', () {
    test('nothing here throws, and nothing is emitted', () async {
      final peers = <BlePeerEvent>[];
      final data = <BleInbound>[];
      radio.peers.listen(peers.add);
      radio.inbound.listen(data.add);
      await radio.start();

      for (final bad in <Object?>[
        null,
        'a string',
        42,
        <Object?>[1, 2, 3],
        {'peerId': 'p1'}, // no event kind
        {'event': 'peer'}, // no peer
        {'event': 'peer', 'peerId': ''}, // empty peer
        {'event': 'peer', 'peerId': 'p1'}, // no connected flag
        {'event': 'peer', 'peerId': 'p1', 'connected': 'yes'}, // wrong type
        {'event': 'data', 'peerId': 'p1'}, // no bytes
        {'event': 'data', 'peerId': 'p1', 'bytes': 'not bytes'},
        {'event': 'data', 'peerId': 'p1', 'bytes': <int>[]},
        {'event': 'mtu', 'peerId': 'unknown-peer', 'mtu': 500},
        {'event': 'something-else', 'peerId': 'p1'},
      ]) {
        await emit(bad);
      }

      expect(peers, isEmpty);
      expect(data, isEmpty);
      expect(radio.malformedEvents, 14,
          reason: 'counted rather than thrown: a native side on a different '
              'version must not crash the relay, and silence would make the '
              'eventual debugging impossible');
    });

    test('an MTU the platform did not really negotiate is clamped down',
        () async {
      // Clamping low costs extra writes. Trusting a number that is too large
      // gets writes rejected, or silently truncated into corrupt frames.
      await radio.start();
      await emit({'event': 'peer', 'peerId': 'p1', 'connected': true, 'mtu': 9999});
      expect(radio.mtuFor('p1'), 517);
    });

    test('an MTU below the floor is raised to it', () async {
      await radio.start();
      await emit({'event': 'peer', 'peerId': 'p2', 'connected': true, 'mtu': 4});
      expect(radio.mtuFor('p2'), bleMinimumMtu);
    });

    test('a missing MTU is the floor, not a crash', () async {
      await radio.start();
      await emit({'event': 'peer', 'peerId': 'p3', 'connected': true});
      expect(radio.mtuFor('p3'), bleMinimumMtu);
    });

    test('an error on the event stream is counted, not fatal', () async {
      await radio.start();
      sink?.error(code: 'boom', message: 'radio fell over');
      await Future<void>.delayed(Duration.zero);
      expect(radio.malformedEvents, 1);
      // And the radio still works afterwards.
      await emit({'event': 'peer', 'peerId': 'p9', 'connected': true, 'mtu': 100});
      expect(radio.mtuFor('p9'), 100);
    });
  });
}

String? _peerOf(MethodCall call) {
  final args = call.arguments;
  if (args is! Map) return null;
  final peer = args.cast<Object?, Object?>()['peerId'];
  return peer is String ? peer : null;
}
