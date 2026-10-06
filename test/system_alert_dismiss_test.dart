// "Dismiss this alert" has to dismiss the alert.
//
// The dismissed check sat after the early return for target 'ALL', so a
// statewide advisory — the commonest kind — came straight back the moment it
// was dismissed. The mobile control sweep found the button doing nothing.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/services/user_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpWith(
    WidgetTester tester, {
    required List<Map<String, dynamic>> alerts,
    String role = 'CITIZEN',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemAlertsStreamProvider.overrideWith((ref) => Stream.value(alerts)),
          userProfileProvider.overrideWith((ref) => Stream.value({'role': role})),
        ],
        child: const MaterialApp(
          home: SystemAlertListener(child: Scaffold(body: SizedBox.shrink())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  final statewide = {
    'id': 'a1',
    'target_type': 'ALL',
    'severity': 'CRITICAL',
    'message': 'Curfew from 18:00 in Jos North',
  };

  testWidgets('a statewide advisory goes away when dismissed', (tester) async {
    await pumpWith(tester, alerts: [statewide]);
    expect(find.text('CURFEW FROM 18:00 IN JOS NORTH'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss this alert'));
    await tester.pump();
    expect(find.text('CURFEW FROM 18:00 IN JOS NORTH'), findsNothing);
  });

  testWidgets('HQ can dismiss an advisory too', (tester) async {
    await pumpWith(tester, alerts: [statewide], role: 'HQ_OFFICER');
    await tester.tap(find.byTooltip('Dismiss this alert'));
    await tester.pump();
    expect(find.text('CURFEW FROM 18:00 IN JOS NORTH'), findsNothing);
  });

  testWidgets('dismissing one advisory shows the next, not nothing', (tester) async {
    await pumpWith(tester, alerts: [
      statewide,
      {'id': 'a2', 'target_type': 'ALL', 'severity': 'HIGH', 'message': 'Road closed at Bukuru'},
    ]);
    await tester.tap(find.byTooltip('Dismiss this alert'));
    await tester.pump();
    expect(find.text('CURFEW FROM 18:00 IN JOS NORTH'), findsNothing);
    expect(find.text('ROAD CLOSED AT BUKURU'), findsOneWidget);
  });
}
