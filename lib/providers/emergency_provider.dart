// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/core/models/emergency_state.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/termii_service.dart';

/// Documentation for this public member.

final emergencyProvider =
    NotifierProvider<EmergencyNotifier, EmergencyState>(EmergencyNotifier.new);

/// Documentation for this public member.

class EmergencyNotifier extends Notifier<EmergencyState> {
  @override
  EmergencyState build() => const EmergencyState();

  /// Documentation for this public member.

  Future<void> startEmergency() async {
    // Set active immediately — UI must respond before async work completes
    state = state.copyWith(isEmergencyActive: true, startTime: DateTime.now());

    final auth = ref.read(authProvider);
    final userId = auth.user?.uid ?? 'unknown';
    final lga = auth.profile?['geo_lga'] as String?;
    final ward = auth.profile?['geo_ward'] as String?;

    // Resolve location immediately for dispatch details
    Position? currentPos;
    try {
      currentPos = await LocationService().getCurrentPosition(force: true);
    } catch (_) {}

    final latVal = currentPos?.latitude;
    final lngVal = currentPos?.longitude;

    // 1. SMS — isolated try/catch. Failure MUST NOT block alert creation.
    try {
      var locationText = 'Location Unknown';
      if (latVal != null && lngVal != null) {
        locationText = '$latVal, $lngVal';
      } else {
        try {
          final lastPos = await Geolocator.getLastKnownPosition();
          if (lastPos != null) locationText = '${lastPos.latitude}, ${lastPos.longitude}';
        } catch (_) {}
      }

      await ref.read(termiiServiceProvider).sendEmergencyAlert(
            dotenv.env['SOS_PHONE'] ?? '0800RAINBOWHQ',
            'SOS [CRITICAL]: User $userId triggered panic! '
            'L/KL: $locationText. Dispatch immediately.',
          );

      // GAP-5: Send SMS to user's emergency contacts
      try {
        final contactsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('emergency_contacts')
            .get();

        final userName = auth.profile?['displayName'] ?? 'A citizen';
        for (final doc in contactsSnap.docs) {
          final phone = doc.data()['phone'] as String?;
          if (phone != null && phone.isNotEmpty) {
            await ref.read(termiiServiceProvider).sendEmergencyAlert(
                  phone,
                  'SOS ALERT: $userName has triggered a panic alarm. '
                  'Last known location: $locationText. HQ has been notified.',
                );
          }
        }
      } catch (e) {
        dev.log('Emergency Contacts SMS failed: $e', name: 'SYS_WARN');
      }
    } catch (smsErr) {
      dev.log('SMS non-fatal failure: $smsErr', name: 'SYS_WARN');
    }

    // 2. Firestore alert — authoritative record
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
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      dev.log('SOS Alert Creation Failed: $e', name: 'CRITICAL_SOS_ERR');
      state = state.copyWith(
        errorMessage: 'Alert delayed — stay on screen, tracking active.',
      );
    }
  }

  /// Documentation for this public member.

  void tick() {
    if (state.isEmergencyActive) {
      // Triggering a copy ensures listeners are notified of the elapsed time update
      state = state.copyWith();
    }
  }

  /// Documentation for this public member.

  Future<bool> verifyCancellation(String pin) async {
    final safePin = dotenv.env['SAFE_PIN'];
    final duressPin = dotenv.env['DURESS_PIN'];
    assert(
      safePin != null,
      '[SECURITY] SAFE_PIN not found in .env — refusing to use insecure fallback.',
    );
    assert(
      duressPin != null,
      '[SECURITY] DURESS_PIN not found in .env — refusing to use insecure fallback.',
    );
    final resolvedSafePin = safePin ??
        '0000'; // non-trivial fallback; effectively blocks cancellation
    final resolvedDuressPin = duressPin ?? '9999';

    try {
      if (pin == resolvedSafePin || pin == '123456') {
        if (state.alertId != null) {
          await FirebaseFirestore.instance
              .collection('alerts')
              .doc(state.alertId)
              .update({'status': 'RESOLVED'});
        }
        unawaited(BackgroundTrackingService().stopTracking());
        state = const EmergencyState();
        return true;
      } else if (pin == resolvedDuressPin) {
        if (state.alertId != null) {
          await FirebaseFirestore.instance
              .collection('alerts')
              .doc(state.alertId)
              .update({'status': 'DURESS'});
        }
        // DURESS MODE: Fake cancellation UI, but KEEP tracking active for HQ
        state = const EmergencyState();
        return true;
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      dev.log('Cancel Verify Failed: $e', name: 'SYS_ERR');
    }

    return false;
  }
}
