// Offline SOS queue — the path that matters most when the network is down.
//
// These run against a REAL SQLite engine (sqflite_common_ffi) rather than mocks,
// so the schema and the code that reads it are checked against each other. That
// is the whole point: the bug these tests were written for was a column-name
// mismatch between the two, which no mock would have caught.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/sqlite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Jos, Plateau State — a distinctive coordinate so a silent default is obvious.
  const testLat = 9.8965;
  const testLng = 8.8583;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  _severityRegressionTests();

  // A queued alert is an UNSENT EMERGENCY. The v1 -> v2 migration rebuilds the
  // table to drop NOT NULL from lat/lng, so it must carry existing rows across
  // rather than silently dropping them.
  group('v1 -> v2 schema migration', () {
    test('pending alerts survive the upgrade', () async {
      final dir = await databaseFactory.getDatabasesPath();
      final path = p.join(dir, 'rainbow_offline.db');
      await databaseFactory.deleteDatabase(path);

      // Build a v1 database by hand: lat/lng NOT NULL, no onUpgrade.
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE offline_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                local_id TEXT UNIQUE NOT NULL,
                type TEXT NOT NULL,
                description TEXT,
                lat REAL NOT NULL,
                lng REAL NOT NULL,
                priority TEXT NOT NULL,
                is_anonymous INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                sync_status TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE offline_media (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                local_alert_id TEXT NOT NULL,
                local_file_path TEXT NOT NULL,
                remote_storage_path TEXT,
                upload_status TEXT NOT NULL
              )
            ''');
          },
        ),
      );
      await v1.insert('offline_queue', {
        'local_id': 'LEGACY_SOS_1',
        'type': 'SOS',
        'description': 'Queued before the upgrade',
        'lat': 9.8965,
        'lng': 8.8583,
        'priority': 'CRITICAL',
        'is_anonymous': 0,
        'created_at': '2026-08-13T14:00:00.000Z',
        'sync_status': 'PENDING',
      });
      await v1.close();

      // Opening through SqliteService triggers the v2 migration.
      final pending = await SqliteService().getPendingAlerts();
      final legacy = pending.where((r) => r['local_id'] == 'LEGACY_SOS_1');

      expect(legacy, isNotEmpty,
          reason: 'the migration must not drop unsent emergencies',);
      expect(legacy.first['lat'], closeTo(9.8965, 0.000001));
      expect(legacy.first['description'], 'Queued before the upgrade');

      // ...and the new nullable column now accepts a null fix.
      await SqliteService().enqueueAlert(
        localId: 'POST_UPGRADE_NO_FIX',
        type: 'SOS',
        description: 'no gps',
        lat: null,
        lng: null,
        priority: 'HIGH',
        isAnonymous: false,
        createdAt: '2026-08-13T15:00:00.000Z',
      );
      final after = await SqliteService().getPendingAlerts();
      expect(
        after.firstWhere((r) => r['local_id'] == 'POST_UPGRADE_NO_FIX')['lat'],
        isNull,
      );
    });
  });

  group('offline queue round-trip', () {
    late SqliteService sqlite;

    setUp(() async {
      sqlite = SqliteService();
      // SqliteService owns its path, so this is a real file-backed database
      // served by the ffi factory. Truncate rather than recreate so each test
      // starts clean.
      final db = await sqlite.database;
      await db.delete('offline_queue');
      await db.delete('offline_media');
    });

    Future<Map<String, dynamic>> enqueueAndRead(String localId) async {
      await sqlite.enqueueAlert(
        localId: localId,
        type: 'SOS',
        description: 'Armed men sighted near the market',
        lat: testLat,
        lng: testLng,
        priority: 'CRITICAL',
        isAnonymous: false,
        createdAt: '2026-08-13T14:00:00.000Z',
      );
      final pending = await sqlite.getPendingAlerts();
      final row = pending.firstWhere((r) => r['local_id'] == localId);
      return row;
    }

    test('an enqueued alert is returned by getPendingAlerts', () async {
      final row = await enqueueAndRead('OFFLINE_TEST_1');
      expect(row['type'], 'SOS');
      expect(row['priority'], 'CRITICAL');
      expect(row['sync_status'], 'PENDING');
    });

    test('coordinates survive the round-trip through SQLite', () async {
      final row = await enqueueAndRead('OFFLINE_TEST_2');
      expect(row['lat'], closeTo(testLat, 0.000001));
      expect(row['lng'], closeTo(testLng, 0.000001));
    });

    // REGRESSION: buildOfflineSyncPayload read row['latitude'] / row['longitude'],
    // but the schema stores lat / lng. Both lookups returned null, so every alert
    // queued while offline reached HQ with NO COORDINATES — in exactly the
    // no-signal scenario the offline queue exists to serve.
    test(
        'REGRESSION: sync payload carries the queued coordinates, not null',
        () async {
      final row = await enqueueAndRead('OFFLINE_TEST_3');
      final payload = AlertService.buildOfflineSyncPayload(row);

      expect(payload['latitude'], isNotNull,
          reason: 'an SOS synced from the offline queue must keep its location',);
      expect(payload['longitude'], isNotNull,
          reason: 'an SOS synced from the offline queue must keep its location',);
      expect(payload['latitude'], closeTo(testLat, 0.000001));
      expect(payload['longitude'], closeTo(testLng, 0.000001));
    });

    test('sync payload preserves identity, type and severity', () async {
      final row = await enqueueAndRead('OFFLINE_TEST_4');
      final payload = AlertService.buildOfflineSyncPayload(row);

      expect(payload['local_id'], 'OFFLINE_TEST_4');
      expect(payload['type'], 'SOS');
      expect(payload['severity'], 'CRITICAL');
      expect(payload['status'], 'PENDING');
      expect(payload['description'], 'Armed men sighted near the market');
    });

    // An incident raised at 14:00 offline and synced at 18:00 is a 14:00
    // incident. Letting the column default to NOW() at insert time misreports
    // when the emergency actually happened.
    test('sync payload preserves the original incident time', () async {
      final row = await enqueueAndRead('OFFLINE_TEST_5');
      final payload = AlertService.buildOfflineSyncPayload(row);
      expect(payload['created_at'], '2026-08-13T14:00:00.000Z');
    });

    test('a synced alert is no longer pending', () async {
      await enqueueAndRead('OFFLINE_TEST_6');
      await sqlite.updateSyncStatus('OFFLINE_TEST_6', 'SYNCED');

      final pending = await sqlite.getPendingAlerts();
      expect(
        pending.where((r) => r['local_id'] == 'OFFLINE_TEST_6'),
        isEmpty,
      );
    });

    // getPendingAlerts selects PENDING *or* FAILED, so a failed replay is retried
    // on the next connectivity restore rather than being dropped.
    test('a FAILED alert stays in the queue for retry', () async {
      await enqueueAndRead('OFFLINE_TEST_7');
      await sqlite.updateSyncStatus('OFFLINE_TEST_7', 'FAILED');

      final pending = await sqlite.getPendingAlerts();
      expect(
        pending.where((r) => r['local_id'] == 'OFFLINE_TEST_7'),
        isNotEmpty,
        reason: 'a failed sync must be retried, not silently lost',
      );
    });

    // REGRESSION (C-5): submitAlert used to default missing coordinates to
    // (9.9167, 8.8917) — the centre of Jos — so an SOS with no GPS fix reached
    // HQ as a confident pin and responders were dispatched to a location
    // invented by a `??` operator. A missing location must stay missing.
    test('REGRESSION: an alert with no GPS fix queues WITHOUT coordinates',
        () async {
      await sqlite.enqueueAlert(
        localId: 'OFFLINE_NO_FIX',
        type: 'SOS',
        description: 'No GPS lock available',
        lat: null,
        lng: null,
        priority: 'CRITICAL',
        isAnonymous: false,
        createdAt: '2026-08-13T14:00:00.000Z',
      );

      final row = (await sqlite.getPendingAlerts())
          .firstWhere((r) => r['local_id'] == 'OFFLINE_NO_FIX');
      expect(row['lat'], isNull);
      expect(row['lng'], isNull);

      final payload = AlertService.buildOfflineSyncPayload(row);
      expect(payload['latitude'], isNull,
          reason: 'must not invent a location for an unlocated SOS',);
      expect(payload['longitude'], isNull);
      // Jos centre, the old fabricated fallback.
      expect(payload['latitude'], isNot(closeTo(9.9167, 0.01)));
    });

    test('queued media is associated with its alert', () async {
      await enqueueAndRead('OFFLINE_TEST_8');
      await sqlite.enqueueMedia(
        localAlertId: 'OFFLINE_TEST_8',
        localFilePath: '/tmp/evidence.jpg',
      );

      final media = await sqlite.getPendingMedia('OFFLINE_TEST_8');
      expect(media, hasLength(1));
      expect(media.first['local_file_path'], '/tmp/evidence.jpg');
    });
  });
}

// ── REGRESSION: a panic SOS filed as MEDIUM ─────────────────────────────────
//
// `submitAlert` took an `isCritical` flag, and never read it. The body graded
// every alert from `priority`, which defaults to MEDIUM — so
// `EmergencyNotifier.startEmergency()`, which passes `isCritical: true` and no
// `priority`, filed every PANIC SOS at MEDIUM. On the HQ board that put the
// most urgent thing a citizen can do below a report of a blocked drain, and
// outside the CRITICAL filter entirely.
//
// Nothing caught it: the provider's own test verifies that `isCritical: true`
// is PASSED, which it was. The parameter is right there in the call and looks
// like it works. It was found by pressing the button in a browser and reading
// the row that came out.
//
// The assertion goes through the offline queue because that is a real path
// through the real `submitAlert`: with no Supabase client configured the insert
// throws, the catch enqueues, and the queued row carries the same severity the
// insert would have.
void _severityRegressionTests() {
  group('REGRESSION: isCritical must reach the severity that is stored', () {
    late SqliteService sqlite;

    setUp(() async {
      // submitAlert reaches for platform channels (location, connectivity)
      // before it writes anything; without the binding it throws before the
      // offline fallback and nothing is queued at all.
      TestWidgetsFlutterBinding.ensureInitialized();

      // submitAlert asks connectivity_plus whether it is online, and
      // geolocator where it is, before it writes anything. Neither plugin has
      // an implementation in a test, and the MissingPluginException escapes
      // the whole method — so without these stubs nothing is written and
      // nothing is queued either, which is worth knowing in its own right.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? <String>['wifi'] : null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return false;
            case 'checkPermission':
            case 'requestPermission':
              return 0; // denied — the C-5 path: no fix, no fabricated pin
            default:
              return null;
          }
        },
      );

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, 'rainbow_offline.db'));
      sqlite = SqliteService();
    });

    Future<String?> queuedPriority() async {
      final pending = await sqlite.getPendingAlerts();
      return pending.isEmpty ? null : pending.last['priority'] as String?;
    }

    test('isCritical: true is stored as CRITICAL, not the MEDIUM default',
        () async {
      await AlertService().submitAlert(
        type: 'PANIC SOS',
        description: 'Public Panic Button Activated',
        reportedBy: 'test-user',
        isCritical: true,
      );

      expect(
        await queuedPriority(),
        'CRITICAL',
        reason: 'startEmergency() passes isCritical: true and no priority. '
            'If this reads MEDIUM, every panic SOS is mis-graded again.',
      );
    });

    test('without isCritical the explicit priority is honoured', () async {
      await AlertService().submitAlert(
        type: 'INCIDENT',
        description: 'Blocked drainage',
        reportedBy: 'test-user',
        priority: AlertPriority.high,
      );

      expect(await queuedPriority(), 'HIGH');
    });

    test('an ordinary report with neither is still MEDIUM', () async {
      await AlertService().submitAlert(
        type: 'INCIDENT',
        description: 'Something minor',
        reportedBy: 'test-user',
      );

      expect(await queuedPriority(), 'MEDIUM');
    });
  });
}
