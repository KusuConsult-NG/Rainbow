import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/offline/offline_escalation.dart';
import 'package:rainbow_app/core/offline/offline_ref.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/voice_note_service.dart';
import 'package:rainbow_app/services/cloudinary_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/mesh_service.dart';
import 'package:rainbow_app/core/geo/jurisdiction_resolver.dart';
import 'package:rainbow_app/services/sqlite_service.dart';

/// Documentation for this public member.

final alertServiceProvider = Provider<AlertService>((ref) {
  return AlertService(ref.read(sqliteServiceProvider));
});

/// Handles synchronization of Alert and Incident Report data
/// between the local client and the Supabase `alerts` table.
class AlertService {
  /// Documentation for this public member.
  AlertService([SqliteService? sqliteService])
      : _sqliteService = sqliteService ?? SqliteService();

  final SqliteService _sqliteService;

  /// Submits an emergency SOS or incident alert to Supabase.
  Future<String?> submitAlert({
    required String type,
    required String description,
    required String reportedBy,
    double? latitude,
    double? longitude,
    bool isCritical = false,
    AlertPriority priority = AlertPriority.medium,
    List<String>? attachments,
    /// The reporter's own voice, when they could not or did not type.
    ///
    /// Separate from `attachments` on purpose: that list is evidence and this
    /// is the report. It lands in `alerts.voice_note_url`, so a responder's
    /// card can say "the reporter left a voice note" instead of counting it
    /// among the photographs — which is what happened while the recording was
    /// uploaded as one more attachment.
    VoiceNote? voiceNote,
    String? geoLga,
    String? geoWard,
    String? geoSiecWard,
    String? geoPu,
    String syncStatus = 'COMPLETED',
  }) async {
    /// `isCritical` was a parameter that did nothing.
    ///
    /// It was declared, callers set it, and the body never read it — so
    /// `startEmergency()`, which passes `isCritical: true` and no `priority`,
    /// filed every PANIC SOS at the default: MEDIUM. The most urgent thing a
    /// citizen can do arrived on the HQ board graded medium, below a report of
    /// a blocked drain, and outside the CRITICAL filter entirely.
    ///
    /// Caught by pressing the button and reading the row that came out
    /// (`severity: MEDIUM`), not by reading the code — the parameter is right
    /// there in the call and looks like it works.
    final effectivePriority = isCritical ? AlertPriority.critical : priority;

    // Coordinates stay NULL when there is no real fix.
    //
    // This previously defaulted to (9.9167, 8.8917) — the centre of Jos — so an
    // SOS raised where the GPS could not get a lock reached the command
    // dashboard as a confident pin, indistinguishable from a real position, and
    // responders were dispatched to a location produced by a `??` operator.
    // A missing location must read as missing. See E2E_AUDIT_REPORT.md C-5.
    var finalLat = latitude;
    var finalLng = longitude;

    try {
      if (finalLat == null || finalLng == null) {
        final pos = await LocationService().getCurrentPosition(force: true);
        if (pos != null) {
          finalLat = pos.latitude;
          finalLng = pos.longitude;
        }
      }
    } catch (e) {
      debugPrint('[SYS_ERR] AlertService: Error resolving location: $e');
    }

    if (finalLat == null || finalLng == null) {
      debugPrint(
        '[ALERT_SERVICE] No GPS fix for $type alert — submitting WITHOUT '
        'coordinates. HQ surfaces these in the unlocated-alerts panel; '
        'jurisdiction (geo_lga/geo_ward/geo_pu) is still attached.',
      );
    }

    // ── Which jurisdiction owns this incident ───────────────────────────
    //
    // The command chain starts at the tier responsible for the GROUND the
    // incident happened on, so an alert has to carry that ground. Nothing
    // attached it: a citizen report carried no geography at all unless the
    // reporter opened the manual override, and the panic SOS carried the
    // reporter's REGISTERED lga/ward — where they live, not where they are.
    // Every tier filter then fell through its `IS NULL` fail-open and showed
    // every alert to everybody, so the routing existed but never ran.
    //
    // Order of preference, most trustworthy first:
    //   1. what the caller passed  — a manual override by the reporter
    //   2. the coordinates          — measured, and the point of all this
    //   3. nothing                  — unresolved is a real answer
    //
    // The reporter's profile is deliberately NOT a fallback here. Filing an
    // incident against the address someone registered at is how a report from
    // Mangu is routed to a unit in Jos, and it would be indistinguishable
    // afterwards from a measured position. C-5 was this mistake with
    // coordinates; this is the same mistake with jurisdiction.
    var finalLga = geoLga;
    var finalWard = geoWard;
    final finalPu = geoPu;

    if (finalLga == null || finalWard == null) {
      try {
        await JurisdictionResolver.instance.ensureLoaded();
        final j = JurisdictionResolver.instance.resolve(finalLat, finalLng);
        if (j.isResolved) {
          finalLga ??= j.lga;
          finalWard ??= j.ward;
          debugPrint('[ALERT_SERVICE] jurisdiction from GPS: $j');
        } else {
          debugPrint(
            '[ALERT_SERVICE] coordinates did not resolve to a Plateau LGA — '
            'submitting without jurisdiction rather than guessing one.',
          );
        }
      } catch (e) {
        debugPrint('[ALERT_SERVICE] jurisdiction lookup failed: $e');
      }
    }

    // There is no polling unit from coordinates, and there cannot be: no open
    // dataset gives polling units a position. A PU arrives only when the
    // reporter picks one.

    final localId = newOfflineLocalId();
    // ^ `OFFLINE_<millis>_<12 hex>`. Two things are load-bearing:
    //
    //   * the PREFIX, because `wasQueuedOffline` below is how a caller tells a
    //     report that reached the database from one sitting in the local queue,
    //     and the screens use it to decide what to tell the person;
    //   * the TAG, because it is the only identity this report has across the
    //     three ways it can reach HQ. It used to be `OFFLINE_<millis>` alone,
    //     and HQ's dedup — `local_id LIKE '%<hex>%'` — could therefore never
    //     match anything, so one emergency arriving by SMS and by queue would
    //     have become two incidents and two dispatches. See
    //     lib/core/offline/offline_ref.dart.

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isOffline = connectivityResult.contains(ConnectivityResult.none);

      if (isOffline) {
        await _sqliteService.enqueueAlert(
          localId: localId,
          type: type,
          description: description,
          lat: finalLat,
          lng: finalLng,
          priority: effectivePriority.name.toUpperCase(),
          isAnonymous: false,
          createdAt: DateTime.now().toIso8601String(),
          reportedBy: reportedBy,
        );

        if (attachments != null) {
          for (final path in attachments) {
            await _sqliteService.enqueueMedia(
              localAlertId: localId,
              localFilePath: path,
            );
          }
        }

        // The radio says there is no data path. Try the ones that do not need
        // one — SMS if there is cell signal and this is urgent enough to spend a
        // message on, and the mesh, which costs nothing.
        await _escalateOffline(
          localId: localId,
          type: type,
          severity: effectivePriority.name.toUpperCase(),
          latitude: finalLat,
          longitude: finalLng,
        );

        await BackgroundTrackingService().startSosTracking(localId, reportedBy);
        return localId;
      }

      final mediaUrls = <String>[];
      if (attachments != null && attachments.isNotEmpty) {
        for (final filePath in attachments) {
          try {
            final file = File(filePath);
            if (file.existsSync()) {
              // 1. Cost-optimized Cloudinary Upload (Free 25GB Storage + Transcoding)
              final cloudinaryUrl = await CloudinaryService.instance.uploadMedia(file);
              if (cloudinaryUrl != null) {
                mediaUrls.add(cloudinaryUrl);
                continue;
              }

              // 2. Supabase Storage Fallback
              final bytes = await file.readAsBytes();
              final ext = filePath.split('.').last;
              final fileName = '${DateTime.now().millisecondsSinceEpoch}_${localId.length > 5 ? localId.substring(0, 5) : localId}.$ext';
              final storagePath = 'incident_media/$fileName';
              await SupabaseConfig.client.storage
                  .from('incident-media')
                  .uploadBinary(storagePath, bytes);
              final publicUrl = SupabaseConfig.client.storage
                  .from('incident-media')
                  .getPublicUrl(storagePath);
              mediaUrls.add(publicUrl);
            } else if (filePath.startsWith('http')) {
              mediaUrls.add(filePath);
            }
          } catch (e) {
            debugPrint('[ALERT_SERVICE] Media upload fallback for $filePath: $e');
            if (filePath.startsWith('http')) {
              mediaUrls.add(filePath);
            }
          }
        }
      }

      // THE VOICE NOTE IS UPLOADED LAST AND ON ITS OWN.
      //
      // Through the same two-step path as the evidence (Cloudinary, then
      // Supabase storage) because the fallback is the reason either one
      // arrives. A failure here must not take the report with it: somebody who
      // could not type has also said something in the description or the
      // transcript, and an incident filed without its audio beats no incident.
      String? voiceNoteUrl;
      if (voiceNote != null) {
        try {
          final file = File(voiceNote.path);
          if (file.existsSync()) {
            voiceNoteUrl = await CloudinaryService.instance.uploadMedia(file);
            if (voiceNoteUrl == null) {
              final bytes = await file.readAsBytes();
              final storagePath =
                  'incident_media/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
              await SupabaseConfig.client.storage
                  .from('incident-media')
                  .uploadBinary(storagePath, bytes);
              voiceNoteUrl = SupabaseConfig.client.storage
                  .from('incident-media')
                  .getPublicUrl(storagePath);
            }
          } else if (voiceNote.path.startsWith('http')) {
            voiceNoteUrl = voiceNote.path;
          }
        } catch (e) {
          debugPrint('[ALERT_SERVICE] the voice note did not upload: $e');
        }
      }

      final alertPayload = <String, dynamic>{
        'local_id': localId,
        'type': type,
        'description': description,
        'reported_by': reportedBy,
        // `'reportedBy': reportedBy` used to sit here too — a camelCase twin of
        // the line above, and not a column. PostgREST rejects an insert naming
        // an unknown column IN FULL, so EVERY alert this app submitted was
        // refused: every SOS, every incident report.
        //
        // It was invisible because the failure path is a fallback, not an
        // error: the catch below enqueues the alert into offline SQLite, and
        // the UI says the report was sent. It looked like an app that worked
        // offline. It was an app that was always offline.
        //
        // The drift gate missed it too — its Dart key pattern was
        // `[a-z_][a-z0-9_]*` with no IGNORECASE, so a camelCase key did not
        // match and was skipped in silence. Fixed in check_schema_drift.py.
        'latitude': finalLat,
        'longitude': finalLng,
        'status': 'PENDING',
        'severity': effectivePriority.name.toUpperCase(),
        'geo_lga': finalLga,
        'geo_ward': finalWard,
        'geo_siec_ward': geoSiecWard,
        'geo_pu': finalPu,
        'media_urls': mediaUrls,
        // Only when there is one: writing nulls would overwrite nothing here
        // (this is an insert) but it keeps the payload honest about what the
        // report actually carries.
        if (voiceNoteUrl != null) 'voice_note_url': voiceNoteUrl,
        if (voiceNoteUrl != null) 'voice_note_seconds': voiceNote!.seconds,
      };

      try {
        final response = await SupabaseConfig.client
            .from('alerts')
            .insert(alertPayload)
            .select('id')
            .maybeSingle();

        final alertId = response?['id'] as String? ?? localId;
        await BackgroundTrackingService().startSosTracking(alertId, reportedBy);
        return alertId;
      } catch (e) {
        debugPrint(
          '[ALERT_SERVICE] Direct insert failed ($e) — saving to offline SQLite queue.',
        );
        await _sqliteService.enqueueAlert(
          localId: localId,
          type: type,
          description: description,
          lat: finalLat,
          lng: finalLng,
          priority: effectivePriority.name.toUpperCase(),
          isAnonymous: false,
          createdAt: DateTime.now().toIso8601String(),
          reportedBy: reportedBy,
        );

        if (attachments != null) {
          for (final path in attachments) {
            await _sqliteService.enqueueMedia(
              localAlertId: localId,
              localFilePath: path,
            );
          }
        }

        // This branch matters MORE than the no-radio one above, and it is the
        // one a connectivity check cannot see. The radio said connected and the
        // insert was still refused: a captive portal, a congested tower that
        // carries a text but not a TLS handshake, an expired token, an RLS
        // refusal, a column the schema lacks, HQ simply down. The report reached
        // nobody, so the offline channels are exactly as necessary here.
        await _escalateOffline(
          localId: localId,
          type: type,
          severity: effectivePriority.name.toUpperCase(),
          latitude: finalLat,
          longitude: finalLng,
        );

        await BackgroundTrackingService().startSosTracking(localId, reportedBy);
        return localId;
      }
    } catch (e) {
      debugPrint('[CRITICAL_SERVICE_ERR] AlertService Submission Failed: $e');
      return localId;
    }
  }

  /// Test seam: the offline channels, so the send path can be tested without a
  /// SIM, a keystore or a radio.
  @visibleForTesting
  static Future<OfflineEscalationReport> Function({
    required String localId,
    required String type,
    required String severity,
    double? latitude,
    double? longitude,
  })? escalateOverride;

  Future<void> _escalateOffline({
    required String localId,
    required String type,
    required String severity,
    double? latitude,
    double? longitude,
  }) async {
    try {
      if (escalateOverride != null) {
        await escalateOverride!(
          localId: localId,
          type: type,
          severity: severity,
          latitude: latitude,
          longitude: longitude,
        );
        return;
      }
      // The Bluetooth mesh is offered when this phone can use it without asking
      // for anything mid-emergency; otherwise `mesh` is null and this is the
      // SMS path only. See MeshService.nodeForEmergency.
      final mesh = await MeshService.instance.nodeForEmergency();
      await OfflineEscalation(mesh: mesh).escalate(
        localId: localId,
        type: type,
        severity: severity,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      // The report is already in the queue. This was the attempt to do better.
      debugPrint('[ALERT_SERVICE] offline escalation failed: $e');
    }
  }

  /// Did this submission end up in the local queue rather than the database?
  ///
  /// `submitAlert` returns a real uuid when the insert succeeded and an
  /// `OFFLINE_…` id when it fell back to SQLite, so the answer is already in
  /// the value every caller receives.
  ///
  /// WHY THIS EXISTS RATHER THAN A CONNECTIVITY CHECK.
  ///
  /// The report screen decided what to tell the user from
  /// `connectivityResult.contains(ConnectivityResult.none)` — a reading of the
  /// RADIO, taken BEFORE the submit. That answers "does this phone have a
  /// network interface up", which is not the question. The question is "did the
  /// report arrive", and the two come apart in every case that matters: a
  /// captive portal, DNS failure, an expired token, a row-level-security
  /// refusal, a column the schema does not have, or the backend simply being
  /// down. In all of those the radio says connected, the insert fails, the
  /// alert goes to the local queue — and the person was shown a green REPORT
  /// TRANSMITTED with a shield on it.
  ///
  /// That is precisely the failure mode that hid `alerts.reportedBy` for
  /// months: an insert the database refused looked exactly like one that
  /// succeeded, because the offline queue caught it and the screen was reading
  /// the radio instead of the outcome.
  static bool wasQueuedOffline(String? alertId) =>
      alertId != null &&
      (alertId.startsWith('OFFLINE_') || alertId.startsWith('LOCAL_'));

  /// Builds the Supabase `alerts` payload for one row of the local offline queue.
  ///
  /// Extracted as a pure function so the offline SOS replay path can be tested
  /// without a network or a Supabase session — see `test/offline_queue_test.dart`.
  ///
  /// REGRESSION GUARD: this previously read `row['latitude']` and
  /// `row['longitude']`, but the SQLite schema stores those columns as `lat` and
  /// `lng` (see SqliteService._initDb and enqueueAlert). Both lookups therefore
  /// returned null, and **every alert queued while offline reached HQ with no
  /// coordinates** — in exactly the no-signal scenario the offline queue exists
  /// to serve.
  ///
  /// `created_at` is carried across from the queue rather than defaulting to
  /// NOW() at insert time, so an incident raised at 14:00 and synced at 18:00 is
  /// recorded at 14:00.
  static Map<String, dynamic> buildOfflineSyncPayload(
    Map<String, dynamic> row,
  ) {
    return <String, dynamic>{
      'local_id': row['local_id'],
      'type': row['type'],
      'description': row['description'],
      'latitude': row['lat'],
      'longitude': row['lng'],
      'severity': row['priority'],
      'status': 'PENDING',
      if (row['created_at'] != null) 'created_at': row['created_at'],
      // REGRESSION GUARD: this key was absent, so every alert synced from the
      // offline queue reached HQ with `reported_by` NULL. A dispatcher could not
      // call the reporter back, the reporter could not see their own report
      // under RLS, and the offline-channel dedup — which scopes by reporter —
      // could never match it. Null here now means one thing only: the report was
      // filed anonymously, or it was queued by a build older than v3 of the
      // local database.
      if (row['reported_by'] != null) 'reported_by': row['reported_by'],
    };
  }

  /// Test seam: the "has this already arrived?" lookup, so the flush can be
  /// tested without Supabase.
  @visibleForTesting
  static Future<String?> Function(String tagHex)? alreadyDeliveredOverride;

  /// The id of an alert already carrying this report's tag, or null.
  Future<String?> _findAlreadyDelivered(String localId) async {
    final tag = offlineRefHexOf(localId);
    if (tag == null) return null;
    try {
      if (alreadyDeliveredOverride != null) {
        return await alreadyDeliveredOverride!(tag);
      }
      final rows = await SupabaseConfig.client
          .from('alerts')
          .select('id')
          .like('local_id', '%$tag%')
          .limit(1);
      if (rows.isEmpty) return null;
      return rows.first['id'] as String?;
    } catch (e) {
      // Fail towards DELIVERING. A duplicate incident is visible to a dispatcher
      // and can be merged; a report dropped because a dedup lookup failed is
      // visible to nobody.
      debugPrint('[SYNC] dedup lookup failed ($e) — filing the report anyway');
      return null;
    }
  }

  /// Replays pending alerts once connectivity is restored.
  /// The flush currently running, if any. Static because the callers do not
  /// share an instance: `main.dart` constructs its own `AlertService()` while
  /// the home screen goes through `alertServiceProvider`.
  static Future<Map<String, String>>? _flushInFlight;

  /// Drops the guard between tests.
  @visibleForTesting
  static void resetFlushGuard() => _flushInFlight = null;

  /// Sends everything waiting in the local queue, one flush at a time.
  ///
  /// ## Why the guard is the whole point
  ///
  /// Four call sites fire this and none of them awaits it: start-up, app
  /// resume, the home screen's initState, and connectivity returning — and
  /// connectivity is listened to TWICE, in `main.dart` and again in
  /// `home_screen.dart`. So the moment the network comes back, two flushes
  /// start together. That is also the exact moment a backlog exists.
  ///
  /// Both would call `getPendingAlerts()` and get the same rows, both would
  /// miss the already-delivered check because neither had inserted yet, and
  /// both would insert. Five queued emergencies become ten incidents and up to
  /// five pairs of units sent to one place. The de-duplication below is aimed
  /// at the same report arriving over DIFFERENT channels; it cannot see a
  /// second copy of itself racing it through the same one.
  ///
  /// A later caller joins the flush already running rather than starting a
  /// second one, and gets its result.
  Future<Map<String, String>> flushOfflineQueue() {
    final running = _flushInFlight;
    if (running != null) return running;

    final started = _flushOfflineQueueOnce()
        .whenComplete(() => _flushInFlight = null);
    _flushInFlight = started;
    return started;
  }

  Future<Map<String, String>> _flushOfflineQueueOnce() async {
    final mappings = <String, String>{};
    try {
      final offlineQueue = await _sqliteService.getPendingAlerts();
      if (offlineQueue.isEmpty) return mappings;

      debugPrint('[SYNC] Recovering ${offlineQueue.length} offline alerts...');
      for (final row in offlineQueue) {
        final localId = row['local_id'] as String;
        try {
          // Did this report already reach HQ by SMS or through the mesh while
          // the phone had no data? If so, inserting it again means two incidents
          // and two units sent to one place.
          //
          // HQ records an offline-channel alert with `local_id` set to the
          // twelve-hex tag, and the queued id ends with that same tag, so one
          // LIKE finds it. The anonymous case cannot be deduplicated this way and
          // is not meant to be: an anonymous report is deliberately not linked to
          // its reporter, so this phone cannot prove the row is its own.
          final alreadyThere = await _findAlreadyDelivered(localId);
          if (alreadyThere != null) {
            debugPrint(
              '[SYNC] $localId already reached HQ over an offline channel — '
              'marking synced instead of filing it twice.',
            );
            mappings[localId] = alreadyThere;
            await _sqliteService.markAlertSynced(localId);
            continue;
          }

          final payload = buildOfflineSyncPayload(row);

          final response = await SupabaseConfig.client
              .from('alerts')
              .insert(payload)
              .select()
              .single();

          final alertId = response['id'] as String?;
          if (alertId != null) {
            mappings[localId] = alertId;
            await _sqliteService.markAlertSynced(localId);
          }
        } catch (e) {
          debugPrint('[SYNC_ERR] Alert sync failed for $localId: $e');
          await _sqliteService.updateSyncStatus(localId, 'FAILED');
        }
      }
    } catch (e) {
      debugPrint('[SYNC_ERR] Flush offline queue failed: $e');
    }
    return mappings;
  }
}
