// Volume Down ×3 with the phone locked: the presses the Android accessibility
// service hands over (VolumeSosAccessibilityService.kt) must go through the
// same silent SOS as the in-app presses, once, and only for somebody signed in.
// And the Settings tile must explain the service before opening Android's
// settings, which is the disclosure Google Play requires.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/sos/volume_sos.dart';
import 'package:rainbow_app/features/settings/settings_screen.dart';
import 'package:rainbow_app/features/settings/volume_sos_lock_screen_tile.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _Auth extends AuthNotifier {
  _Auth(AuthState initial) {
    state = initial;
  }

  @override
  void initAuth() {}

  /// The saved session finishing its restore, as [user].
  void restored(User user) =>
      state = AuthState(user: user, role: UserRole.citizen, isLoading: false);
}

class _RecordingEmergency extends EmergencyNotifier {
  static int raised = 0;
  static bool? lastSilent;

  @override
  Future<void> startEmergency({bool silent = false, String? description}) async {
    if (state.isEmergencyActive) return;
    raised++;
    lastSilent = silent;
    state = state.copyWith(isEmergencyActive: true, isSilent: silent);
  }
}

final _user = User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

const _channel = MethodChannel('test/volume_sos');

/// The native side, as Dart sees it.
class _Native {
  int pendingMs = -1;
  bool serviceOn = false;
  final calls = <String>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'takePending':
          final p = pendingMs;
          pendingMs = -1;
          return p;
        case 'isServiceEnabled':
          return serviceOn;
        case 'openAccessibilitySettings':
          return true;
      }
      return null;
    });
  }

  /// The service handing over three presses while the app runs.
  Future<void> press() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(const MethodCall('trigger')),
      (_) {},
    );
  }
}

