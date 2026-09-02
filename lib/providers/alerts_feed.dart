import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// How much to trust what the responder is looking at.
enum FeedLiveness {
  /// First load. Nothing has arrived yet and no claim is being made.
  connecting,

  /// The realtime channel is established; new alerts arrive as they are filed.
  live,

  /// Realtime could not be established, or dropped. Rows below come from
  /// periodic fetches and may be up to one poll interval stale.
  degraded,
}

/// One reading of the alert feed, carrying how much it can be trusted.
class AlertsFeed {
  const AlertsFeed({
    required this.rows,
    required this.liveness,
    this.error,
    this.at,
  });

  /// Empty and making no claim — the state before anything has loaded.
  static const AlertsFeed initial = AlertsFeed(
    rows: <Map<String, dynamic>>[],
    liveness: FeedLiveness.connecting,
  );

  /// The alert rows currently known, whatever their provenance.
  final List<Map<String, dynamic>> rows;

  /// How much [rows] can be trusted to be current.
  final FeedLiveness liveness;

  /// Last transport failure, if any. Kept so the UI can say *why* it is
  /// degraded rather than only that it is.
  final String? error;

  /// When [rows] were last refreshed.
  final DateTime? at;

  /// Returns a copy with the given fields replaced.
  AlertsFeed copyWith({
    List<Map<String, dynamic>>? rows,
    FeedLiveness? liveness,
    String? error,
    DateTime? at,
  }) =>
      AlertsFeed(
        rows: rows ?? this.rows,
        liveness: liveness ?? this.liveness,
        error: error,
        at: at ?? this.at,
      );
}

/// The responder's alert feed, built so that losing the realtime channel
/// degrades it instead of emptying it.
///
/// WHY THIS IS NOT JUST `.stream()`.
///
/// The mission feed used to be a bare `client.from('alerts').stream(...)`, read
/// through a `StreamBuilder` that did `snapshot.data ?? []` and never looked at
/// `hasError`. Both failure modes therefore rendered as an empty list, and an
/// empty list renders as **"ALL CLEAR — NO ACTIVE MISSIONS"**.
///
/// So a responder whose device could not open a WebSocket — a rural link, a
/// captive portal, a proxy that passes HTTPS but blocks `wss` — was shown a
/// confident all-clear over a live incident, with nothing on screen to suggest
/// the feed was not working. That is the same defect as a status light wired to
/// always read ONLINE: an instrument that can only report good news.
///
/// This does three things instead:
///
///  1. **Fetches over REST first**, so alerts are on screen before realtime is
///     established at all, and remain on screen if it never is.
///  2. **Falls back to polling** when the channel does not come up within
///     [realtimeGrace], or when it errors or drops later.
///  3. **Reports its own liveness**, so the UI can distinguish "no active
///     missions" from "this feed is not live".
///
/// Takes [fetch] and [watch] as plain functions rather than a [SupabaseClient]
/// so the whole degrade-and-recover path can be driven in a unit test with no
/// Supabase, no network and no device — see `test/alerts_feed_test.dart`.
/// [supabaseAlertsFeed] wires it to the real client.
Stream<AlertsFeed> resilientAlertsFeed({
  required Future<List<Map<String, dynamic>>> Function() fetch,
  required Stream<List<Map<String, dynamic>>> Function() watch,
  Duration realtimeGrace = const Duration(seconds: 6),
  Duration pollInterval = const Duration(seconds: 20),
}) {
  late final StreamController<AlertsFeed> controller;

  var liveness = FeedLiveness.connecting;
  var rows = const <Map<String, dynamic>>[];
  String? lastError;

  Timer? grace;
  Timer? poll;
  StreamSubscription<List<Map<String, dynamic>>>? sub;

  void emit() {
    if (controller.isClosed) return;
    controller.add(AlertsFeed(
      rows: rows,
      liveness: liveness,
      error: lastError,
      at: DateTime.now(),
    ));
  }

  Future<void> fetchOnce() async {
    try {
      rows = await fetch();
      lastError = null;
    } catch (e) {
      // Keep whatever rows we already had. Replacing them with an empty list
      // on a failed refresh is precisely the behaviour being fixed.
      lastError = e.toString();
    }
    emit();
  }

  void degrade(String? why) {
    if (liveness == FeedLiveness.degraded) return;
    liveness = FeedLiveness.degraded;
    lastError = why ?? lastError;
    poll ??= Timer.periodic(pollInterval, (_) => fetchOnce());
    emit();
    // Refresh immediately on degrading rather than waiting a whole interval.
    unawaited(fetchOnce());
  }

  controller = StreamController<AlertsFeed>(
    onListen: () {
      emit(); // connecting, empty — an honest starting state
      unawaited(fetchOnce());

      grace = Timer(realtimeGrace, () {
        if (liveness != FeedLiveness.live) {
          degrade('Realtime channel did not connect.');
        }
      });

      try {
        sub = watch().listen(
          (data) {
            rows = List<Map<String, dynamic>>.from(data);
            liveness = FeedLiveness.live;
            lastError = null;
            poll?.cancel();
            poll = null;
            emit();
          },
          onError: (Object e) => degrade(e.toString()),
          onDone: () => degrade('Realtime channel closed.'),
        );
      } catch (e) {
        degrade(e.toString());
      }
    },
    onCancel: () async {
      grace?.cancel();
      poll?.cancel();
      await sub?.cancel();
    },
  );

  return controller.stream;
}

/// [resilientAlertsFeed] wired to a live Supabase client.
Stream<AlertsFeed> supabaseAlertsFeed(
  SupabaseClient client, {
  String table = 'alerts',
  Duration realtimeGrace = const Duration(seconds: 6),
  Duration pollInterval = const Duration(seconds: 20),
}) =>
    resilientAlertsFeed(
      fetch: () async => List<Map<String, dynamic>>.from(
        await client.from(table).select() as List,
      ),
      watch: () => client.from(table).stream(primaryKey: ['id']),
      realtimeGrace: realtimeGrace,
      pollInterval: pollInterval,
    );
