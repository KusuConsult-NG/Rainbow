import 'package:flutter/foundation.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.read(authServiceProvider));
});

class PushNotificationService {
  final AuthService _authService;

  PushNotificationService(this._authService);

  Future<void> initialize() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('[SYS_INFO] User granted push notification permission.');
      
      // Get the token and attach it to the current user's profile
      String? token = await messaging.getToken();
      if (token != null) {
        _saveTokenToFirestore(token);
      }

      // Listen for token refreshes
      messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
      });

      // Handle foreground messages natively if needed.
      // Usually, OS handles background ones, but we log foreground here.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[SYS_INFO] Received Foreground Push: ${message.notification?.title}');
      });
    } else {
      debugPrint('[SYS_WARN] User declined or has not accepted push notification permissions.');
    }
  }

  void _saveTokenToFirestore(String token) async {
    final uid = _authService.currentUserId;
    if (uid == null) return;
    
    try {
      // 1. Save token and fetch profile
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final String? role = data['role'];
      final String? lga = data['lga'];
      final String? ward = data['ward'];

      FirebaseMessaging messaging = FirebaseMessaging.instance;

      if (role != null) {
        // Global Role Topic
        await messaging.subscribeToTopic('staff_${role.toLowerCase()}');
        
        // Broadcast Topics (Match backend massBroadcast)
        await messaging.subscribeToTopic('all_citizens');

        if (lga != null) {
          final cleanLga = lga.toLowerCase().replaceAll(' ', '_');
          await messaging.subscribeToTopic('lga_$cleanLga');
          // For staff-specific LGA alerts
          await messaging.subscribeToTopic('staff_lga_$cleanLga');
        }

        if (ward != null) {
          final cleanWard = ward.toLowerCase().replaceAll(' ', '_');
          await messaging.subscribeToTopic('ward_$cleanWard');
          // For staff-specific Ward alerts
          await messaging.subscribeToTopic('staff_ward_$cleanWard');
        }
      } else {
        // Citizens subscribe to global broadcasts
        await messaging.subscribeToTopic('all_citizens');
      }
    } catch (e) {
      debugPrint('[SYS_ERR] Failed to sync jurisdictional communications: $e');
    }
  }
}
