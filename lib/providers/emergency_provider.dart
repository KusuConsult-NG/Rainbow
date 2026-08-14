import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/core/config/app_config.dart';
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
      final isRealAlertId = !safeAlertId.startsWith('LOCAL_') &&
          !safeAlertId.startsWith('OFFLINE_');

      unawaited(
        BackgroundTrackingService().startSosTracking(safeAlertId, userId),
      );

      // Redundant out-of-band nudge to the HQ dispatch line, for the case where
      // nobody is watching the dashboard.
      //
      // Deliberately NOT awaited: it used to run first and block the alert write
      // behind an SMS provider's latency, which is backwards — the alert row is
      // the system of record and must be created as fast as possible.
      //
      // A local/offline id is passed as null rather than as text: 'LOCAL_1723…'
      // means nothing to a dispatcher and would read as a real reference.
      unawaited(
        _dispatchEscalationSms(
          alertId: isRealAlertId ? alertId : null,
          latitude: latVal,
          longitude: lngVal,
        ),
      );

      state = state.copyWith(alertId: isRealAlertId ? alertId : null);
    } catch (e) {
      dev.log('SOS Alert Creation Failed: $e', name: 'CRITICAL_SOS_ERR');
      state = state.copyWith(
        errorMessage: 'Alert delayed — stay on screen, tracking active.',
      );
    }
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

  Future<bool> verifyCancellation(String pin) async {
    // No fallbacks. These previously defaulted to '0000'/'9999', which are
    // published in this repository — a captor who had read it would know that
    // 9999 signals duress. Unconfigured now means "reject", not "use 9999".
    final safePin = AppConfig.safePin;
    final duressPin = AppConfig.duressPin;

    if (safePin == null || duressPin == null) {
      dev.log(
        'Emergency PINs unconfigured — cancellation rejected. See AppConfig.validate().',
        name: 'CONFIG_ERR',
      );
      return false;
    }

    try {
      if (pin == safePin) {
        if (state.alertId != null) {
          await SupabaseConfig.client
              .from('alerts')
              .update({'status': 'RESOLVED'})
              .eq('id', state.alertId!);
        }
        unawaited(BackgroundTrackingService().stopTracking());
        state = const EmergencyState();
        return true;
      } else if (pin == duressPin) {
        if (state.alertId != null) {
          await SupabaseConfig.client
              .from('alerts')
              .update({'status': 'DURESS'})
              .eq('id', state.alertId!);
        }
        state = const EmergencyState();
        return true;
      }
    } catch (e) {
      dev.log('Cancel Verify Failed: $e', name: 'SYS_ERR');
    }

    return false;
  }
}
