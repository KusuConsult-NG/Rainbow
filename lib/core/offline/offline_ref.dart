/// The one identity that follows a report across all three ways out.
///
/// ## The problem this fixes
///
/// A report raised with no data can reach HQ three ways, and often reaches it
/// more than once:
///
/// 1. by **SMS**, within seconds, if there is cell signal;
/// 2. through the **mesh**, minutes later, via whichever phone found a network;
/// 3. from the phone's own **offline queue**, when its data comes back.
///
/// Those are three deliveries of ONE emergency. Recording three incidents means
/// three units dispatched to one place while the next call waits, so HQ
/// deduplicates on `alerts.local_id`, and both offline channels carry six bytes
/// of it. That was the design, and it could not work as built: the SMS payload
/// carries six arbitrary bytes, HQ matches them with
/// `local_id LIKE '%<hex>%'`, and the queue's id was
/// `OFFLINE_<milliseconds>` — a string those bytes do not appear in, in any
/// encoding. So every dedup check would have missed, silently, and each channel
/// would have produced its own incident.
///
/// Found while wiring the channels into the app, which is the first time
/// anything held both ends at once.
///
/// ## The fix: put the tag in the id
///
/// ```
///   OFFLINE_1790500000000_a1b2c3d4e5f6
///           └ when              └ the tag: 6 random bytes, 12 hex characters
/// ```
///
/// The tag is what travels. HQ's `LIKE '%a1b2c3d4e5f6%'` now matches the row the
/// queue will eventually insert, and the queue's own flush looks for a row
/// already carrying the tag before inserting another. Both orders are covered,
/// which matters because in the field the SMS usually wins and the design
/// assumed the queue would.
///
/// ## Why random rather than the timestamp
///
/// Six bytes of a millisecond timestamp are nearly all the same byte across a
/// whole day, so a truncated one would collide constantly — and a dedup
/// collision is not a duplicate, it is a DROPPED emergency: HQ would decide the
/// second incident was already recorded. Random six bytes is 48 bits, and HQ
/// deduplicates within a window rather than for all time.
library;

import 'dart:math';
import 'dart:typed_data';

/// How many bytes of identity travel over the offline channels.
const int offlineRefLength = 6;

/// The prefix every locally-queued id carries.
///
/// Load-bearing: `AlertService.wasQueuedOffline` is how a screen tells a report
/// that reached the database from one sitting in the local queue.
const String offlineIdPrefix = 'OFFLINE_';

/// Mints an id for a report that could not be sent.
///
/// [random] is injectable for tests only; production uses the platform CSPRNG.
/// It is not a secret — it identifies one report to HQ — but it must not be
/// guessable either, because anybody who could predict it could pre-empt a real
/// report's dedup and have HQ discard it.
String newOfflineLocalId({DateTime? now, Random? random}) {
  final rng = random ?? Random.secure();
  final tag = List<int>.generate(offlineRefLength, (_) => rng.nextInt(256));
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return '$offlineIdPrefix${at}_${_hex(tag)}';
}

/// Whether [alertId] is an id the DATABASE issued, rather than a local one.
///
/// ONE answer to this question, beside the function that mints the other kind.
/// There were two, and they did not agree about what they were testing:
///
///   background_tracking_service.dart  a UUID regex
///   emergency_provider.dart           !startsWith('LOCAL_') &&
///                                     !startsWith('OFFLINE_')
///
/// `scripts/check_a_tracked_sos_reaches_the_map.py` was written for T-7x and
/// says, in its own words, that the predicate must match "a UUID rather than,
/// say, rejecting a prefix — a `!startsWith('OFFLINE_')` check would pass any
/// other junk". It checks the tracking service. The prefix version survived one
/// file away, in the code that decides whether the dispatcher channel opens for
/// a citizen in an emergency.
///
/// Today both reachable values — a server uuid, or an id from
/// [newOfflineLocalId] — are classified the same way by either test, so nothing
/// visible depended on it. That is a reason it went unnoticed, not a reason to
/// keep two. `telemetry.alert_id` and `incident_tracks.alert_id` are UUID
/// columns and PostgreSQL rejects anything else at the TYPE, before the foreign
/// key: `22P02 invalid input syntax for type uuid`. A predicate that answers
/// "not obviously local" when the column asks "is this a uuid" is one sentinel
/// away from losing a live route again. See E2E_AUDIT_REPORT.md T-7x and T-86.
bool isServerAlertId(String? alertId) {
  if (alertId == null) return false;
  return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
                r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(alertId);
}

/// Reads the six-byte tag out of a local id, or null if it has none.
///
/// Null for the ids minted before this existed, and for a real database uuid.
/// A caller that gets null must not invent a tag: sending an alert whose tag
/// matches nothing is how a duplicate gets through, and sending one whose tag
/// matches something else is how a real alert gets dropped.
Uint8List? offlineRefOf(String? localId) {
  if (localId == null) return null;
  final match =
      RegExp('_([0-9a-f]{${offlineRefLength * 2}})\$').firstMatch(localId);
  if (match == null) return null;
  final hex = match.group(1)!;
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// The tag as HQ stores and matches it.
String? offlineRefHexOf(String? localId) {
  final ref = offlineRefOf(localId);
  return ref == null ? null : _hex(ref);
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
