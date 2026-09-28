// The moment the offline channels stop being decoration.
//
// Both channels were built, tested and unreachable: nothing in the app called
// any of them, so a report raised with no data went into the local queue and
// waited for a network that might not come back for hours. These tests are about
// the call — when it happens, when it must NOT happen, and what it costs.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/mesh/ble_mesh_transport.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/mesh_node.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';
import 'package:rainbow_app/core/offline/offline_escalation.dart';
import 'package:rainbow_app/core/offline/offline_ref.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';
import 'package:rainbow_app/core/offline/sms_device_key.dart';
import 'package:rainbow_app/core/offline/sms_sender.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hq = meshGenerateHqKeypair(random: meshTestRandom(71));
  final deviceKey =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 17) % 256));
  final deviceRef = Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01]);
  final at = DateTime.utc(2026, 9, 28, 20);

  /// A secure-storage stand-in, so nothing here touches a keystore.
  late Map<String, String> stored;
  late SmsDeviceKeyService keys;
  late List<String> sentBodies;
  late String? sentTo;
  late SmsSendOutcome nextOutcome;

  setUp(() {
    stored = {
      'sms_device_ref': base64Encode(deviceRef),
      'sms_device_secret': base64Encode(deviceKey),
    };
    keys = SmsDeviceKeyService(storage: _FakeStorage(stored));
    sentBodies = [];
    sentTo = null;
    nextOutcome = SmsSendOutcome.sentSilently;
    SmsSender.isAndroidOverride = true;
    SmsSender.sendOverride = (destination, body) async {
      sentTo = destination;
      sentBodies.add(body);
      if (nextOutcome == SmsSendOutcome.failed) return 0;
      return 1;
    };
  });

  tearDown(() {
    SmsSender.sendOverride = null;
    SmsSender.isAndroidOverride = null;
    SmsSender.launchOverride = null;
  });

  OfflineEscalation escalation({MeshNode? mesh, String? shortcode = '32123'}) =>
      OfflineEscalation(
        keys: keys,
        mesh: mesh,
        shortcode: shortcode,
        hqMeshPublicKey: hq.publicKey,
        clock: () => at,
      );

  group('a CRITICAL report with no data path', () {
    test('goes out by SMS, authenticated, in one message', () async {
      final localId = newOfflineLocalId(now: at);
      final report = await escalation().escalate(
        localId: localId,
        type: 'Kidnap - Immediate Abduction',
        severity: 'CRITICAL',
        latitude: 9.89654,
        longitude: 8.85831,
      );

      expect(report.smsOutcome, SmsSendOutcome.sentSilently);
      expect(sentTo, '32123');
      expect(sentBodies.single.length, 75, reason: 'one GSM-7 segment, one cost');

      // And HQ can open it, with the right category and the tag that lets it
      // recognise the same report arriving again.
      final decoded =
          decodeSmsAlert(body: sentBodies.single, key: deviceKey);
      expect(decoded.payload, isNotNull);
      expect(decoded.payload!.categoryCode, 0, reason: 'Kidnap');
      expect(decoded.payload!.severityCode, 3);
      expect(decoded.payload!.latitude, closeTo(9.89654, 0.00001));
      expect(
        decoded.payload!.localRef,
        offlineRefOf(localId),
        reason: 'the tag HQ deduplicates on',
      );
    });

    test('an unrecognised type becomes SOS, not a wrong category', () async {
      // A dispatcher reading SOS investigates. One reading "Flood" for a
      // kidnapping does not.
      await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'EMERGENCY - Silent SOS',
        severity: 'CRITICAL',
      );
      expect(
        decodeSmsAlert(body: sentBodies.single, key: deviceKey)
            .payload!
            .categoryCode,
        offlineCategorySos,
      );
    });

    test('a report with no GPS fix says so rather than inventing a place',
        () async {
      await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Fire - Building Fire',
        severity: 'HIGH',
      );
      final p = decodeSmsAlert(body: sentBodies.single, key: deviceKey).payload!;
      expect(p.latitude, isNull);
      expect(p.longitude, isNull);
    });
  });

  group('when it must not spend a message', () {
    test('the report already reached HQ over data', () async {
      final r = await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
        dataSendSucceeded: true,
      );
      expect(sentBodies, isEmpty);
      expect(r.reachedAnything, isFalse);
    });

    test('there is no cellular service at all', () async {
      await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
        hasCellularSignal: false,
      );
      expect(sentBodies, isEmpty);
    });

    test('a MEDIUM report that can wait for the network', () async {
      await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Flood - Blocked Drainage',
        severity: 'MEDIUM',
      );
      expect(sentBodies, isEmpty);
    });

    test('this handset has never registered a device key', () async {
      // Sending unauthenticated costs money to produce something HQ correctly
      // refuses.
      stored.clear();
      await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
      );
      expect(sentBodies, isEmpty);
    });

    test('no shortcode is configured', () async {
      // A message with nowhere to go costs money and reaches nobody.
      final r = await escalation(shortcode: null).escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
      );
      expect(sentBodies, isEmpty);
      expect(r.smsOutcome, SmsSendOutcome.notNeeded);
    });

    test('the local id carries no dedup tag', () async {
      // An id from before the tag existed. Sending it would produce an alert HQ
      // cannot recognise as a duplicate, so the same emergency would be filed
      // twice and two units sent to one place.
      final r = await escalation().escalate(
        localId: 'OFFLINE_1790500000000',
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
      );
      expect(sentBodies, isEmpty);
      expect(r.because, contains('dedup tag'));
    });
  });

  group('the mesh, when there is a radio', () {
    test('carries the same bytes as the SMS would', () async {
      // One sealed body, both channels. Not two payloads — the mesh plaintext IS
      // the SMS body, which is what makes a mesh alert unforgeable and lets the
      // two channels deduplicate against each other.
      final radio = FakeBleRadio('self');
      final peerRadio = FakeBleRadio('peer');
      final transport = BleMeshTransport(radio, clock: () => at);
      final peer = BleMeshTransport(peerRadio, clock: () => at);
      final node = MeshNode(
        relay: MeshRelay(clock: () => at),
        transport: transport,
      );
      final arrived = <String>[];
      peer.inbound.listen((e) {
        final opened = meshOpen(sealed: e.sealed, hqPrivateKey: hq.privateKey);
        if (opened != null) arrived.add(ascii.decode(opened));
      });
      addTearDown(() async {
        await transport.dispose();
        await peer.dispose();
        await radio.dispose();
        await peerRadio.dispose();
      });

      await node.start();
      await peer.start();
      radio.link(peerRadio);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final r = await escalation(mesh: node).escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Community attack - Riot',
        severity: 'CRITICAL',
      );
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(r.meshSent, isTrue);
      expect(arrived, hasLength(1));
      expect(arrived.single, sentBodies.single,
          reason: 'the mesh carried exactly what the SMS carried');
    });

    test('goes even for a MEDIUM report, because it costs nothing', () async {
      // The SMS test exists to protect a budget. A relayed envelope spends
      // somebody's battery, not somebody's airtime, so the severity line does
      // not apply.
      final radio = FakeBleRadio('self');
      final transport = BleMeshTransport(radio, clock: () => at);
      final node =
          MeshNode(relay: MeshRelay(clock: () => at), transport: transport);
      addTearDown(() async {
        await transport.dispose();
        await radio.dispose();
      });
      await node.start();

      final r = await escalation(mesh: node).escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Flood - Blocked Drainage',
        severity: 'MEDIUM',
      );
      expect(sentBodies, isEmpty, reason: 'no message bought');
      expect(r.meshSent, isTrue);
      expect(node.relay.length, 1, reason: 'held until somebody walks past');
    });

    test('there is no mesh when there is no radio, and it says so', () async {
      // Today's production state: the BLE native halves are not written, so
      // nothing constructs a node. Visible rather than hidden, so nobody
      // believes the mesh is carrying traffic when it is not.
      final r = await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
      );
      expect(r.meshSent, isFalse);
      expect(r.smsOutcome, SmsSendOutcome.sentSilently);
    });
  });

  group('it cannot take the SOS down with it', () {
    test('a platform failure is reported, not thrown', () async {
      SmsSender.sendOverride =
          (d, b) async => throw PlatformException(code: 'SMS_DENIED');
      final r = await escalation().escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
      );
      // Android falls through to the composer, which has no launcher here.
      expect(r.smsOutcome, SmsSendOutcome.failed);
    });

    test('a broken key store is reported, not thrown', () async {
      final broken = OfflineEscalation(
        keys: SmsDeviceKeyService(storage: _ThrowingStorage()),
        shortcode: '32123',
        clock: () => at,
      );
      final r = await broken.escalate(
        localId: newOfflineLocalId(now: at),
        type: 'Kidnap - Held Hostage',
        severity: 'CRITICAL',
      );
      expect(r.reachedAnything, isFalse);
    });
  });

  group('the category and severity maps', () {
    test('every label maps to its own index, and the order is the wire order',
        () {
      // The index IS the wire value, so this list is append-only. Reordering the
      // categories would silently relabel every alert in flight — a kidnapping
      // arriving at HQ as a flood. The list is repeated here on purpose: if
      // somebody reorders alert_categories.dart, this fails.
      const expected = [
        'Kidnap',
        'Fire',
        'Drug abuse',
        'Police brutality',
        'Flood',
        'Cyber crime',
        'Child abuse',
        'Domestic violence',
        'Cattle rustling',
        'Community attack',
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(smsCategoryCodeFor(expected[i]), i, reason: expected[i]);
        expect(smsCategoryCodeFor('${expected[i]} - Something'), i);
      }
    });

    test('an unknown or empty type is an SOS', () {
      for (final t in ['', 'Nonsense', 'EMERGENCY - Silent SOS', ' - ']) {
        expect(smsCategoryCodeFor(t), offlineCategorySos);
      }
    });

    test('severities map in wire order and default to MEDIUM', () {
      expect(smsSeverityCodeFor('LOW'), 0);
      expect(smsSeverityCodeFor('medium'), 1);
      expect(smsSeverityCodeFor('HIGH'), 2);
      expect(smsSeverityCodeFor('CRITICAL'), 3);
      expect(smsSeverityCodeFor('nonsense'), 1);
    });
  });
}

/// An in-memory stand-in for the keystore, so nothing here touches one.
class _FakeStorage implements FlutterSecureStorage {
  _FakeStorage(this.values);
  final Map<String, String> values;

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions,
      dynamic wOptions}) async => values[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A keystore that is unavailable, which happens on real handsets.
class _ThrowingStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions,
      dynamic wOptions}) async => throw StateError('keystore unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
