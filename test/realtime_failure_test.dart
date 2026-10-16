// A handset that cannot reach the backend must still have an app.
//
// `AsyncError.value` RETHROWS the error it holds
// (riverpod-2.6.1/lib/src/common.dart:493-498) — it is not the
// null-returning getter its name suggests. `SystemAlertListener` read
// `ref.watch(userProfileProvider).value` in its `build`, and that widget
// wraps EVERY screen through `MaterialApp.builder`.
//
// `userProfileProvider` is a realtime stream on `profiles`. So for a
// SIGNED-IN user whose handset could not reach Supabase — no DNS, no data, a
// dropped socket — the error rethrew out of the build of the widget wrapping
// the whole app. In a release build that paints a featureless pale rectangle,
// which is exactly what was reported from a real device:
//
//   RealtimeSubscribeException(status: channelError, details:
//   WebSocketChannelException: SocketException: Failed host lookup:
//   '<project>.supabase.co' (OS Error: No address associated with hostname,
//   errno = 7))
//
// This app carries an offline queue, an encrypted SMS fallback and a
// Bluetooth mesh so that losing the network is survivable. Losing it must not
// be the thing that kills the UI.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/app.dart';
import 'package:rainbow_app/features/auth/login_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/core/models/broadcast_alert.dart';
import 'package:rainbow_app/services/broadcast_service.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/services/update_service.dart';
import 'package:rainbow_app/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePush implements PushNotificationService {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  Future<void> initialize() async {}
}

class _FakeSync implements SyncService {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  void initialize() {}
  @override
  ValueNotifier<bool> get isSyncing => ValueNotifier<bool>(false);
}

class _FakeUpdate implements UpdateService {
  @override
  dynamic noSuchMethod(Invocation i) => null;
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

class _FakeAuth extends AuthNotifier {
  _FakeAuth(AuthState s) {
    state = s;
  }
  @override
  void initAuth() {}
}

/// The shape of a realtime channel that could not be reached.
class _Unreachable implements Exception {
  @override
  String toString() =>
      'RealtimeSubscribeException(status: channelError, details: '
      'SocketException: Failed host lookup, errno = 7)';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget boot() => ProviderScope(
        overrides: [
          // Signed in — which is what makes `userProfileProvider` subscribe at
          // all. Signed out it returns `Stream.value(null)` and never errors,
          // which is why this never showed up on a login screen.
          authProvider.overrideWith(
            (ref) => _FakeAuth(AuthState(isLoading: false)),
          ),
          // The backend is unreachable.
          userProfileProvider.overrideWith(
            (ref) => Stream<Map<String, dynamic>?>.error(_Unreachable()),
          ),
          broadcastProvider.overrideWith(
            (ref) => Stream<List<BroadcastAlert>>.error(_Unreachable()),
          ),
          pushNotificationServiceProvider.overrideWithValue(_FakePush()),
          syncServiceProvider.overrideWithValue(_FakeSync()),
          updateServiceProvider.overrideWithValue(_FakeUpdate()),
          splashFinishedProvider.overrideWith((ref) => true),
        ],
        child: const RainbowApp(),
      );

  testWidgets('an unreachable backend does not take the app down',
      (tester) async {
    await tester.pumpWidget(boot());
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a realtime failure rethrown out of the build of the widget '
          'wrapping every screen is a pale rectangle on a release handset',
    );

    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 800));
    }

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'still standing after the timers that drive start-up',
    );
  });

  testWidgets('and the app is still usable, not merely alive', (tester) async {
    await tester.pumpWidget(boot());
    await tester.pump();
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 800));
    }

    // An authenticated user whose role never resolved lands on the login
    // screen rather than on nothing. The point is that a screen renders.
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
