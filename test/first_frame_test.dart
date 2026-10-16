// THE BLANK PAGE.
//
// An installed release APK opened to a featureless pale page and stopped
// there. The mechanism, from the SDK source rather than from guesswork:
//
//   1. `main()` caught a `SupabaseConfig.init()` failure, logged it, and
//      called `runApp` anyway.
//   2. `RainbowApp.build` watches `appRouter`, whose body builds
//      `RouterNotifier`, whose constructor `listen`s to `authProvider`, which
//      constructs `AuthNotifier`, whose constructor calls `initAuth()`, which
//      reached `SupabaseConfig.client` — all synchronously, inside the app's
//      FIRST build.
//   3. `Supabase.instance` guards itself with an `assert`, which a release
//      build strips, and `Supabase.client` is a `late` field — so in release
//      that line threw `LateInitializationError`.
//   4. A throw during `build()` hands the frame to `ErrorWidget.builder`,
//      whose default composes its message inside `assert(() { ... }())`. In
//      release the message is therefore empty, `RenderErrorBox` builds no
//      paragraph, and all it paints is its background colour: pale grey.
//
// So the app's own start-up failure wore no message at all. Every test here
// fails against the code as it was.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/app.dart';
import 'package:rainbow_app/core/startup/startup_failure.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/features/auth/login_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/services/update_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePush implements PushNotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<void> initialize() async {}
}

class _FakeSync implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void initialize() {}
  @override
  ValueNotifier<bool> get isSyncing => ValueNotifier<bool>(false);
}

class _FakeUpdate implements UpdateService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<UpdateInfo> checkForUpdates() async => UpdateInfo(
        hasUpdate: false,
        isForceUpdate: false,
        updateUrl: '',
        latestVersion: '1.0.0',
      );
  @override
  Future<UpdateInfo> checkAppVersion() async => checkForUpdates();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // No client, and no stand-in for one. This is a handset on which
    // `SupabaseConfig.init()` failed.
    SupabaseConfig.clientOverride = null;
  });

  // Note what this test does NOT override: `authProvider`. The existing boot
  // smoke test in `widget_test.dart` replaces `AuthNotifier` with one whose
  // `initAuth()` does nothing — the exact line that killed the release APK —
  // and its own comment says so. So the app had a passing "app boots" test
  // and no test of the way it actually boots.
  testWidgets(
    'the app still renders a usable screen when Supabase never initialized',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushNotificationServiceProvider.overrideWithValue(_FakePush()),
            syncServiceProvider.overrideWithValue(_FakeSync()),
            updateServiceProvider.overrideWithValue(_FakeUpdate()),
            splashFinishedProvider.overrideWith((ref) => true),
          ],
          child: const RainbowApp(),
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a missing backend client must not throw out of a build — in '
            'release that paints a pale rectangle with no text on it',
      );
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 800));
      }
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  test('the auth notifier reports a missing client instead of throwing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(authProvider);
    expect(state.isLoading, isFalse);
    expect(state.resolutionError, isNotNull);
    expect(state.resolutionError, contains('auth-unavailable'));
  });

  test('SupabaseConfig.client names the problem when it has none', () {
    expect(SupabaseConfig.isInitialized, isFalse);
    expect(
      () => SupabaseConfig.client,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Supabase is not initialized'),
        ),
      ),
      reason: 'the stock getter throws LateInitializationError in release, '
          'because the assert that would have explained it is stripped',
    );
  });

  testWidgets('the installed error widget carries its own text', (tester) async {
    // `flutter_test` fails any test that leaves `ErrorWidget.builder`
    // changed, and it checks before tear-downs run — so this is put back by
    // hand, immediately, rather than with `addTearDown`.
    final previous = ErrorWidget.builder;
    installReadableErrorWidget();
    final widget = ErrorWidget.builder(
      FlutterErrorDetails(exception: StateError('a deliberate failure')),
    );
    ErrorWidget.builder = previous;

    // The stock builder returns an ErrorWidget whose message is composed
    // inside an assert, so in release it renders a blank pale box. The
    // replacement must not be that widget, and must not depend on an assert
    // for its text.
    expect(widget, isA<StartupFailureScreen>());

    await tester.pumpWidget(widget);
    expect(
      find.text(Translations.get('startup_failed_title', AppLanguage.english)),
      findsOneWidget,
    );
    expect(find.textContaining('a deliberate failure'), findsOneWidget);
  });

  testWidgets('the failure screen offers a retry when one can help',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(
      StartupFailureScreen(
        error: StateError('no client'),
        stage: 'connecting to the Plateau Eye service',
        onRetry: () => retried = true,
      ),
    );

    final retry =
        find.text(Translations.get('startup_failed_retry', AppLanguage.english));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    expect(retried, isTrue);
  });

  testWidgets('the failure screen speaks all three languages', (tester) async {
    await tester.pumpWidget(
      StartupFailureScreen(
        error: StateError('no client'),
        stage: 'starting up',
      ),
    );

    for (final language in AppLanguage.values) {
      final title = Translations.get('startup_failed_title', language);
      expect(
        find.textContaining(title),
        findsAtLeastNWidgets(1),
        reason: 'a user who reads only ${language.label} gets nothing from a '
            'blank page either',
      );
    }
  });

  test('a failing start-up step cannot stop start-up', () async {
    var reached = false;
    await runStartupStep('a step that throws', () async {
      throw StateError('plugin not registered');
    });
    await runStartupStep('the step after it', () async => reached = true);
    expect(
      reached,
      isTrue,
      reason: 'these ran as bare statements before runApp, so a throw from '
          'any of them meant no Flutter frame was ever produced',
    );
  });
}