void main() {
  late _Native native;
  late _Auth auth;

  setUp(() {
    _RecordingEmergency.raised = 0;
    _RecordingEmergency.lastSilent = null;
    native = _Native()..install();
    signInWait = const Duration(seconds: 30);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  Future<void> pump(
    WidgetTester tester, {
    bool signedIn = true,
    bool loading = false,
    bool enabled = true,
    Widget? home,
  }) async {
    SharedPreferences.setMockInitialValues({volumeSosPreferenceKey: enabled});
    auth = _Auth(AuthState(
      user: signedIn ? _user : null,
      role: UserRole.citizen,
      isLoading: loading,
    ));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          emergencyProvider.overrideWith(_RecordingEmergency.new),
          volumeSosLockScreenProvider.overrideWithValue(
            VolumeSosLockScreen(channel: _channel, supported: true),
          ),
        ],
        child: MaterialApp(
          home: VolumeSosListener(child: home ?? const Scaffold(body: Text('screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('presses handed over by the service', () {
    testWidgets('send ONE silent SOS, and change nothing on screen', (tester) async {
      await pump(tester);

      await native.press();
      await tester.pump();
      expect(_RecordingEmergency.raised, 1);
      expect(_RecordingEmergency.lastSilent, isTrue);

      await native.press();
      await tester.pump();
      expect(_RecordingEmergency.raised, 1, reason: 'nothing more during an active SOS');
      expect(find.text('screen'), findsOneWidget);
    });

    testWidgets('send nothing for somebody signed out', (tester) async {
      await pump(tester, signedIn: false);
      await native.press();
      await tester.pump();
      expect(_RecordingEmergency.raised, 0);
    });

    testWidgets('wait for a sign-in still being restored, then send', (tester) async {
      // A cold start from the lock screen: the saved session is still loading.
      await pump(tester, signedIn: false, loading: true);
      await native.press();
      await tester.pump();
      expect(_RecordingEmergency.raised, 0, reason: 'not before the session is back');

      auth.restored(_user);
      await tester.pump();
      expect(_RecordingEmergency.raised, 1);
    });

    testWidgets('give up on a sign-in that never comes back', (tester) async {
      signInWait = const Duration(seconds: 2);
      await pump(tester, signedIn: false, loading: true);
      await native.press();
      await tester.pump(const Duration(seconds: 3));
      expect(_RecordingEmergency.raised, 0);
    });

    testWidgets('do not need the in-app switch to have loaded', (tester) async {
      // The service read the saved setting itself. At a cold start this
      // screen's copy is still loading and reads false; it must not drop the
      // press.
      await pump(tester, enabled: false);
      await native.press();
      await tester.pump();
      expect(_RecordingEmergency.raised, 1);
    });
  });

  group('a press that had to start the app', () {
    testWidgets('is sent once the app is up', (tester) async {
      native.pendingMs = 4000;
      await pump(tester);
      expect(native.calls, contains('takePending'));
      expect(_RecordingEmergency.raised, 1);
      expect(_RecordingEmergency.lastSilent, isTrue);
    });

    testWidgets('is not sent when it is over two minutes old', (tester) async {
      native.pendingMs = const Duration(minutes: 3).inMilliseconds;
      await pump(tester);
      expect(_RecordingEmergency.raised, 0);
    });

    testWidgets('is sent at most once', (tester) async {
      native.pendingMs = 1000;
      await pump(tester);
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(_RecordingEmergency.raised, 1, reason: 'takePending clears it');
    });
  });

  group('the Settings tile', () {
    Widget tile() => const Scaffold(body: VolumeSosLockScreenTile());
    String en(String k) => Translations.get(k, AppLanguage.english);

    testWidgets('with the service off: explains, THEN opens Android settings', (tester) async {
      await pump(tester, home: tile());
      expect(find.text(en('vsos_lock_off')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('volume_sos_set_up_locked')));
      await tester.pumpAndSettle();
      // The disclosure, before anything is opened.
      expect(find.text(en('vsos_disclosure_body')), findsOneWidget);
      expect(native.calls, isNot(contains('openAccessibilitySettings')));

      await tester.tap(find.byKey(const ValueKey('volume_sos_open_accessibility')));
      await tester.pumpAndSettle();
      expect(native.calls, contains('openAccessibilitySettings'));
    });

    testWidgets('NOT NOW opens nothing', (tester) async {
      await pump(tester, home: tile());
      await tester.tap(find.byKey(const ValueKey('volume_sos_set_up_locked')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en('vsos_disclosure_cancel')));
      await tester.pumpAndSettle();
      expect(native.calls, isNot(contains('openAccessibilitySettings')));
    });

    testWidgets('with the service on: says it works locked, and offers nothing to set up',
        (tester) async {
      native.serviceOn = true;
      await pump(tester, home: tile());
      expect(find.text(en('vsos_lock_on')), findsOneWidget);
      expect(find.byKey(const ValueKey('volume_sos_set_up_locked')), findsNothing);
    });

    testWidgets('is not shown while Volume Down ×3 is switched off', (tester) async {
      await pump(tester, enabled: false, home: tile());
      expect(find.byKey(const ValueKey('volume_sos_lock_screen')), findsNothing);
    });

    testWidgets('notices the service being switched on in Android settings', (tester) async {
      await pump(tester, home: tile());
      expect(find.text(en('vsos_lock_off')), findsOneWidget);
      native.serviceOn = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(en('vsos_lock_on')), findsOneWidget);
    });
  });

  group('the Settings switch', () {
    String en(String k) => Translations.get(k, AppLanguage.english);

    // The switch's description ends "it can also work with the phone locked:
    // set that up below", and "below" was empty until the switch was on. So
    // the sentence pointed at nothing, and afterwards the step was a tile to
    // be noticed and a second button to be pressed. A handset with the switch
    // on still did nothing when the screen was locked.
    testWidgets('turning it ON offers the locked-phone step at once',
        (tester) async {
      await pump(tester, enabled: false, home: const SettingsScreen());

      await tester.tap(find.byKey(const ValueKey('volume_sos_toggle')));
      await tester.pumpAndSettle();

      expect(find.text(en('vsos_disclosure_body')), findsOneWidget,
          reason: 'the disclosure the description promised, without hunting');
      expect(native.calls, isNot(contains('openAccessibilitySettings')),
          reason: 'nothing is opened before it has been explained');

      await tester.tap(find.byKey(const ValueKey('volume_sos_open_accessibility')));
      await tester.pumpAndSettle();
      expect(native.calls, contains('openAccessibilitySettings'));
    });

    testWidgets('NOT NOW leaves the switch on and opens nothing',
        (tester) async {
      await pump(tester, enabled: false, home: const SettingsScreen());
      await tester.tap(find.byKey(const ValueKey('volume_sos_toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(en('vsos_disclosure_cancel')));
      await tester.pumpAndSettle();

      expect(native.calls, isNot(contains('openAccessibilitySettings')));
      // In-app Volume Down ×3 still works; only the locked-phone half is
      // unset, and the tile below is the way back to it.
      final toggle =
          tester.widget<SwitchListTile>(find.byKey(const ValueKey('volume_sos_toggle')));
      expect(toggle.value, isTrue);
      expect(find.byKey(const ValueKey('volume_sos_set_up_locked')), findsOneWidget);
    });

    testWidgets('asks nothing when the service is already on', (tester) async {
      native.serviceOn = true;
      await pump(tester, enabled: false, home: const SettingsScreen());

      await tester.tap(find.byKey(const ValueKey('volume_sos_toggle')));
      await tester.pumpAndSettle();

      expect(find.text(en('vsos_disclosure_body')), findsNothing);
      expect(find.text(en('vsos_lock_on')), findsOneWidget);
    });

    testWidgets('turning it OFF asks nothing', (tester) async {
      await pump(tester, home: const SettingsScreen());

      await tester.tap(find.byKey(const ValueKey('volume_sos_toggle')));
      await tester.pumpAndSettle();

      expect(find.text(en('vsos_disclosure_body')), findsNothing);
      expect(native.calls, isNot(contains('openAccessibilitySettings')));
    });

    // Three quick presses of Volume Down is also how a person turns the
    // volume down. Defaulting this on would send silent alerts from pockets.
    test('is off until somebody turns it on', () async {
      SharedPreferences.setMockInitialValues({});
      expect(VolumeSosSetting().state, isFalse);
    });
  });

  test('off Android there is no service, and nothing is called', () async {
    final lock = VolumeSosLockScreen(channel: _channel, supported: false);
    expect(await lock.isServiceEnabled(), isFalse);
    expect(await lock.takePending(), isNull);
    expect(await lock.openSettings(), isFalse);
    expect(native.calls, isEmpty);
  });
}
