// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/app.dart';
import 'package:rainbow_app/core/providers/tactical_provider_observer.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await SupabaseConfig.init();
    await AlertService().flushOfflineQueue();
    return Future.value(true);
  });
}

void main() {
  // ignore: discarded_futures
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[CRITICAL_FLUTTER_ERR] ${details.exception}');
      unawaited(
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[CRITICAL_PLATFORM_ERR] $error');
      unawaited(Sentry.captureException(error, stackTrace: stack));
      return true;
    };

    // ─── PHASE 1: Supabase Initialization ───
    debugPrint('🚀 [MAIN] Starting Supabase initialization...');
    try {
      await SupabaseConfig.init();
      debugPrint('🚀 [MAIN] Supabase initialized.');
    } catch (e) {
      debugPrint('🔥 [CRITICAL_MAIN_ERR] Supabase Init Failed: $e');
    }

    // ─── PHASE 2: Non-blocking background services ───
    unawaited(
      Future(() async {
        // Workmanager (Android offline sync worker)
        try {
          await Workmanager()
              .initialize(callbackDispatcher)
              .timeout(const Duration(seconds: 3));
          await Workmanager()
              .registerPeriodicTask(
                '1',
                'offlineSyncTask',
                frequency: const Duration(minutes: 15),
                constraints: Constraints(networkType: NetworkType.connected),
              )
              .timeout(const Duration(seconds: 3));
          debugPrint('🚀 [MAIN] Workmanager initialized.');
        } catch (e) {
          debugPrint('⚠️ Workmanager Init Failed: $e');
        }

        // Background tracking service configure
        try {
          await BackgroundTrackingService()
              .initializeService()
              .timeout(const Duration(seconds: 3));
          debugPrint('🚀 [MAIN] BackgroundTrackingService Ready.');
        } catch (e) {
          debugPrint('⚠️ BackgroundTrackingService init failed: $e');
        }
      }),
    );

    // Connectivity sync listener
    Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = !results.contains(ConnectivityResult.none);
      if (isOnline) {
        debugPrint('[SYNC] Connectivity restored — flushing offline queue.');
        unawaited(AlertService().flushOfflineQueue());
      }
    });

    // Add Lifecycle Observer for app resume offline sync
    WidgetsBinding.instance.addObserver(
      _LifecycleEventHandler(
        resumeCallBack: () async {
          final connectivityResult = await Connectivity().checkConnectivity();
          if (!connectivityResult.contains(ConnectivityResult.none)) {
            debugPrint('[SYNC] App Resumed — flushing offline queue.');
            unawaited(AlertService().flushOfflineQueue());
          }
        },
      ),
    );

    try {
      debugPrint('🚀 [MAIN] Loading .env...');
      await dotenv.load().timeout(const Duration(seconds: 3));
      debugPrint('🚀 [MAIN] .env Loaded.');
    } catch (e) {
      debugPrint('⚠️ [MAIN] .env load warning: $e');
    }

    // Force orientation lock for security HUD consistency
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // System UI Overlay Styling
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    runApp(
      ProviderScope(
        observers: [TacticalProviderObserver()],
        child: const RainbowApp(),
      ),
    );
  }, (error, stackTrace) {
    debugPrint('[CRITICAL_UNCAUGHT_ERR] $error');
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  });
}

class _LifecycleEventHandler extends WidgetsBindingObserver {
  _LifecycleEventHandler({this.resumeCallBack});

  final AsyncCallback? resumeCallBack;

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      if (resumeCallBack != null) {
        await resumeCallBack!();
      }
    }
  }
}
