import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/providers/alerts_feed.dart';

/// The responder's mission feed used to be a bare `.stream()`, so a WebSocket
/// that never connected produced an empty list — and an empty list renders as
/// "ALL CLEAR — NO ACTIVE MISSIONS". These tests exist to make that specific
/// lie impossible: whenever the feed is not live, it must say so, and it must
/// not throw away rows it already has.
void main() {
  final rows = [
    {'id': 'a1', 'status': 'ACTIVE', 'category': 'SECURITY'},
    {'id': 'a2', 'status': 'DISPATCHED', 'category': 'MEDICAL'},
  ];

  group('resilientAlertsFeed', () {
    test('shows alerts from REST even when realtime never connects', () async {
      final seen = <AlertsFeed>[];
      final sub = resilientAlertsFeed(
        fetch: () async => rows,
        // A channel that opens and then says nothing: exactly what a proxy
        // that passes HTTPS but silently drops `wss` looks like.
        watch: () => const Stream<List<Map<String, dynamic>>>.empty()
            .asBroadcastStream()
            .where((_) => false),
        realtimeGrace: const Duration(milliseconds: 60),
        pollInterval: const Duration(milliseconds: 200),
      ).listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await sub.cancel();

      final last = seen.last;
      expect(last.rows.length, 2,
          reason: 'REST rows must survive a dead realtime channel');
      expect(last.liveness, FeedLiveness.degraded,
          reason: 'the feed must not claim to be live when it is not');
    });

    test('never reports ALL CLEAR territory: liveness is degraded, not live, '
        'when the fetch also fails', () async {
      final seen = <AlertsFeed>[];
      final sub = resilientAlertsFeed(
        fetch: () async => throw Exception('SocketException: no route to host'),
        watch: () => Stream<List<Map<String, dynamic>>>.error(
            Exception('WebSocket refused')),
        realtimeGrace: const Duration(milliseconds: 60),
        pollInterval: const Duration(milliseconds: 200),
      ).listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(seen.last.liveness, FeedLiveness.degraded);
      expect(seen.last.rows, isEmpty);
      expect(seen.last.error, isNotNull,
          reason: 'the UI needs a reason to show, not just a blank screen');
      // The distinction the whole change exists for.
      expect(seen.any((f) => f.liveness == FeedLiveness.live), isFalse);
    });

    test('reports live once realtime delivers', () async {
      final ctrl = StreamController<List<Map<String, dynamic>>>();
      final seen = <AlertsFeed>[];
      final sub = resilientAlertsFeed(
        fetch: () async => <Map<String, dynamic>>[],
        watch: () => ctrl.stream,
        realtimeGrace: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 200),
      ).listen(seen.add);

      ctrl.add(rows);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(seen.last.liveness, FeedLiveness.live);
      expect(seen.last.rows.length, 2);
      expect(seen.last.error, isNull);

      await sub.cancel();
      await ctrl.close();
    });

    test('keeps the rows it already had when a later refresh fails', () async {
      var callCount = 0;
      final seen = <AlertsFeed>[];
      final sub = resilientAlertsFeed(
        fetch: () async {
          callCount++;
          if (callCount == 1) return rows;
          throw Exception('connection reset');
        },
        watch: () => const Stream<List<Map<String, dynamic>>>.empty()
            .asBroadcastStream()
            .where((_) => false),
        realtimeGrace: const Duration(milliseconds: 50),
        pollInterval: const Duration(milliseconds: 80),
      ).listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await sub.cancel();

      expect(callCount, greaterThan(1), reason: 'it must keep polling');
      expect(seen.last.rows.length, 2,
          reason: 'a failed refresh must not blank an incident list');
      expect(seen.last.error, isNotNull);
    });

    test('degrades when an established channel later closes', () async {
      final ctrl = StreamController<List<Map<String, dynamic>>>();
      final seen = <AlertsFeed>[];
      final sub = resilientAlertsFeed(
        fetch: () async => rows,
        watch: () => ctrl.stream,
        realtimeGrace: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 100),
      ).listen(seen.add);

      ctrl.add(rows);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen.last.liveness, FeedLiveness.live);

      await ctrl.close(); // the link drops mid-incident
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(seen.last.liveness, FeedLiveness.degraded,
          reason: 'a dropped channel must stop the feed claiming to be live');
      expect(seen.last.rows.length, 2,
          reason: 'and must not empty the list on the way down');

      await sub.cancel();
    });

    test('first emission makes no claim at all', () async {
      final seen = <AlertsFeed>[];
      final sub = resilientAlertsFeed(
        fetch: () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return rows;
        },
        watch: () => const Stream<List<Map<String, dynamic>>>.empty()
            .asBroadcastStream()
            .where((_) => false),
        realtimeGrace: const Duration(seconds: 5),
      ).listen(seen.add);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen.first.liveness, FeedLiveness.connecting,
          reason: 'before anything loads, the feed must not say all clear');

      await sub.cancel();
    });
  });
}
