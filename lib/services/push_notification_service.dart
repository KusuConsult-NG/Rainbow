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
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fcmToken': token,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SYS_ERR] Failed to save FCM token: $e');
    }
  }
}
