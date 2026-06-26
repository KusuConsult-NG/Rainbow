import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_theme.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';

/// Documentation for this public member.

class RainbowApp extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const RainbowApp({super.key});

  @override
  ConsumerState<RainbowApp> createState() => _RainbowAppState();
}

class _RainbowAppState extends ConsumerState<RainbowApp> {
  @override
  void initState() {
    super.initState();
    // Initialize Core Tactical Services
    unawaited(
      Future.microtask(() async {
        debugPrint('🚀 [APP] Initializing PushNotificationService...');
        await ref.read(pushNotificationServiceProvider).initialize();
        debugPrint('🚀 [APP] PushNotificationService initialized.');
        ref.read(
          syncServiceProvider,
        ); // Triggers auto-initialization via provider
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Operation Rainbow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouter),
      builder: (context, child) {
        return SystemAlertListener(child: child!);
      },
    );
  }
}
