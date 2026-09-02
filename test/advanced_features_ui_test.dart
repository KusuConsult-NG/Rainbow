import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/mission_resolution_screen.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:rainbow_app/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SpeechService.instance.useFallback = true;
    TtsService.instance.useFallback = true;
  });

  testWidgets('Responders UI: MissionResolutionScreen renders debrief form', (tester) async {
    final mockAlert = {
      'id': 'alert_test_123',
      'type': 'FIRE',
      'description': 'Fire reported near the central market area.',
      'status': 'ON_SITE',
    };

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: MissionResolutionScreen(alertData: mockAlert),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('RESOLUTION NOTES & AFTER-ACTION DEBRIEF'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('MARK MISSION AS RESOLVED'), findsOneWidget);
  });

  testWidgets('Responders UI: TtsService triggers audio briefing upon accept', (tester) async {
    String? spokenBrief;
    TtsService.instance.onSpeechBriefing = (text) {
      spokenBrief = text;
    };

    await TtsService.instance.speak('Mission accepted. Threat details: Protest in progress.');

    expect(spokenBrief, contains('Mission accepted.'));
    expect(spokenBrief, contains('Protest in progress.'));
  });
}
