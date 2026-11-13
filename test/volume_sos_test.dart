import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/sos/volume_sos.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(AuthState initial) {
    state = initial;
  }

  @override
  void initAuth() {}
}

/// Records whether the SOS was raised, without touching GPS or the network.
class _RecordingEmergency extends EmergencyNotifier {
  static int raised = 0;
  static bool? lastSilent;

  @override
  Future<void> startEmergency({bool silent = false}) async {
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

void main() {
  setUp(() {
    _RecordingEmergency.raised = 0;
    _RecordingEmergency.lastSilent = null;
  });

  Future<void> pumpWith(
    WidgetTester tester, {
    required bool enabled,
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues({volumeSosPreferenceKey: enabled});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(
              AuthState(
                user: signedIn ? _user : null,
                role: UserRole.citizen,
                isLoading: false,
              ),
            ),
          ),
          emergencyProvider.overrideWith(_RecordingEmergency.new),
        ],
        child: const MaterialApp(
          home: VolumeSosListener(child: Scaffold(body: Text('screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('switched on: three presses send ONE silent SOS', (tester) async {
    await pumpWith(tester, enabled: true);

    await press(tester, 2);
    expect(_RecordingEmergency.raised, 0, reason: 'two presses send nothing');

    await press(tester);
    expect(_RecordingEmergency.raised, 1);
    expect(_RecordingEmergency.lastSilent, isTrue);

    await press(tester, 6);
    expect(_RecordingEmergency.raised, 1,
        reason: 'presses during an active SOS file nothing more');
    expect(find.text('screen'), findsOneWidget,
        reason: 'the screen does not change');
  });

  testWidgets('off by default: three presses send nothing', (tester) async {
    await pumpWith(tester, enabled: false);
    await press(tester, 3);
    expect(_RecordingEmergency.raised, 0);
  });

  testWidgets('signed out: three presses send nothing', (tester) async {
    await pumpWith(tester, enabled: true, signedIn: false);
    await press(tester, 3);
    expect(_RecordingEmergency.raised, 0);
  });

  testWidgets('Volume Up does not count', (tester) async {
    await pumpWith(tester, enabled: true);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(_RecordingEmergency.raised, 0);
  });
}
