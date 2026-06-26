// PRD §5: Device binding (prevent abuse) + Device fingerprinting (§14)
// Associates the current Firebase user with a unique device ID, and checks
// for forced-logout signals from HQ.
// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Documentation for this public member.

class DeviceService {
  /// Documentation for this public member.
  factory DeviceService() => _instance;
  DeviceService._internal();
  static final DeviceService _instance = DeviceService._internal();

  final _storage = const FlutterSecureStorage();
  StreamSubscription<DocumentSnapshot>? _sessionSubscription;

  /// Returns or creates a persistent device fingerprint stored in secure storage.
  Future<String> getDeviceId() async {
    final deviceId = await _storage.read(key: 'device_fingerprint');
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
      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        {
          'device_id': deviceId,
          'last_login': FieldValue.serverTimestamp(),
          'platform': Platform.operatingSystem,
          'forceLogout': false,
        },
        SetOptions(merge: true),
      );
      debugPrint('[DEVICE] Session registered: $deviceId → user $userId');
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[DEVICE_ERR] Failed to register session: $e');
    }
  }

  /// Streams the user's Firestore profile and forces app logout if HQ sets forceLogout=true.
  void listenForForcedLogout(String userId, void Function() onForcedLogout) {
    if (_sessionSubscription != null) {
      unawaited(_sessionSubscription!.cancel());
    }
    _sessionSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data['forceLogout'] == true) {
        debugPrint(
          '[SEC] HQ FORCED LOGOUT detected for user $userId. Signing out.',
        );
        unawaited(FirebaseAuth.instance.signOut());
        onForcedLogout();
      }
    });
  }

  /// Documentation for this public member.

  void dispose() {
    if (_sessionSubscription != null) {
      unawaited(_sessionSubscription!.cancel());
    }
  }
}
