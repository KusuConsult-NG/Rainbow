// Crash and error reports: off unless a DSN is configured, and never carrying
// anything about the person when on. See lib/core/startup/error_reporting.dart.
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:rainbow_app/core/startup/error_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('the DSN', () {
    test('is read when it is https', () {
      dotenv.loadFromString(envString: 'SENTRY_DSN=https://abc@o1.ingest.sentry.io/2');
      expect(AppConfig.sentryDsn, 'https://abc@o1.ingest.sentry.io/2');
    });

    test('is ignored when blank or not https', () {
      dotenv.loadFromString(envString: 'SENTRY_DSN=');
      expect(AppConfig.sentryDsn, isNull);
      dotenv.loadFromString(envString: 'SENTRY_DSN=http://abc@o1.ingest.sentry.io/2');
      expect(AppConfig.sentryDsn, isNull);
    });
  });

  test('with no DSN, reporting does not start', () async {
    dotenv.loadFromString(envString: 'SENTRY_DSN=');
    await ErrorReporting.start();
    expect(ErrorReporting.enabled, isFalse);
  });

  // Guardian tells people nothing it hears leaves the phone, and the app
  // handles people in danger. A report may carry the error and versions only.
  test('a report carries nothing about the person', () {
    final o = SentryFlutterOptions();
    ErrorReporting.configure(o, 'https://abc@o1.ingest.sentry.io/2');
    expect(o.dsn, 'https://abc@o1.ingest.sentry.io/2');
    expect(o.sendDefaultPii, isFalse, reason: 'no user, IP or request bodies');
    expect(o.maxBreadcrumbs, 0,
        reason: 'breadcrumbs carry log lines, alert ids, coordinates, taps');
    expect(o.enablePrintBreadcrumbs, isFalse);
    expect(o.enableAutoNativeBreadcrumbs, isFalse);
    expect(o.enableUserInteractionBreadcrumbs, isFalse);
    expect(o.attachScreenshot, isFalse, reason: 'a screenshot shows the screen');
    expect(o.enableAutoPerformanceTracing, isFalse);
    expect(o.tracesSampleRate, isNull);
  });
}
