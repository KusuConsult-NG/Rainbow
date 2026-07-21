import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/core/models/emergency_state.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/termii_service.dart';

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
      var locationText = 'Location Unknown';
      if (latVal != null && lngVal != null) {
        locationText = '$latVal, $lngVal';
      }

      await ref.read(termiiServiceProvider).sendEmergencyAlert(
            dotenv.env['SOS_PHONE'] ?? '0800RAINBOWHQ',
            'SOS [CRITICAL]: User $userId triggered panic! '
            'L/KL: $locationText. Dispatch immediately.',
          );
    } catch (e) {
      dev.log('Emergency SMS failed: $e', name: 'EmergencyNotifier');
    }

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
      state = state.copyWith(alertId: isRealAlertId ? alertId : null);
    } catch (e) {
      dev.log('SOS Alert Creation Failed: $e', name: 'CRITICAL_SOS_ERR');
      state = state.copyWith(
        errorMessage: 'Alert delayed — stay on screen, tracking active.',
      );
    }
  }

  void tick() {
    if (state.isEmergencyActive) {
      state = state.copyWith();
    }
  }

  Future<bool> verifyCancellation(String pin) async {
    final safePin = dotenv.env['SAFE_PIN'] ?? '0000';
    final duressPin = dotenv.env['DURESS_PIN'] ?? '9999';

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
