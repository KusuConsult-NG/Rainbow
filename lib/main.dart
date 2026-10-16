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
import 'package:rainbow_app/core/startup/startup_failure.dart';
import 'package:rainbow_app/core/net/resolving_http_overrides.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Whether a root widget has been handed to Flutter yet.
///
/// Guards the zone handler below: a late async error must not replace a
/// running app with a failure screen, but an error that escapes BEFORE the
/// first frame must not leave the window empty.
bool _rootWidgetRequested = false;

void main() {
  // ignore: discarded_futures
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // FIRST, before anything that can throw.
    //
    // In a release build Flutter's stock error widget paints a pale rectangle
    // with no text on it, because the message it would show is composed inside
    // an `assert` (see core/startup/startup_failure.dart for the citations).
    // An exception from any `build()` therefore looked exactly like "the app
    // loads a blank page and stops there" — which is what an installed APK
    // did. This replaces it with a screen that names the failure.
    installReadableErrorWidget();

    // SECOND, and before anything opens a socket.
    //
    // A handset in Plateau, showing four bars of 4G, could not resolve the
    // backend's hostname: "No address associated with hostname, errno = 7" —
    // an EMPTY answer from the device's resolver, not a missing name. The
    // same hostname loaded in Chrome on the same phone, because Chrome can
    // resolve over its own DNS-over-HTTPS while Flutter goes through the
    // system getaddrinfo(). A Private DNS profile, a filtering carrier
    // resolver or a VPN all produce that split.
    //
    // Nobody reporting an emergency is going to be told to open Settings, so
    // the app carries its own resolver and uses it only when the device's
    // has already said no. `dart:io` holds its WebSocket client in a
    // `static final`, so this has to be installed before the first socket or
    // the realtime channel keeps the unmodified one for the session.
    ResolvingHttpOverrides.install();

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

    await boot();
  }, (error, stackTrace) {
    debugPrint('[CRITICAL_UNCAUGHT_ERR] $error');
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    // Before this, an error that reached here was logged and nothing else
    // happened. If it arrived before `runApp`, no Flutter frame was ever
    // produced and the window kept showing the launch background for as long
    // as the user was willing to stare at it.
    if (!_rootWidgetRequested) {
      _showStartupFailure(error, 'starting up');
    }
  });
}

/// Brings the app up, and guarantees a first frame.
///
/// Every step here is either (a) required before the app can be built at all,
/// in which case its failure produces a screen that says so, or (b) guarded
/// by [runStartupStep], which cannot stop start-up. Nothing between the top
/// of this function and [runApp] may throw past it.
///
/// Exposed for test rather than private: the one thing worth asserting about
/// start-up is that it always ends with a root widget, and that cannot be
/// asserted about a closure inside `main`.
@visibleForTesting
Future<void> boot() async {
  // ─── The one dependency the app cannot be built without ───
  //
  // Every screen reaches `SupabaseConfig.client`, and `AuthNotifier`'s
  // constructor reaches it synchronously during the first build. Building
  // `RainbowApp` without a client guarantees a build-time throw, so this is
  // checked rather than swallowed.
  //
  // BOUNDED, not merely guarded. The first version of this function wrapped
  // this in a try/catch and argued that `Supabase.initialize` does no network
  // I/O and therefore cannot hang. A try/catch catches a throw; it does not
  // catch a step that never finishes — and a step that never finishes here is
  // the same blank page as one that throws, because `runApp` is never
  // reached. The browser harness found the stall the argument had ruled out.
  debugPrint('🚀 [MAIN] Starting Supabase initialization...');
  final supabaseFailure = await runRequiredStartupStep(
    'Supabase initialization',
    SupabaseConfig.init,
    limit: const Duration(seconds: 8),
  );
  if (supabaseFailure == null) {
    debugPrint('🚀 [MAIN] Supabase initialized.');
  } else {
    debugPrint('🔥 [CRITICAL_MAIN_ERR] Supabase Init Failed: $supabaseFailure');
    unawaited(Sentry.captureException(supabaseFailure));
  }

  if (!SupabaseConfig.isInitialized) {
    _showStartupFailure(
      supabaseFailure ??
          StateError('SupabaseConfig.init() returned without a client.'),
      'connecting to the Plateau Eye service',
      canRetry: true,
    );
    return;
  }

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

  // Bounded and guarded, and kept before the first frame because AppConfig
  // reads these values: a screen built before they land would silently use
  // its fallbacks.
  await runStartupStep('.env load', () async {
    await dotenv.load().timeout(const Duration(seconds: 3));
    debugPrint('🚀 [MAIN] .env Loaded. keys=${dotenv.env.length}');
  });

  // Report configuration state explicitly. The load above is intentionally
  // non-fatal, which means a missing .env used to leave the app running with
  // every fallback silently active. validate() makes that visible in logs and
  // throws in debug builds so it cannot reach a tester unnoticed — which is
  // also why it is guarded: a debug throw here must not cost the first frame.
  await runStartupStep('config validation', () async => AppConfig.validate());

  // Orientation lock before the first frame, so the app does not flash
  // landscape on a tilted phone. Bounded: it is a platform channel call, and
  // nothing on this path is allowed to wait forever.
  await runStartupStep('orientation lock', () async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).timeout(const Duration(seconds: 2));
  });

  // ─── THE FIRST FRAME ───
  _rootWidgetRequested = true;
  runApp(
    const ProviderScope(
      observers: [TacticalProviderObserver()],
      child: RainbowApp(),
    ),
  );

  // ─── Everything below is not needed to draw a frame ───
  //
  // It used to run BEFORE `runApp`. A throw from any of it — a plugin that
  // failed to register, a platform channel that rejected a call — jumped
  // straight to the zone handler, and `runApp` was never reached.

  await runStartupStep('system UI style', () async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  });

  await runStartupStep('connectivity listener', () async {
    Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = !results.contains(ConnectivityResult.none);
      if (isOnline) {
        debugPrint('[SYNC] Connectivity restored — flushing offline queue.');
        unawaited(AlertService().flushOfflineQueue());
      }
    });
  });

  await runStartupStep('lifecycle observer', () async {
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
  });

  unawaited(
    runStartupStep('background tracking service', () async {
      await BackgroundTrackingService()
          .initializeService()
          .timeout(const Duration(seconds: 3));
      debugPrint('🚀 [MAIN] BackgroundTrackingService Ready.');
    }),
  );
}

/// Puts a legible failure on screen in place of the app.
void _showStartupFailure(
  Object error,
  String stage, {
  bool canRetry = false,
}) {
  _rootWidgetRequested = true;
  runApp(
    StartupFailureScreen(
      error: error,
      stage: stage,
      onRetry: canRetry
          ? () {
              // `Supabase.initialize` returns the existing instance rather
              // than re-running when the client was already built, so a retry
              // after a partial failure genuinely can succeed.
              unawaited(boot());
            }
          : null,
    ),
  );
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
