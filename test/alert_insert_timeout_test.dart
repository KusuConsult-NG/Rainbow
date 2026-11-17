// An alert insert that never answers must not hold the report.
//
// With no limit on the insert, a connection that is "up" and carries nothing
// (a captive portal, a dead 2G link) held submitAlert for as long as the OS's
// TCP timeouts allowed, and none of the fallbacks ran: not the offline queue,
// not the mesh or SMS escalation, and not the SOS escalation SMS, which
// startEmergency sends only after submitAlert returns.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:rainbow_app/core/offline/offline_escalation.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/sqlite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/offline_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SqliteService sqlite;
  late List<String> escalated;

  setUp(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? <String>['mobile'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => call.method == 'isLocationServiceEnabled' ? false : 0,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, 'rainbow_offline.db'));
    sqlite = SqliteService();

    escalated = <String>[];
    AlertService.escalateOverride = ({
      required String localId,
      required String type,
      required String severity,
      double? latitude,
      double? longitude,
    }) async {
      escalated.add(localId);
      return const OfflineEscalationReport(because: 'test');
    };
    AlertService.insertLimit = const Duration(milliseconds: 100);
  });

  tearDown(() {
    AlertService.escalateOverride = null;
    AlertService.insertLimit = const Duration(seconds: 15);
  });

  test('an insert that never answers falls through to the offline path', () async {
    // The server accepts the connection and never replies.
    installOfflineSupabase(handler: (_) => Completer<http.Response>().future);

    final id = await AlertService()
        .submitAlert(
          type: 'PANIC SOS',
          description: 'Public Panic Button Activated',
          reportedBy: 'test-user',
          isCritical: true,
          lookUpLocation: false,
        )
        .timeout(const Duration(seconds: 5),
            onTimeout: () => fail('submitAlert was still waiting on the insert'));

    final pending = await sqlite.getPendingAlerts();
    expect(pending, hasLength(1), reason: 'queued on the phone');
    expect(id, pending.single['local_id'], reason: 'the caller gets the local id');
    expect(escalated, [id], reason: 'and the offline channels were tried');
  });

  // startSosTracking may ask for location permission and wait, with no limit,
  // for an answer that a backgrounded app cannot get. The alert id, and with
  // it startEmergency's escalation SMS, used to wait on that.
  test('tracking that never finishes starting does not hold the alert id', () async {
    installOfflineSupabase(handler: jsonRows([
      {'id': '7f3a1c94-2b6d-4e58-9a01-5c8e2d4f6b70'},
    ]));
    AlertService.insertLimit = const Duration(seconds: 5);
    final started = <String>[];
    AlertService.startTrackingOverride = (alertId, userId) {
      started.add(alertId);
      return Completer<void>().future; // a permission request nobody answers
    };
    addTearDown(() => AlertService.startTrackingOverride = null);

    final id = await AlertService()
        .submitAlert(
          type: 'PANIC SOS',
          description: 'Public Panic Button Activated',
          reportedBy: 'test-user',
          isCritical: true,
          lookUpLocation: false,
        )
        .timeout(const Duration(seconds: 3),
            onTimeout: () => fail('submitAlert waited for tracking to start'));

    expect(id, '7f3a1c94-2b6d-4e58-9a01-5c8e2d4f6b70');
    expect(started, [id], reason: 'tracking is still started, for the real id');
  });

  // MeshNode.send awaits a Bluetooth exchange with nearby phones, with no
  // limit. submitAlert awaited the escalation, and only then started tracking.
  test('an offline escalation that never finishes holds neither the id nor tracking', () async {
    installOfflineSupabase(handler: jsonError(503, 'down'));
    AlertService.insertLimit = const Duration(seconds: 5);
    AlertService.offlineEscalationLimit = const Duration(milliseconds: 100);
    addTearDown(() => AlertService.offlineEscalationLimit = const Duration(seconds: 20));
    AlertService.escalateOverride = ({
      required String localId,
      required String type,
      required String severity,
      double? latitude,
      double? longitude,
    }) {
      escalated.add(localId);
      return Completer<OfflineEscalationReport>().future; // a stalled exchange
    };
    final started = <String>[];
    AlertService.startTrackingOverride = (alertId, userId) async => started.add(alertId);
    addTearDown(() => AlertService.startTrackingOverride = null);

    final id = await AlertService()
        .submitAlert(
          type: 'PANIC SOS',
          description: 'Public Panic Button Activated',
          reportedBy: 'test-user',
          isCritical: true,
          lookUpLocation: false,
        )
        .timeout(const Duration(seconds: 3),
            onTimeout: () => fail('submitAlert waited for the offline escalation'));

    expect((await sqlite.getPendingAlerts()).single['local_id'], id);
    expect(escalated, [id], reason: 'the offline channels were still tried');
    expect(started, [id], reason: 'and tracking started, not held behind them');
  });

  // Only one flush runs at a time, so a request in it that never answered
  // kept every later flush, and every queued SOS, waiting until a restart.
  test('a flush whose insert never answers ends, and leaves the row for retry', () async {
    // Queue one report: the first insert fails outright.
    installOfflineSupabase(handler: jsonError(503, 'down'));
    final id = await AlertService().submitAlert(
      type: 'PANIC SOS',
      description: 'Public Panic Button Activated',
      reportedBy: 'test-user',
      isCritical: true,
      lookUpLocation: false,
    );
    expect((await sqlite.getPendingAlerts()).single['local_id'], id);

    // Now the server accepts the connection and never replies.
    installOfflineSupabase(handler: (_) => Completer<http.Response>().future);
    AlertService.resetFlushGuard();
    AlertService.alreadyDeliveredOverride = (_) async => null;
    addTearDown(() => AlertService.alreadyDeliveredOverride = null);

    final synced = await AlertService()
        .flushOfflineQueue()
        .timeout(const Duration(seconds: 3),
            onTimeout: () => fail('the flush was still waiting on the insert'));
    expect(synced, isEmpty);
    final pending = await sqlite.getPendingAlerts();
    expect(pending.single['local_id'], id, reason: 'still queued');
    expect(pending.single['sync_status'], 'FAILED', reason: 'and retried by the next flush');
  });

  test('an insert that answers in time is not affected', () async {
    installOfflineSupabase(handler: jsonRows([
      {'id': '7f3a1c94-2b6d-4e58-9a01-5c8e2d4f6b70'},
    ]));
    AlertService.insertLimit = const Duration(seconds: 5);

    final id = await AlertService().submitAlert(
      type: 'PANIC SOS',
      description: 'Public Panic Button Activated',
      reportedBy: 'test-user',
      isCritical: true,
      lookUpLocation: false,
    );

    expect(id, '7f3a1c94-2b6d-4e58-9a01-5c8e2d4f6b70');
    expect(await sqlite.getPendingAlerts(), isEmpty);
    expect(escalated, isEmpty);
  });
}
