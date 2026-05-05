import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/alert_service.dart';
import '../services/auth_service.dart';
import '../services/termii_service.dart';
import '../services/background_tracking_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final emergencyProvider = NotifierProvider<EmergencyNotifier, EmergencyState>(EmergencyNotifier.new);

class EmergencyState {
  final bool isActive;
  final DateTime? startTime;
  final String? alertId;

  const EmergencyState({this.isActive = false, this.startTime, this.alertId});

  String get formattedTime {
    if (startTime == null) return "00:00";
    final diff = DateTime.now().difference(startTime!);
    final m = (diff.inMinutes).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class EmergencyNotifier extends Notifier<EmergencyState> {
  @override
  EmergencyState build() => const EmergencyState();

  Future<void> startEmergency() async {
    final userId = ref.read(authServiceProvider).currentUserId ?? 'citizen';

    // 1. Dispatch SMS synchronously immediately (Bypasses Internet Deadzones)
    // We try to get quick location, otherwise send generic SOS
    String locationText = 'Location Unknown';
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) {
        locationText = '${pos.latitude}, ${pos.longitude}';
      }
    } catch (_) {}

    ref.read(termiiServiceProvider).sendEmergencyAlert(
      '0800RAINBOWHQ', 
      'SOS [CRITICAL]: Citizen $userId has triggered an active panic alert! \nL/KL: $locationText \nDispatch teams immediately.',
    );

    // 2. Generate the alert natively in Firebase
    final alertId = await ref.read(alertServiceProvider).submitAlert(
      type: 'PANIC SOS',
      description: 'Public Panic Button Activated',
      reportedBy: userId,
      isCritical: true,
    );
    
    // Fix #9: only start tracking with a real Firestore doc ID.
    // Offline-queued IDs start with 'LOCAL_' or 'OFFLINE_QUEUED_' — skip tracking for those.
    final isRealAlertId = !alertId.startsWith('LOCAL_') && !alertId.startsWith('OFFLINE_QUEUED_');
    if (isRealAlertId) {
      BackgroundTrackingService().startTracking(alertId, userId);
    } else {
      debugPrint('[SYS_WARN] EmergencyProvider: Skipping tracking — offline alertId: $alertId');
    }

    state = EmergencyState(isActive: true, startTime: DateTime.now(), alertId: isRealAlertId ? alertId : null);
  }

  void tick() {
    if (state.isActive) {
      // Re-triggering state assignment forces a UI rebuild to call `get formattedTime`
      state = EmergencyState(isActive: true, startTime: state.startTime, alertId: state.alertId);
    }
  }

  Future<bool> verifyCancellation(String pin) async {
    // Pins are loaded from environment to prevent APK reverse engineering
    final safePin = dotenv.env['SAFE_PIN'] ?? '1234';
    final duressPin = dotenv.env['DURESS_PIN'] ?? '9999';

    if (state.alertId == null) {
      state = const EmergencyState(isActive: false, startTime: null, alertId: null);
      return true;
    }

    if (pin == safePin) {
      try {
        await FirebaseFirestore.instance.collection('alerts').doc(state.alertId).update({'status': 'RESOLVED'});
      } catch (_) {}
      BackgroundTrackingService().stopTracking();
      state = const EmergencyState(isActive: false, startTime: null, alertId: null);
      return true;
    } else if (pin == duressPin) {
      try {
        await FirebaseFirestore.instance.collection('alerts').doc(state.alertId).update({'status': 'DURESS'});
      } catch (_) {}
      // Clear UI so attacker thinks it worked — duress stays active on HQ. DO NOT stop tracking!
      state = const EmergencyState(isActive: false, startTime: null, alertId: null);
      return true;
    }
    
    return false;
  }
}
