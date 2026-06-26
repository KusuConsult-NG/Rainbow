// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/services/auth_service.dart';

/// Documentation for this public member.

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.read(authServiceProvider));
});

/// Documentation for this public member.

class PushNotificationService {
  /// Documentation for this public member.
  PushNotificationService(this._authService);
  final AuthService _authService;

  /// Documentation for this public member.

  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission().timeout(
            const Duration(seconds: 5),
          );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('[SYS_INFO] User granted push notification permission.');

        // Get the token and attach it to the current user's profile
        final token = await messaging.getToken().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('[SYS_WARN] FCM getToken timed out.');
            return null;
          },
        );
        if (token != null) {
          unawaited(_saveTokenToFirestore(token));
        }

        // Listen for token refreshes — only when notifications are authorized
        messaging.onTokenRefresh.listen((newToken) {
          unawaited(_saveTokenToFirestore(newToken));
        });

        // Handle foreground messages natively if needed.
        FirebaseMessaging.onMessage.listen((message) {
          debugPrint(
            '[SYS_INFO] Received Foreground Push: ${message.notification?.title}',
          );
        });
      } else {
        debugPrint(
          '[SYS_WARN] User declined or has not accepted push notification permissions.',
        );
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[SYS_ERR] Push notification initialization failed: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final uid = _authService.currentUserId;
    if (uid == null) return;

    try {
      // 1. Save token and fetch profile
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 5));

      if (!userDoc.exists || userDoc.data() == null) return;

      final data = userDoc.data()!;
      final role = data['role'] as String?;
      final lga = data['lga'] as String?;
      final ward = data['ward'] as String?;

      final messaging = FirebaseMessaging.instance;
      final cleanLga = lga?.toLowerCase().replaceAll(' ', '_');
      final cleanWard = ward?.toLowerCase().replaceAll(' ', '_');

      final subscriptionFutures = <Future<void>>[
        if (role != null) ...[
          messaging.subscribeToTopic('staff_${role.toLowerCase()}'),
          messaging.subscribeToTopic('all_citizens'),
          if (cleanLga != null) ...[
            messaging.subscribeToTopic('lga_$cleanLga'),
            messaging.subscribeToTopic('staff_lga_$cleanLga'),
          ],
          if (cleanWard != null) ...[
            messaging.subscribeToTopic('ward_$cleanWard'),
            messaging.subscribeToTopic('staff_ward_$cleanWard'),
          ],
        ] else
          messaging.subscribeToTopic('all_citizens'),
      ];

      // Execute all subscriptions in parallel and catch individual errors gracefully
      await Future.wait(
        subscriptionFutures.map(
          (future) =>
              future.timeout(const Duration(seconds: 3)).catchError((Object e) {
            debugPrint('[SYS_ERR] Individual topic subscription failed: $e');
          }),
        ),
      );
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[SYS_ERR] Failed to sync jurisdictional communications: $e');
    }
  }
}
