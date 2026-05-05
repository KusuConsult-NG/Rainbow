// PRD §5: Device binding (prevent abuse) + Device fingerprinting (§14)
// Associates the current Firebase user with a unique device ID, and checks
// for forced-logout signals from HQ.
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  final _storage = const FlutterSecureStorage();
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;

  /// Returns or creates a persistent device fingerprint stored in secure storage.
  Future<String> getDeviceId() async {
    String? deviceId = await _storage.read(key: 'device_fingerprint');
    if (deviceId != null) return deviceId;

    // Generate a pseudo-random device fingerprint (no native plugin required)
    final platform = Platform.operatingSystem;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newId = '${platform}_${timestamp}_${DateTime.now().microsecond}';
    await _storage.write(key: 'device_fingerprint', value: newId);
    return newId;
  }

  /// Called after successful login: registers the device with the user's Firestore
  /// profile, enabling HQ to force-logout by toggling `forceLogout` on the document.
  Future<void> registerDeviceSession(String userId) async {
    try {
      final deviceId = await getDeviceId();
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'device_id': deviceId,
        'last_login': FieldValue.serverTimestamp(),
        'platform': Platform.operatingSystem,
        'forceLogout': false,
      }, SetOptions(merge: true));
      debugPrint('[DEVICE] Session registered: $deviceId → user $userId');
    } catch (e) {
      debugPrint('[DEVICE_ERR] Failed to register session: $e');
    }
  }

  /// Streams the user's Firestore profile and forces app logout if HQ sets forceLogout=true.
  void listenForForcedLogout(String userId, void Function() onForcedLogout) {
    _sessionSubscription?.cancel();
    _sessionSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data['forceLogout'] == true) {
        debugPrint('[SEC] HQ FORCED LOGOUT detected for user $userId. Signing out.');
        FirebaseAuth.instance.signOut();
        onForcedLogout();
      }
    });
  }

  void dispose() {
    _sessionSubscription?.cancel();
  }
}
