// One emergency, three ways out, one incident at HQ.
//
// A report raised with no data can reach HQ by SMS within seconds, through the
// mesh minutes later, and from the phone's own queue when data returns. Those are
// three deliveries of one emergency, and recording three incidents means three
// units sent to one place while the next call waits.
//
// HQ deduplicates on a tag inside `local_id`, and as built that could never have
// matched: the tag was six arbitrary bytes and the id was `OFFLINE_<millis>`, a
// string those bytes do not appear in under any encoding. These tests pin the fix
// from both ends, because in the field the SMS usually wins and the design
// assumed the queue would.
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rainbow_app/core/offline/offline_ref.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/sqlite_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    AlertService.resetFlushGuard();
    AlertService.alreadyDeliveredOverride = null;
    AlertService.escalateOverride = null;
  });

  group('the tag that follows a report', () {
    test('an id carries a tag HQ can find inside it', () {
      // This is the whole property. HQ matches `local_id LIKE '%<hex>%'`, so the
      // hex has to literally appear in the id the queue will insert.
      final id = newOfflineLocalId();
      final hex = offlineRefHexOf(id);
      expect(hex, isNotNull);
      expect(id.contains(hex!), isTrue);
      expect(id.startsWith(offlineIdPrefix), isTrue,
          reason: 'wasQueuedOffline still has to recognise it');
    });

    test('the tag is six bytes, which is what the wire format carries', () {
      expect(offlineRefOf(newOfflineLocalId())!.length, offlineRefLength);
    });

    test('two reports never share a tag', () {
      // A dedup collision is not a duplicate — it is a DROPPED emergency: HQ
      // would decide the second incident had already been recorded. Six bytes of
      // a millisecond timestamp would collide constantly, which is why the tag is
      // random.
      final seen = <String>{};
      for (var i = 0; i < 2000; i++) {
        seen.add(offlineRefHexOf(newOfflineLocalId())!);
      }
      expect(seen, hasLength(2000));
    });

    test('an id from before the tag existed has none, and does not pretend to',
        () {
      // A caller that gets null must not invent one: a tag matching nothing lets
      // a duplicate through, and a tag matching something else DROPS a real
      // alert.
      for (final old in [
        'OFFLINE_1790500000000',
        'LOCAL_123',
        '8f14e45f-ea12-4b1b-9b1b-000000000000',
        '',
      ]) {
        expect(offlineRefOf(old), isNull, reason: old);
        expect(offlineRefHexOf(old), isNull);
      }
      expect(offlineRefOf(null), isNull);
    });

    test('the timestamp is still in there, so an id remains readable', () {
      final at = DateTime.utc(2026, 9, 28, 20);
      expect(
        newOfflineLocalId(now: at),
        startsWith('${offlineIdPrefix}${at.millisecondsSinceEpoch}_'),
      );
    });
  });

  group('the queue remembers who reported', () {
    late SqliteService sqlite;

    setUp(() async {
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, 'rainbow_offline.db'));
      sqlite = SqliteService();
    });

    Future<Map<String, dynamic>> enqueue({
      required String localId,
      String? reportedBy = 'citizen-uuid',
      bool anonymous = false,
    }) async {
      await sqlite.enqueueAlert(
        localId: localId,
        type: 'Kidnap - Held Hostage',
        description: 'x',
        lat: 9.9,
        lng: 8.9,
        priority: 'CRITICAL',
        isAnonymous: anonymous,
        createdAt: DateTime.utc(2026, 9, 28, 14).toIso8601String(),
        reportedBy: reportedBy,
      );
      final rows = await sqlite.getPendingAlerts();
      return rows.firstWhere((r) => r['local_id'] == localId);
    }

    test('and hands it to HQ when the queue is replayed', () async {
      // REGRESSION: the queue had no reporter column, so every alert synced from
      // it reached HQ with reported_by NULL. A dispatcher could not call the
      // reporter back, the reporter could not see their own report under RLS, and
      // the offline-channel dedup — which scopes by reporter — could never match.
      final row = await enqueue(localId: newOfflineLocalId());
      expect(row['reported_by'], 'citizen-uuid');
      expect(
        AlertService.buildOfflineSyncPayload(row)['reported_by'],
        'citizen-uuid',
      );
    });

    test('an anonymous report is not attributed, even locally', () async {
      // Anonymity the device quietly discards is worse than none, because the
      // reporter believes they have it.
      final row = await enqueue(
          localId: newOfflineLocalId(), anonymous: true);
      expect(row['reported_by'], isNull);
      expect(
        AlertService.buildOfflineSyncPayload(row).containsKey('reported_by'),
        isFalse,
      );
    });

    test('a row queued by an older build syncs without a reporter, not with a '
        'wrong one', () async {
      final row = await enqueue(localId: newOfflineLocalId(), reportedBy: null);
      expect(
        AlertService.buildOfflineSyncPayload(row).containsKey('reported_by'),
        isFalse,
      );
    });
  });

  group('replaying the queue after an offline channel already delivered', () {
    late SqliteService sqlite;
    late AlertService service;

    setUp(() async {
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, 'rainbow_offline.db'));
      sqlite = SqliteService();
      service = AlertService(sqlite);
    });

    Future<String> queueOne() async {
      final localId = newOfflineLocalId();
      await sqlite.enqueueAlert(
        localId: localId,
        type: 'Kidnap - Held Hostage',
        description: 'x',
        lat: 9.9,
        lng: 8.9,
        priority: 'CRITICAL',
        isAnonymous: false,
        createdAt: DateTime.utc(2026, 9, 28, 14).toIso8601String(),
        reportedBy: 'citizen-uuid',
      );
      return localId;
    }

    test('it is not filed a second time', () async {
      // The SMS arrived while the phone had no data; now data is back and the
      // queue would insert the same emergency again.
      final localId = await queueOne();
      var askedFor = '';
      AlertService.alreadyDeliveredOverride = (tag) async {
        askedFor = tag;
        return 'already-at-hq';
      };

      final mappings = await service.flushOfflineQueue();

      expect(askedFor, offlineRefHexOf(localId),
          reason: 'it looks for the tag, which is what HQ stored');
      expect(mappings[localId], 'already-at-hq');
      // Nothing was inserted: there is no Supabase here, so an insert would have
      // thrown and the row would have been marked FAILED instead of synced.
      final pending = await sqlite.getPendingAlerts();
      expect(pending.where((r) => r['local_id'] == localId), isEmpty,
          reason: 'the queue considers it delivered');
    });

    test('but it IS filed when nothing has arrived', () async {
      // And the report survives the attempt: with no Supabase the insert throws,
      // and a queued alert is an unsent emergency that must stay queued.
      final localId = await queueOne();
      AlertService.alreadyDeliveredOverride = (tag) async => null;

      final mappings = await service.flushOfflineQueue();

      expect(mappings, isEmpty);
      final pending = await sqlite.getPendingAlerts();
      expect(pending.map((r) => r['local_id']), contains(localId),
          reason: 'still in the queue, marked FAILED, to be retried');
    });

    test('a lookup failure files the report rather than risking losing it',
        () async {
      // Fails towards DELIVERING. A duplicate incident is visible to a dispatcher
      // and can be merged; a report dropped because a bookkeeping lookup failed
      // is visible to nobody.
      final localId = await queueOne();
      AlertService.alreadyDeliveredOverride =
          (tag) async => throw StateError('network gone again');

      await service.flushOfflineQueue();
      final pending = await sqlite.getPendingAlerts();
      expect(pending.map((r) => r['local_id']), contains(localId));
    });
  });

  group('two flushes racing each other', () {
    // The queue is flushed from four places and awaited by none of them:
    // start-up, app resume, the home screen's initState, and connectivity
    // returning — and connectivity is listened to TWICE, in main.dart and
    // again in home_screen.dart. When the network comes back, two flushes
    // start together, over a backlog that exists precisely then.
    late SqliteService sqlite;

    setUp(() async {
      final dir = await databaseFactory.getDatabasesPath();
      await databaseFactory.deleteDatabase(p.join(dir, 'rainbow_offline.db'));
      sqlite = SqliteService();
      AlertService.resetFlushGuard();
    });

    test('a queued report is considered once, not once per flush', () async {
      final localId = newOfflineLocalId();
      await sqlite.enqueueAlert(
        localId: localId,
        type: 'Kidnap - Held Hostage',
        description: 'x',
        lat: 9.9,
        lng: 8.9,
        priority: 'CRITICAL',
        isAnonymous: false,
        createdAt: DateTime.utc(2026, 9, 28, 14).toIso8601String(),
        reportedBy: 'citizen-uuid',
      );

      // Counting the delivery lookups counts the times the row was taken up for
      // sending. Without a guard this is 2, and in production that is two
      // incidents for one emergency and two sets of units sent to one place.
      var considered = 0;
      AlertService.alreadyDeliveredOverride = (tag) async {
        considered += 1;
        // Long enough that the second flush starts while the first is still
        // inside the row, which is the race being reproduced.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return 'already-at-hq';
      };

      // The two listeners do not share an instance: main.dart builds its own
      // AlertService, the home screen goes through the provider. A guard held
      // on the instance would not have helped.
      final a = AlertService(sqlite).flushOfflineQueue();
      final b = AlertService(SqliteService()).flushOfflineQueue();
      await Future.wait([a, b]);

      expect(considered, 1);
    });

    test('the second caller still gets the result', () async {
      // Joining a flush already running must not mean being told nothing
      // happened — the caller cannot tell the difference between that and an
      // empty queue.
      final localId = newOfflineLocalId();
      await sqlite.enqueueAlert(
        localId: localId,
        type: 'Kidnap - Held Hostage',
        description: 'x',
        lat: 9.9,
        lng: 8.9,
        priority: 'CRITICAL',
        isAnonymous: false,
        createdAt: DateTime.utc(2026, 9, 28, 14).toIso8601String(),
        reportedBy: 'citizen-uuid',
      );
      AlertService.alreadyDeliveredOverride = (tag) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return 'already-at-hq';
      };

      final a = AlertService(sqlite).flushOfflineQueue();
      final b = AlertService(SqliteService()).flushOfflineQueue();
      final results = await Future.wait([a, b]);

      expect(results[0][localId], 'already-at-hq');
      expect(results[1][localId], 'already-at-hq');
    });

    test('a later flush is a real flush, not the old one again', () async {
      // The guard must last exactly as long as the flush. If it outlived it,
      // reports queued afterwards would never be sent.
      AlertService.alreadyDeliveredOverride = (tag) async => 'already-at-hq';
      await AlertService(sqlite).flushOfflineQueue();

      final localId = newOfflineLocalId();
      await sqlite.enqueueAlert(
        localId: localId,
        type: 'Kidnap - Held Hostage',
        description: 'x',
        lat: 9.9,
        lng: 8.9,
        priority: 'CRITICAL',
        isAnonymous: false,
        createdAt: DateTime.utc(2026, 9, 28, 14).toIso8601String(),
        reportedBy: 'citizen-uuid',
      );

      final mappings = await AlertService(sqlite).flushOfflineQueue();
      expect(mappings[localId], 'already-at-hq');
    });
  });
}
