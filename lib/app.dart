import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'services/push_notification_service.dart';

class RainbowApp extends ConsumerStatefulWidget {
  const RainbowApp({super.key});

  @override
  ConsumerState<RainbowApp> createState() => _RainbowAppState();
}

class _RainbowAppState extends ConsumerState<RainbowApp> {
  @override
  void initState() {
    super.initState();
    // Initialize Push Notifications
    Future.microtask(() {
      ref.read(pushNotificationServiceProvider).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Operation Rainbow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
