import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/core/offline/offline_ref.dart';
import 'package:rainbow_app/core/models/emergency_state.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/sos_dispatch_service.dart';

final emergencyProvider =
    NotifierProvider<EmergencyNotifier, EmergencyState>(EmergencyNotifier.new);

class EmergencyNotifier extends Notifier<EmergencyState> {
  @override
  EmergencyState build() => const EmergencyState();

  Future<void> startEmergency() async {
    state = state.copyWith(isEmergencyActive: true, startTime: DateTime.now());

    final auth = ref.read(authProvider);
    final userId = auth.user?.id ?? 'unknown';
    final lga = auth.profile?['geo_lga'] as String?;
    final ward = auth.profile?['geo_ward'] as String?;

    Position? currentPos;
    try {
      currentPos = await LocationService().getCurrentPosition(force: true);
    } catch (_) {}

    final latVal = currentPos?.latitude;
    final lngVal = currentPos?.longitude;

    /// Server-side alert reference to quote in the escalation SMS, or null when
    /// the write failed or was queued offline. Declared out here so the SMS can
    /// be dispatched after the try/catch regardless of which way it went.
    String? dispatchRef;

    try {
      final alertId = await ref.read(alertServiceProvider).submitAlert(
            type: 'PANIC SOS',
            description: 'Public Panic Button Activated',
            reportedBy: userId,
            latitude: latVal,
            longitude: lngVal,
            isCritical: true,
            geoLga: lga,
            geoWard: ward,
          );

      final safeAlertId = alertId ?? 'OFFLINE_PENDING';
      // ONE predicate, not a second prefix test. This decides whether the
      // dispatcher channel opens, and it asked "does this not look local"
      // where the column asks "is this a uuid". See T-86.
      final isRealAlertId = isServerAlertId(safeAlertId);

      unawaited(
        BackgroundTrackingService().startSosTracking(safeAlertId, userId),
      );

      dispatchRef = isRealAlertId ? alertId : null;
      state = state.copyWith(alertId: dispatchRef);
    } catch (e) {
      dev.log('SOS Alert Creation Failed: $e', name: 'CRITICAL_SOS_ERR');
      state = state.copyWith(
        errorMessage: 'Alert delayed — stay on screen, tracking active.',
      );
    }

    // Redundant out-of-band nudge to the HQ dispatch line, for the case where
    // nobody is watching the dashboard.
    //
    // OUTSIDE the try/catch on purpose. A redundant channel that only fires when
    // the primary channel succeeded is not redundancy. `submitAlert` happens to
    // swallow everything and return a local id today, so placing this inside the
    // try worked — but it made the SOS fallback silently depend on that, and a
    // later `rethrow` in AlertService would have removed the fallback in exactly
    // the situation it exists for, with nothing failing to show it.
    //
    // Not awaited: it previously ran BEFORE the alert write, blocking the system
    // of record behind an SMS provider's latency.
    //
    // A local/offline id is passed as null rather than as text: 'LOCAL_1723…'
    // means nothing to a dispatcher and would read as a real reference.
    unawaited(
      _dispatchEscalationSms(
        alertId: dispatchRef,
        latitude: latVal,
        longitude: lngVal,
      ),
    );
  }

  /// Ask the HQ backend to send the escalation SMS.
  ///
  /// The Termii credential is no longer on the device (finding H-3), so this is
  /// an authenticated call to our own backend rather than a call to the SMS
  /// provider. Every outcome is logged and none of them fail the SOS.
  Future<void> _dispatchEscalationSms({
    required String? alertId,
    required double? latitude,
    required double? longitude,
  }) async {
    final result = await ref.read(sosDispatchServiceProvider).dispatchSos(
          alertId: alertId,
          latitude: latitude,
          longitude: longitude,
        );
    if (result != SosDispatchResult.sent) {
      dev.log(
        'SOS escalation SMS not sent: ${result.name}. '
        'The alert row is unaffected.',
        name: 'EmergencyNotifier',
      );
    }
  }

  void tick() {
    if (state.isEmergencyActive) {
      state = state.copyWith();
    }
  }

  /// Test seam: BackgroundTrackingService talks to platform channels, which do
  /// not exist under `flutter test`.
  @visibleForTesting
  static Future<void> Function()? stopTrackingOverride;

  /// Verifies an emergency PIN ON THE SERVER and, when there is an alert, closes
  /// it there too.
  ///
  /// This used to compare the entry against SAFE_PIN / DURESS_PIN — build-time
  /// constants shipped inside the APK, identical for every install and
  /// readable by anyone who unzipped it. No PIN material exists on the device
  /// now: `resolve_emergency` checks a bcrypt hash the API cannot read, rate
  /// limits guesses, and records who resolved the alert.
  ///
  /// The screen treats [CancelOutcome.resolved] and [CancelOutcome.duress]
  /// identically — that is the whole point of a duress code. The only
  /// difference is that tracking keeps running under duress, so HQ can follow.
  Future<CancelOutcome> verifyCancellation(String pin) async {
    try {
      final dynamic raw = state.alertId != null
          ? await SupabaseConfig.client.rpc<dynamic>(
              'resolve_emergency',
              params: <String, dynamic>{'p_alert_id': state.alertId, 'p_pin': pin},
            )
          : await SupabaseConfig.client.rpc<dynamic>(
              'verify_emergency_pin',
              params: <String, dynamic>{'p_pin': pin},
            );
      final code = raw is String ? raw : raw?.toString() ?? '';

      switch (code) {
        case 'RESOLVED':
        case 'SAFE':
          unawaited(
            (stopTrackingOverride ?? BackgroundTrackingService().stopTracking)(),
          );
          state = const EmergencyState();
          return CancelOutcome.resolved;
        case 'DURESS':
          // Deliberately NOT stopping tracking: the person may still be in danger.
          state = const EmergencyState();
          return CancelOutcome.duress;
        case 'LOCKED':
          return CancelOutcome.locked;
        case 'UNSET':
          return CancelOutcome.unset;
        case 'NOT_FOUND':
          return CancelOutcome.notFound;
        default:
          return CancelOutcome.invalid;
      }
    } catch (e) {
      dev.log('Cancel Verify Failed: $e', name: 'SYS_ERR');
      return CancelOutcome.error;
    }
  }
}

/// What the server said about a cancellation attempt.
enum CancelOutcome {
  /// Safe PIN: the alert is resolved and tracking stops.
  resolved,

  /// Duress PIN: the alert is flagged DURESS; the screen behaves as [resolved].
  duress,

  /// Wrong PIN.
  invalid,

  /// Too many wrong PINs; entry is locked for a while.
  locked,

  /// This account has no emergency PINs configured yet.
  unset,

  /// No such alert reported by or assigned to this user.
  notFound,

  /// The server could not be reached, or returned something unexpected.
  error,
}
