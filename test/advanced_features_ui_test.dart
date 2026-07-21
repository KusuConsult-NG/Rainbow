import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rainbow_app/features/agent/mission_resolution_screen.dart';
import 'package:rainbow_app/features/citizen/dispatcher_chat_screen.dart';
import 'package:rainbow_app/providers/firestore_provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:rainbow_app/services/tts_service.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

class FakeUser extends Fake implements firebase_auth.User {
  @override
  final String uid;
  FakeUser({required this.uid});

  @override
  String? get displayName => 'Citizen User';
}

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier() {
    state = AuthState(
      user: FakeUser(uid: 'citizen_123'),
      role: UserRole.citizen,
      isLoading: false,
      hasOnboarded: true,
      profile: {'displayName': 'Citizen User'},
    );
  }

  @override
  void initAuth() {}
}

class FakeDocumentSnapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  final String _id;
  final Map<String, dynamic> _data;

  FakeDocumentSnapshot(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data[field];

  @override
  bool get exists => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SpeechService.instance.useFallback = true;
    TtsService.instance.useFallback = true;
  });

  testWidgets('Responders UI: MissionResolutionScreen renders AAR inputs and dictation widget', (tester) async {
    final mockAlert = FakeDocumentSnapshot('alert_test_123', {
      'type': 'FIRE',
      'description': 'Fire reported near the central market area.',
      'status': 'ON_SITE',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MissionResolutionScreen(alertDoc: mockAlert),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify text inputs and headers are visible
    expect(find.text('AAR NARRATIVE (REQUIRED)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // 2. Verify Speech-to-Text Dictation widget renders in idle state
    expect(find.text('TAP MIC ICON TO DICTATE AFTER-ACTION REPORT'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

    // 3. Trigger Dictation start click
    final micButton = find.byIcon(Icons.mic_none_rounded);
    expect(micButton, findsOneWidget);
    await tester.tap(micButton);
    await tester.pumpAndSettle();

    // 4. Verify visual feedback for active recording
    expect(find.text('DICTATING REPORT... SPEAK NOW'), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record_rounded), findsOneWidget);

    // 5. Await simulated speech transcription delay
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 6. Verify that TextField value has updated dynamically with simulated text
    expect(find.text('Help! Urgent response team needed at my location.'), findsOneWidget);

    // 7. Click to stop dictation
    final stopButton = find.byIcon(Icons.stop_rounded);
    expect(stopButton, findsOneWidget);
    await tester.tap(stopButton);
    await tester.pumpAndSettle();

    // 8. Verify it returns to idle dictation status
    expect(find.text('TAP MIC ICON TO DICTATE AFTER-ACTION REPORT'), findsOneWidget);

    // 9. Settle remaining 3-second simulation timer to prevent pending timer leak errors
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('Responders UI: TtsService triggers audio briefing upon accept', (tester) async {
    String? spokenBrief;
    TtsService.instance.onSpeechBriefing = (text) {
      spokenBrief = text;
    };

    // Trigger synthetic accept voice brief
    await TtsService.instance.speak('Mission accepted. Threat details: Protest in progress.');

    expect(spokenBrief, contains('Mission accepted.'));
    expect(spokenBrief, contains('Protest in progress.'));
  });

  testWidgets('Citizen UI: DispatcherChatScreen renders mic button and toggles dictation', (tester) async {
    final fakeFirestore = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          authProvider.overrideWith((ref) => FakeAuthNotifier()),
        ],
        child: const MaterialApp(
          home: DispatcherChatScreen(alertId: 'alert_123'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify mic button is rendered
    final micButton = find.byIcon(Icons.mic_none_rounded);
    expect(micButton, findsOneWidget);

    // 2. Click mic button to start dictation
    await tester.tap(micButton);
    await tester.pumpAndSettle();

    // 3. Verify it toggles icon to stop
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    // 4. Wait for simulated dictation callback timer (1 second) to fire
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 5. Verify the dictation text is injected into the TextField
    expect(find.text('Help! Urgent response team needed at my location.'), findsOneWidget);

    // 6. Click stop button
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pumpAndSettle();

    // 7. Verify the icon returns to mic
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

    // 8. Drain the remaining 3-second simulation timer to prevent leaks
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
