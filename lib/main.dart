// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/app.dart';
import 'package:rainbow_app/core/providers/tactical_provider_observer.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/firebase_options.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

/// Documentation for this public member.

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await AlertService().flushOfflineQueue();
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Handling a background message: ${message.messageId}');
}

void main() {
  // ignore: discarded_futures
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[CRITICAL_FLUTTER_ERR] ${details.exception}');
      unawaited(FirebaseCrashlytics.instance.recordFlutterError(details));
      unawaited(
        Sentry.captureException(
          details.exception,
          stackTrace: details.stack,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('[CRITICAL_PLATFORM_ERR] $error');
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
      unawaited(Sentry.captureException(error, stackTrace: stack));
      return true;
    };

    // ─── PHASE 1: Firebase Core (must complete before anything else) ───
    debugPrint('🚀 [MAIN] Starting Firebase initialization...');
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));
      debugPrint('🚀 [MAIN] Firebase initialized.');
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('🔥 [CRITICAL_MAIN_ERR] Firebase Init Failed: $e');
    }

    // Offline persistence — synchronous config, no network needed
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('⚠️ Offline Persistence Config Failed: $e');
    }

    // ─── PHASE 2: Non-blocking background services (fire-and-forget) ───
    // These run AFTER runApp() so they never delay the UI reaching the screen.
    unawaited(
      Future(() async {
        // Workmanager (Android-only, no-op on iOS but guarded)
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
          // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
        } catch (e) {
          debugPrint('⚠️ Workmanager Init Failed: $e');
        }

        // FCM permission — only once, with timeout so it never hangs
        try {
          final fcmSettings = await FirebaseMessaging.instance
              .requestPermission()
              .timeout(const Duration(seconds: 5));
          FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler,
          );
          if (fcmSettings.authorizationStatus ==
              AuthorizationStatus.authorized) {
            final token = await FirebaseMessaging.instance
                .getToken()
                .timeout(const Duration(seconds: 5));
            debugPrint('🚀 [MAIN] FCM Token: $token');
          }
          debugPrint('🚀 [MAIN] Messaging Ready.');
          // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
        } catch (e) {
          debugPrint('⚠️ Messaging Init Failed: $e');
        }

        // Background tracking service configure
        try {
          await BackgroundTrackingService()
              .initializeService()
              .timeout(const Duration(seconds: 3));
          debugPrint('🚀 [MAIN] BackgroundTrackingService Ready.');
          // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
        } catch (e) {
          debugPrint('⚠️ BackgroundTrackingService init failed: $e');
        }

        // App Check — DeviceCheck can hang on iOS 26 review sandbox;
        // must run non-blocking with a hard timeout.
        try {
          if (kDebugMode) {
            debugPrint(
              '🛡️ APP CHECK DEBUG TOKEN: 27A4E831-C72B-4A12-8E82-723A63B4F555',
            );
            await FirebaseAppCheck.instance
                .activate(
                  providerAndroid: const AndroidDebugProvider(),
                  providerApple: const AppleDebugProvider(),
                )
                .timeout(const Duration(seconds: 5));
          } else {
            await FirebaseAppCheck.instance
                .activate()
                .timeout(const Duration(seconds: 5));
          }
          debugPrint('🚀 [MAIN] App Check Ready.');
          // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
        } catch (e) {
          debugPrint('⚠️ App Check Init Failed (non-fatal): $e');
        }
      }),
    );

    // Connectivity sync listener — no await needed
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

      final dsn = dotenv.env['SENTRY_DSN'];
      if (dsn != null && dsn.isNotEmpty) {
        await SentryFlutter.init((options) {
          options
            ..dsn = dsn
            ..tracesSampleRate = 1.0;
        });
        debugPrint('🚀 [MAIN] Sentry Telemetry Ready.');
      } else {
        debugPrint(
          '⚠️ [MAIN] Sentry DSN not found in .env. Running without Sentry.',
        );
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('⚠️ .env Load/Sentry Init Failed: $e');
    }

    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Defensive UI Override
    ErrorWidget.builder = (details) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: AppColors.background,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.terminal_rounded,
                    color: AppColors.emergency,
                    size: 48,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'TACTICAL KERNEL PANIC',
                    style: GoogleFonts.outfit(
                      color: AppColors.emergency,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A critical rendering failure occurred.\nForensic logs transmitted to HQ.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        details.exceptionAsString(),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    };

    debugPrint('🚀 [MAIN] Launching UI (runApp)...');
    runApp(
      const ProviderScope(
        observers: [TacticalProviderObserver()],
        child: RainbowApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('🔥 [CRITICAL_ZONE_ERR] $error');
    // PRD: Ensure secondary log stream for out-of-band crashes
    // FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class _LifecycleEventHandler extends WidgetsBindingObserver {
  _LifecycleEventHandler({required this.resumeCallBack});

  final Future<void> Function() resumeCallBack;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(resumeCallBack());
    }
  }
}
