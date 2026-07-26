import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/services/auth_service.dart';

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.read(authServiceProvider));
});

class PushNotificationService {
  PushNotificationService(this._authService);
  final AuthService _authService;

  static GlobalKey<NavigatorState>? _navigatorKey;
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  static const String _oneSignalAppId = '885be8b2-5f31-4627-a618-685f54dd266a';

  Future<void> initialize() async {
    try {
      if (kDebugMode) {
        OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      }

      // Initialize OneSignal SDK
      OneSignal.initialize(_oneSignalAppId);

      // Prompt for push notification permissions
      await OneSignal.Notifications.requestPermission(true);

      // Link current Supabase User ID with OneSignal External ID
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        await OneSignal.login(userId);
        debugPrint('[ONESIGNAL] User logged in to OneSignal with ID: $userId');
      }

      // Get initial OneSignal Push Subscription ID (Player ID)
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId != null && playerId.isNotEmpty) {
        debugPrint('[ONESIGNAL] Subscription ID (Player ID) acquired: $playerId');
        await _saveTokenToProfile(playerId);
      }

      // Listen to subscription state changes
      OneSignal.User.pushSubscription.addObserver((state) async {
        final newPlayerId = state.current.id;
        debugPrint('[ONESIGNAL] Subscription state changed. New ID: $newPlayerId');
        if (newPlayerId != null && newPlayerId.isNotEmpty) {
          await _saveTokenToProfile(newPlayerId);
        }
      });

      // Listen for foreground notification clicks or receipts
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        debugPrint('[ONESIGNAL_FG] Notification received: ${event.notification.title} - ${event.notification.body}');
        event.notification.display();
      });

      OneSignal.Notifications.addClickListener((event) {
        debugPrint('[ONESIGNAL_CLICK] Notification clicked: ${event.notification.title}');
        // Navigate to mission intel if this is a dispatch notification
        final data = event.notification.additionalData;
        if (data != null) {
          final alertId = data['alertId'] as String?;
          final type = data['type'] as String?;
          if (alertId != null && (type == 'DISPATCH' || type == 'ALERT')) {
            _navigatorKey?.currentState?.pushNamed(
              '/mission-intel',
              arguments: {'alertId': alertId},
            );
          }
        }
      });
    } catch (e) {
      debugPrint('[ONESIGNAL_ERR] OneSignal push notification init failed: $e');
    }
  }

  Future<void> _saveTokenToProfile(String playerId) async {
    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId != null) {
        await SupabaseConfig.client.from('profiles').update({
          'onesignal_player_id': playerId,
          'push_enabled': true,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
        debugPrint('[ONESIGNAL] Player ID synced to profile for user $userId');
      }
    } catch (e) {
      debugPrint('[ONESIGNAL_ERR] Failed to save OneSignal player ID to Supabase: $e');
    }
  }
}
