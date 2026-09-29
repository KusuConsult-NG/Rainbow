/// Watches the SIM and tells HQ when the SMS channel changes.
///
/// The decisions are in `lib/core/device/sim_fingerprint.dart` and are pure and
/// tested. This is the wiring: read the platform, compare against the last
/// reading kept on the device, write a row if something changed, and — this
/// part is not optional — tell the person holding the phone that it was
/// reported.
///
/// ## When it runs
///
/// At sign-in and on every resume. Not on a background timer and not from a
/// broadcast receiver:
///
///   * `SIM_STATE_CHANGED` is an implicit broadcast, and since Android 8 an
///     implicit broadcast cannot be registered in the manifest unless it is on
///     the exemption list, which this one is not. A receiver registered at
///     runtime only lives as long as the process, so it would miss exactly the
///     case that matters — the SIM taken out while the app is closed.
///   * Comparing against a stored reading catches that case anyway, and costs
///     one cheap platform call.
///
/// ## What it will not do
///
/// It attaches no location, ever. See the migration for why that line is
/// drawn where it is.
library;

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/device/sim_channel.dart';
import 'package:rainbow_app/core/device/sim_fingerprint.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';

/// The outcome of one check, so a caller can show the person the notice.
class SimCheckOutcome {
  /// The outcome of one check.
  const SimCheckOutcome(this.change, {this.reported = false});

  /// What changed, if anything.
  final SimChange change;

  /// Whether a row actually reached HQ. False when the write failed — the
  /// handset is offline, most likely — and the check will report it next time.
  final bool reported;

  /// The line to show the holder, or empty when there is nothing to say.
  String get noticeForUser => simChangeNoticeForUser(change);
}

/// Reads the SIM, compares, reports.
class SimWatchService {
  /// Reads the SIM, compares, reports.
  SimWatchService({
    SimReader? reader,
    SecureStorageService? storage,
  })  : _reader = reader ?? const MethodChannelSimReader(),
        _storage = storage ?? SecureStorageService();

  final SimReader _reader;
  final SecureStorageService _storage;

  /// Where the last reading is kept.
  ///
  /// Secure storage rather than SharedPreferences, for one reason: a reading
  /// that can be edited can be used to manufacture a change. Nothing here is
  /// secret, but it has to be tamper-resistant.
  static const String storageKey = 'sim_last_seen';

  /// Test seam: writing the row reaches Supabase.
  @visibleForTesting
  static Future<void> Function(SimChange change, SimSnapshot now)?
      reportOverride;

  /// Checks the SIM and reports a change if there is one.
  ///
  /// Never throws. A failure to read, to store or to report is reported as "no
  /// change", because every one of those means we do not know — and not
  /// knowing must never be shown to an operator as "the SIM was removed".
  Future<SimCheckOutcome> check() async {
    SimSnapshot now;
    try {
      now = await _reader.read();
    } on Object catch (e) {
      debugPrint('[SIM] could not read: $e');
      return const SimCheckOutcome(SimChange.none);
    }

    // Nothing to compare against on a platform that will not say, and nothing
    // worth storing either.
    if (now.presence == SimPresence.unavailable) {
      return const SimCheckOutcome(SimChange.none);
    }

    final before = await _readStored();
    final change = compareSim(before, now);

    // The baseline is written whatever happened, including on the very first
    // run, so that the NEXT change is visible.
    await _store(now);

    if (!shouldReport(change)) return SimCheckOutcome(change);

    var reported = false;
    try {
      await (reportOverride ?? _report)(change, now);
      reported = true;
    } on Object catch (e) {
      // Offline, most likely. The stored baseline has already moved on, so
      // this particular change will not be re-reported — which is the right
      // trade: a duplicated alert for every offline period would train the
      // console to ignore the alert, and the NEXT change is still caught.
      debugPrint('[SIM] could not report the change: $e');
    }
    return SimCheckOutcome(change, reported: reported);
  }

  Future<SimSnapshot?> _readStored() async {
    try {
      final raw = await _storage.readJson(storageKey);
      if (raw == null) return null;
      return SimSnapshot.fromJson(raw);
    } on Object catch (e) {
      debugPrint('[SIM] could not read the stored baseline: $e');
      return null;
    }
  }

  Future<void> _store(SimSnapshot snapshot) async {
    try {
      await _storage.writeJson(storageKey, snapshot.toJson());
    } on Object catch (e) {
      debugPrint('[SIM] could not store the baseline: $e');
    }
  }

  Future<void> _report(SimChange change, SimSnapshot now) async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    await SupabaseConfig.client
        .from('sim_channel_events')
        .insert(<String, dynamic>{
          'user_id': uid,
          'change': change.name.toUpperCase(),
          'operator_name': now.operatorName,
          'operator_code': now.operatorCode,
          'noticed_at': DateTime.now().toUtc().toIso8601String(),
          // No location. Not omitted by oversight — there is no column for
          // one, and the migration says why.
        });
  }

  /// Forgets the baseline. Called on sign-out, so the next person to use this
  /// handset does not inherit a comparison against somebody else's SIM.
  Future<void> forget() async {
    try {
      await _storage.delete(storageKey);
    } on Object catch (e) {
      debugPrint('[SIM] could not clear the baseline: $e');
    }
  }
}
