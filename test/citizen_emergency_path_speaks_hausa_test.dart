// The screens a citizen walks through while something is happening must speak
// the language they chose.
//
// The picker worked, persisted to SharedPreferences and was reachable from two
// places. And then every screen past the home screen spoke English anyway,
// because only five files in the whole app asked the translation table for
// anything: the picker itself, the home screen, the voice dialog, the category
// list and the dispatcher chat. A citizen who selected HAUSA got a Hausa home
// screen and an English emergency.
//
// These tests pump each screen with the language set and assert on the STRING
// ON SCREEN, not on the table. A key defined and never used reads as coverage
// in `check_translation_keys.py` while the screen shows English.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/report/report_initial_screen.dart';
import 'package:rainbow_app/features/report/report_success_screen.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, Widget screen,
    AppLanguage lang) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(languageProvider.notifier).setLanguage(lang);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the situation chooser', () {
    testWidgets('asks the question in Hausa', (tester) async {
      await _pump(tester, const ReportInitialScreen(), AppLanguage.hausa);

      expect(find.text('Mene ne\nya faru?'), findsOneWidget);
      expect(find.text('What is the\nsituation?'), findsNothing);
    });

    testWidgets('names every category in Hausa', (tester) async {
      await _pump(tester, const ReportInitialScreen(), AppLanguage.hausa);

      // All four, because a citizen choosing between them under pressure needs
      // all four — a half-translated list is the worst of both.
      expect(find.text('HATSARI GA RAI'), findsOneWidget);
      expect(find.text('AIKIN LAIFI'), findsOneWidget);
      expect(find.text('ABU MAI TUHUMA'), findsOneWidget);
      expect(find.text("HATSARIN JAMA'A"), findsOneWidget);
      expect(find.text('THREAT TO LIFE'), findsNothing);
      expect(find.text('CIVIL HAZARD'), findsNothing);
    });

    testWidgets('speaks Pidgin when Pidgin is chosen', (tester) async {
      await _pump(tester, const ReportInitialScreen(), AppLanguage.pidgin);

      expect(find.text('Wetin dey\nhappen?'), findsOneWidget);
      expect(find.text('DANGER TO LIFE'), findsOneWidget);
    });

    testWidgets('still reads English when English is chosen', (tester) async {
      // The point is the citizen's choice, not replacing one default with
      // another.
      await _pump(tester, const ReportInitialScreen(), AppLanguage.english);

      expect(find.text('What is the\nsituation?'), findsOneWidget);
      expect(find.text('THREAT TO LIFE'), findsOneWidget);
    });
  });

  group('the confirmation screen', () {
    testWidgets('says a queued report is queued, in Hausa', (tester) async {
      // The offline branch matters more than the online one: a citizen with no
      // signal is being told their report is NOT yet sent, and that sentence
      // has to be one they can read.
      await _pump(
        tester,
        const ReportSuccessScreen(
          alertId: 'a1b2c3d4',
          isOffline: true,
          reportType: 'THREAT TO LIFE',
        ),
        AppLanguage.hausa,
      );

      expect(find.text('AN AJIYE RAHOTO A WAYA'), findsOneWidget);
      expect(find.text('REPORT QUEUED LOCALLY'), findsNothing);
    });

    testWidgets('says a transmitted report was received, in Hausa',
        (tester) async {
      await _pump(
        tester,
        const ReportSuccessScreen(
          alertId: 'a1b2c3d4',
          isOffline: false,
          reportType: 'THREAT TO LIFE',
        ),
        AppLanguage.hausa,
      );

      expect(find.text('AN TURA RAHOTO'), findsOneWidget);
      expect(find.text('CIBIYAR UMARNI TA KARBA'), findsOneWidget);
    });
  });

  group('the table itself', () {
    test('every key the emergency path asks for has all three languages', () {
      // `get()` falls back to English for a missing language, which is right
      // for a reader and wrong for a test: it would make a half-translated key
      // pass. So this asks the table which languages a key actually has.
      final paths = Translations.keys
          .where((k) => k.startsWith('rpt_') || k.startsWith('eme_'));
      expect(paths, isNotEmpty);
      for (final key in paths) {
        expect(
          Translations.languagesFor(key).toSet(),
          AppLanguage.values.toSet(),
          reason: '$key is missing a language',
        );
      }
    });

    test('no status value from the database is in the table', () {
      // 'DISPATCHED', 'ON_ROUTE' and the rest look like labels on the SOS
      // screen and are DATA — compared by string against alerts.status.
      // Translating one would leave a citizen reading LOCATION BROADCASTING
      // with a squad beside them.
      const statuses = [
        'PENDING', 'DISPATCHED', 'ACKNOWLEDGED', 'ON_ROUTE', 'ON_SITE',
        'RESOLVED',
      ];
      for (final lang in AppLanguage.values) {
        for (final key in Translations.keys) {
          expect(statuses.contains(Translations.get(key, lang)), isFalse,
              reason: '$key returns the status value '
                  '"${Translations.get(key, lang)}" in ${lang.code} — a '
                  'status is data, not a label');
        }
      }
    });
  });
}
