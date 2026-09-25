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
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:rainbow_app/core/providers/tactical_provider_observer.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

    // Never fetch a font over the network.
    //
    // `google_fonts` downloads font files on first use and caches them. A UI
    // test against the web build with fonts.gstatic.com unreachable rendered
    // EVERY LABEL BLANK — the logo and the icon fonts drew, but the panic
    // button had no text on it. Text in an emergency app cannot depend on
    // reaching a Google CDN from a rural link.
    //
    // The weights this app uses are bundled under assets/google_fonts/, which
    // the package resolves before considering the network. Turning fetching off
    // means a family that is NOT bundled falls back to the platform font
    // immediately and visibly, rather than working for whoever has warm cache
    // and failing for whoever does not.
    GoogleFonts.config.allowRuntimeFetching = false;

    try {
      debugPrint('🚀 [MAIN] Loading .env...');
      await dotenv.load().timeout(const Duration(seconds: 3));
      debugPrint('🚀 [MAIN] .env Loaded. keys=${dotenv.env.length}');
    } catch (e) {
      debugPrint('⚠️ [MAIN] .env load warning: $e');
    }

    // Report configuration state explicitly. The load above is intentionally
    // non-fatal, which means a missing .env used to leave the app running with
    // every fallback silently active. validate() makes that visible in logs and
    // throws in debug builds so it cannot reach a tester unnoticed.
    AppConfig.validate();

    // Crash reporting. Three call sites already report to Sentry — the two
    // handlers in this file and one in the router — but SentryFlutter.init was
    // never called, so all of them were no-ops and no production crash has ever
    // been reported.
    await _initSentry();

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
      const ProviderScope(
        observers: [TacticalProviderObserver()],
        child: RainbowApp(),
      ),
    );
  }, (error, stackTrace) {
    debugPrint('[CRITICAL_UNCAUGHT_ERR] $error');
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  });
}

Future<void> _initSentry() async {
  final dsn = dotenv.isInitialized ? (dotenv.env['SENTRY_DSN'] ?? '') : '';
  if (dsn.isEmpty) {
    debugPrint(
      '⚠️ [MAIN] SENTRY_DSN not set — crash reporting disabled for this run.',
    );
    return;
  }
  try {
    await SentryFlutter.init((options) {
      options
        ..dsn = dsn
        ..tracesSampleRate = 0.2
        ..environment = kReleaseMode ? 'production' : 'development';
    });
    debugPrint('🚀 [MAIN] Sentry initialized.');
  } catch (e) {
    debugPrint('⚠️ [MAIN] Sentry init failed: $e');
  }
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
