// Offline SOS queue — the path that matters most when the network is down.
//
// These run against a REAL SQLite engine (sqflite_common_ffi) rather than mocks,
// so the schema and the code that reads it are checked against each other. That
// is the whole point: the bug these tests were written for was a column-name
// mismatch between the two, which no mock would have caught.
import 'package:flutter_test/flutter_test.dart';
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
          reason: 'an SOS synced from the offline queue must keep its location');
      expect(payload['longitude'], isNotNull,
          reason: 'an SOS synced from the offline queue must keep its location');
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
