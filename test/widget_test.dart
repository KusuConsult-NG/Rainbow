// App boot smoke test.
//
// This was `skip: true` — the only test asserting the app starts at all never
// ran (audit finding M-1). It was skipped because pumping RainbowApp reaches
// AuthNotifier.initAuth(), which subscribes to Supabase auth before
// Supabase.initialize() has been called, and RainbowApp.initState() touches the
// push-notification and sync services.
//
// All three are injectable, so the test now runs against the REAL app shell:
// the real MaterialApp.router, the real GoRouter with the real redirect rules,
// and the real UpdateCheckListener/SystemAlertListener wrappers.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/app.dart';
import 'package:rainbow_app/features/auth/login_screen.dart';
import 'package:rainbow_app/features/splash/splash_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePushNotificationService implements PushNotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<void> initialize() async {}
}

class FakeSyncService implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void initialize() {}
  @override
  ValueNotifier<bool> get isSyncing => ValueNotifier<bool>(false);
}

/// Skips the real Supabase auth subscription; state is supplied directly.
class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier(AuthState initialState) {
    state = initialState;
  }
  @override
  void initAuth() {}
}

Widget _bootApp({required AuthState auth, required bool splashFinished}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => FakeAuthNotifier(auth)),
      pushNotificationServiceProvider
          .overrideWithValue(FakePushNotificationService()),
      syncServiceProvider.overrideWithValue(FakeSyncService()),
      splashFinishedProvider.overrideWith((ref) => splashFinished),
    ],
    child: const RainbowApp(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // Note: pump(), never pumpAndSettle(). SplashScreen runs a repeating pulse
  // animation, so pumpAndSettle would never return.
  testWidgets('app boots without throwing', (tester) async {
    await tester.pumpWidget(
      _bootApp(auth: AuthState(isLoading: true), splashFinished: false),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Exercises the real GoRouter redirect wiring end to end, rather than calling
  // computeRedirect directly as test/router_redirect_test.dart does. Asserts on
  // what actually rendered — an unauthenticated boot must reach the login screen.
  testWidgets('an unauthenticated boot lands on the login screen',
      (tester) async {
    await tester.pumpWidget(
      _bootApp(auth: AuthState(isLoading: false), splashFinished: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
