/// Crash and error reports, sent to Sentry only when the build names a
/// project in `SENTRY_DSN`.
///
/// `main.dart` called `Sentry.captureException` from four places, but nothing
/// ever called `SentryFlutter.init`, so every one of those reports went
/// nowhere: it looked like error reporting and was not. With no DSN that is
/// still what happens, now on purpose and logged as such. With a DSN, reports
/// are sent.
///
/// WHAT IS SENT, AND WHAT IS NOT. This app handles people in danger, and
/// Guardian tells them that nothing it hears leaves the phone. So a report
/// carries the error, its stack trace, and the app, OS and device versions,
/// and nothing about the person:
///   * no breadcrumbs at all ([SentryOptions.maxBreadcrumbs] 0). Breadcrumbs
///     would otherwise carry log lines, HTTP requests (with alert ids and
///     coordinates in their query strings), screen names and taps;
///   * no user, no IP address, no request bodies
///     ([SentryOptions.sendDefaultPii] false);
///   * no screenshot and no view hierarchy, which would show the screen;
///   * no performance tracing.
library;

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Starts error reporting when, and only when, a DSN is configured.
class ErrorReporting {
  ErrorReporting._();

  static bool _enabled = false;

  /// Whether reports are being sent.
  static bool get enabled => _enabled;

  /// Starts Sentry if `SENTRY_DSN` is set. Call after `.env` is loaded.
  ///
  /// Sentry installs its own `FlutterError.onError` and
  /// `PlatformDispatcher.onError` handlers, which report and then call the
  /// app's own. So those two handlers must not report themselves, or every
  /// error would be sent twice.
  static Future<void> start() async {
    final dsn = AppConfig.sentryDsn;
    if (dsn == null) {
      debugPrint('[REPORTS] off: no SENTRY_DSN in .env, so errors stay on the phone.');
      return;
    }
    await SentryFlutter.init((options) => configure(options, dsn));
    _enabled = true;
    debugPrint('[REPORTS] on: errors are reported, without personal data.');
  }

  /// The options [start] uses. Exposed for the test that holds them in place.
  @visibleForTesting
  static void configure(SentryFlutterOptions options, String dsn) {
    options
      ..dsn = dsn
      ..sendDefaultPii = false
      ..maxBreadcrumbs = 0
      ..enablePrintBreadcrumbs = false
      ..enableAutoNativeBreadcrumbs = false
      ..enableUserInteractionBreadcrumbs = false
      // attachViewHierarchy is left at its default, off: the setter is
      // marked experimental, and setting it is an analyzer warning.
      ..attachScreenshot = false
      ..enableAutoPerformanceTracing = false
      ..tracesSampleRate = null;
  }
}
