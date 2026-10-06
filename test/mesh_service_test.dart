// When this phone is in the mesh, and how what it carries gets out.
//
// The radio is faked (FakeBleRadio, which enforces the MTU and the link
// semantics) and so is HQ, so this proves the policy and the uplink — not
// Bluetooth itself, which only a handset can.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rainbow_app/core/mesh/ble_mesh_transport.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/services/mesh_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<bool> asks;
  late bool permitted;
  late List<http.Request> requests;
  late http.Response Function(http.Request) hq;
  late List<FakeBleRadio> radios;

  MeshEnvelope envelope(int seed) => MeshEnvelope(
        id: Uint8List.fromList(List<int>.generate(meshIdLength, (i) => (seed * 17 + i) % 256)),
        ttl: meshDefaultTtl,
        createdAt: DateTime.now().toUtc(),
        keyId: 1,
        sealed: Uint8List.fromList(List<int>.generate(60, (i) => (seed + i) % 256)),
      );

  MeshService service({String? base = 'https://hq.test'}) => MeshService(
        radioFactory: () {
          final radio = FakeBleRadio('me-${radios.length}');
          radios.add(radio);
          return radio;
        },
        httpClient: MockClient((request) async {
          requests.add(request);
          return hq(request);
        }),
        permissions: ({required bool ask}) async {
          asks.add(ask);
          return permitted;
        },
        hqBaseUrl: () => base,
        uplinkInterval: const Duration(hours: 1),
        peerSettle: Duration.zero,
      );

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    asks = [];
    permitted = true;
    requests = [];
    radios = [];
    hq = (_) => http.Response(jsonEncode({'ok': true, 'done': <String>[]}), 200);
  });

  group('who relays', () {
    test('a responder relays by default, and is asked for Bluetooth', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      expect(mesh.isRunning, isTrue);
      expect(asks, [true]);
      await mesh.onSignedOut();
    });

    test('a citizen does not relay until they choose to', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: false);
      expect(mesh.isRunning, isFalse);
      expect(asks, isEmpty, reason: 'nobody is asked for a feature they did not turn on');

      expect(await mesh.setRelayEnabled(true), isTrue);
      expect(mesh.isRunning, isTrue);
      expect(asks, [true]);

      await mesh.setRelayEnabled(false);
      expect(mesh.isRunning, isFalse);
      // And the choice is remembered for the next sign-in.
      await mesh.onSignedIn(isResponder: false);
      expect(mesh.isRunning, isFalse);
      await mesh.onSignedOut();
    });

    test('a responder who switched it off stays off', () async {
      SharedPreferences.setMockInitialValues({meshRelayPreferenceKey: false});
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      expect(mesh.isRunning, isFalse);
    });

    test('Bluetooth refused means not running, and saying so', () async {
      permitted = false;
      final mesh = service();
      await mesh.onSignedIn(isResponder: false);
      expect(await mesh.setRelayEnabled(true), isFalse);
      expect(mesh.isRunning, isFalse);
    });

    test('signing out while Bluetooth is being asked for leaves it off', () async {
      late MeshService mesh;
      mesh = MeshService(
        radioFactory: () => FakeBleRadio('me'),
        permissions: ({required bool ask}) async {
          await mesh.onSignedOut(); // they gave up and signed out mid-prompt
          return true;
        },
        hqBaseUrl: () => null,
      );
      await mesh.onSignedIn(isResponder: true);
      expect(mesh.isRunning, isFalse);
      expect(mesh.node, isNull);
    });

    test('nothing starts without a signed-in person', () async {
      final mesh = service();
      expect(await mesh.start(ask: true), isFalse);
      expect(asks, isEmpty);
    });

    test('signing out stops the radio and drops what it carried', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      await mesh.node!.send(envelope(1));
      expect(mesh.node!.relay.pending, hasLength(1));
      final radio = radios.single;

      await mesh.onSignedOut();
      expect(mesh.isRunning, isFalse);
      expect(mesh.node, isNull);
      // Signed out, it will not start again for an emergency either.
      expect(await mesh.nodeForEmergency(), isNull);
      // A fresh sign-in gets a fresh radio, not the old one.
      await mesh.onSignedIn(isResponder: true);
      expect(radios.last, isNot(same(radio)));
      expect(mesh.node!.relay.pending, isEmpty);
      await mesh.onSignedOut();
    });
  });

  group('a person\'s own emergency', () {
    test('never prompts for Bluetooth in the middle of one', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: false);
      // Never run on this phone: using it now could mean a permission dialog.
      expect(await mesh.nodeForEmergency(), isNull);
      expect(asks, isEmpty);
      expect(mesh.isRunning, isFalse);
    });

    test('uses the mesh even for a citizen who has not opted in, once it has worked', () async {
      SharedPreferences.setMockInitialValues({meshHasRunPreferenceKey: true});
      final mesh = service();
      await mesh.onSignedIn(isResponder: false);
      expect(mesh.isRunning, isFalse);

      final node = await mesh.nodeForEmergency();
      expect(node, isNotNull);
      expect(mesh.isRunning, isTrue);
      expect(asks, [false], reason: 'checked, never asked');
      await mesh.onSignedOut();
    });

    test('returns the running node when already relaying', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      final running = mesh.node;
      expect(await mesh.nodeForEmergency(), same(running));
      await mesh.onSignedOut();
    });
  });

  group('reaching HQ', () {
    test('uploads what it holds and stops carrying what HQ finished with', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      final held = envelope(2);
      await mesh.node!.send(held);
      hq = (_) => http.Response(jsonEncode({'ok': true, 'done': [held.idHex]}), 200);

      expect(await mesh.uplink(), 1);
      final request = requests.last;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://hq.test/api/mesh/ingest');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')),
          reason: 'the endpoint takes frames from anybody; the uploader is not identified');
      final frames = (jsonDecode(request.body) as Map<String, dynamic>)['frames'] as List;
      expect(frames, [held.toBase64()]);
      expect(mesh.node!.relay.pending, isEmpty);
      // Delivered, not forgotten: a peer cannot hand it back.
      expect(mesh.node!.relay.hasSeen(held.idHex), isTrue);
      await mesh.onSignedOut();
    });

    test('no network keeps everything held, quietly', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      await mesh.node!.send(envelope(3));
      hq = (_) => throw const SocketLikeException();

      expect(await mesh.uplink(), 0);
      expect(mesh.node!.relay.pending, hasLength(1));
      await mesh.onSignedOut();
    });

    test('a refusal or a rate limit keeps everything held', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      await mesh.node!.send(envelope(4));
      hq = (_) => http.Response(jsonEncode({'ok': false, 'retryAfter': 60}), 429);

      expect(await mesh.uplink(), 0);
      expect(mesh.node!.relay.pending, hasLength(1));
      await mesh.onSignedOut();
    });

    test('with no HQ configured it does not try', () async {
      final mesh = service(base: null);
      await mesh.onSignedIn(isResponder: true);
      await mesh.node!.send(envelope(5));
      expect(await mesh.uplink(), 0);
      expect(requests, isEmpty);
      await mesh.onSignedOut();
    });

    test('an alert carried in from a stranger is uploaded on arrival', () async {
      final mesh = service();
      await mesh.onSignedIn(isResponder: true);
      final mine = radios.single;

      // A stranger's phone, holding a sealed alert, comes into range.
      final strangerRadio = FakeBleRadio('stranger');
      final stranger = BleMeshTransport(strangerRadio);
      await stranger.start();
      final carried = envelope(6);
      hq = (_) => http.Response(jsonEncode({'ok': true, 'done': [carried.idHex]}), 200);

      strangerRadio.link(mine);
      await settle();
      await stranger.offer(carried);
      await settle();

      expect(requests, isNotEmpty);
      final frames = (jsonDecode(requests.last.body) as Map<String, dynamic>)['frames'] as List;
      final ids = frames.map((f) => MeshEnvelope.fromBase64(f as String)?.idHex);
      expect(ids, contains(carried.idHex));
      expect(mesh.node!.relay.pending, isEmpty);
      await stranger.stop();
      await mesh.onSignedOut();
    });
  });

  test('a peer arriving is offered everything held', () async {
    final mesh = service(base: null);
    await mesh.onSignedIn(isResponder: true);
    final held = envelope(7);
    await mesh.node!.send(held);

    final neighbourRadio = FakeBleRadio('neighbour');
    final neighbour = BleMeshTransport(neighbourRadio);
    final received = <MeshEnvelope>[];
    neighbour.inbound.listen(received.add);
    await neighbour.start();

    neighbourRadio.link(radios.single);
    await settle();

    expect(received.map((e) => e.idHex), [held.idHex]);
    // One hop spent on the way.
    expect(received.single.ttl, meshDefaultTtl - 1);
    await neighbour.stop();
    await mesh.onSignedOut();
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
