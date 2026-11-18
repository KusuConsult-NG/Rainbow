// The citizen screens converted on 2026-11-17 read the language chosen, and
// change when it changes.
//
// Twelve screens on the citizen's path still spoke English whatever was chosen
// (scripts/check_citizen_screens_speak_the_language.py). These pump some of
// them and assert on the STRING ON SCREEN, as
// citizen_emergency_path_speaks_hausa_test.dart does for the emergency path:
// a key defined and never read passes every table check.
//
// The converted screens read their text through a `_t` helper that calls
// `ref.read`, with `ref.watch(languageProvider)` in build so they redraw. The
// last test changes the language AFTER the screen is up, which is the one
// thing that pattern could get wrong.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/settings/emergency_pin_screen.dart';
import 'package:rainbow_app/features/settings/uninstall_request_screen.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget screen,
  AppLanguage lang,
) async {
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

String _ha(String key) => Translations.get(key, AppLanguage.hausa);
String _pcm(String key) => Translations.get(key, AppLanguage.pidgin);
String _en(String key) => Translations.get(key, AppLanguage.english);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the emergency PIN screen', () {
    testWidgets('explains the safe PIN in Hausa', (tester) async {
      await _pump(tester, const EmergencyPinScreen(), AppLanguage.hausa);

      expect(find.text(_ha('pin_title')), findsOneWidget);
      expect(find.text(_ha('pin_choose_safe')), findsOneWidget);
      expect(find.text(_ha('pin_safe_hint')), findsOneWidget);
      expect(find.text(_ha('pin_continue')), findsOneWidget);
      expect(find.text('Choose your SAFE PIN'), findsNothing);
      expect(find.text('Mataki na 1 cikin 4'), findsOneWidget);
    });

    testWidgets('speaks Pidgin when Pidgin is chosen', (tester) async {
      await _pump(tester, const EmergencyPinScreen(), AppLanguage.pidgin);

      expect(find.text(_pcm('pin_safe_hint')), findsOneWidget);
      expect(find.text('Step 1 of 4'), findsOneWidget);
    });

    testWidgets('still reads English when English is chosen', (tester) async {
      await _pump(tester, const EmergencyPinScreen(), AppLanguage.english);

      expect(find.text('Choose your SAFE PIN'), findsOneWidget);
      expect(
        find.text('Enter this to cancel an SOS normally. 4–8 digits.'),
        findsOneWidget,
      );
      expect(find.text('Step 1 of 4'), findsOneWidget);
    });

    testWidgets('says a too-short PIN is too short, in Hausa', (tester) async {
      // The error path reads the language in a callback, not in build.
      await _pump(tester, const EmergencyPinScreen(), AppLanguage.hausa);

      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text(_ha('pin_continue')));
      await tester.pump();

      expect(find.text(_ha('pin_err_length')), findsOneWidget);
      expect(find.text('Use 4 to 8 digits.'), findsNothing);
    });
  });

  group('the app removal request', () {
    testWidgets('is titled in Hausa', (tester) async {
      await _pump(tester, const UninstallRequestScreen(), AppLanguage.hausa);

      expect(find.text(_ha('uninst_title')), findsOneWidget);
      expect(find.text(_ha('uninst_category')), findsOneWidget);
      expect(find.text(_ha('uninst_submit')), findsOneWidget);
      expect(find.text('APP REMOVAL AUTHORIZATION'), findsNothing);
    });

    testWidgets('shows the chosen reason in Hausa', (tester) async {
      // The VALUE stored stays 'TRANSFER'; only what is shown is translated.
      await _pump(tester, const UninstallRequestScreen(), AppLanguage.hausa);

      expect(find.text(_ha('uninst_transfer')), findsOneWidget);
      expect(find.text('Transfer to Another Unit'), findsNothing);
    });
  });

  testWidgets('a screen already up changes when the language does',
      (tester) async {
    final container =
        await _pump(tester, const EmergencyPinScreen(), AppLanguage.english);
    expect(find.text(_en('pin_choose_safe')), findsOneWidget);

    await container
        .read(languageProvider.notifier)
        .setLanguage(AppLanguage.hausa);
    await tester.pump();

    expect(find.text(_ha('pin_choose_safe')), findsOneWidget);
    expect(find.text(_en('pin_choose_safe')), findsNothing);
  });

  test('every draft key has all three languages, and differs where it should',
      () {
    // A draft whose Hausa is just the English again is not a draft: it is the
    // gap this work closed, still open. A few are the same on purpose (a
    // product name, AES-256); none of those is a sentence.
    const sentences = [
      'pin_safe_hint',
      'pin_duress_hint',
      'pin_err_mismatch',
      'pin_save_failed',
      'onb_perm_location_refused',
      'onb_perm_privacy',
      'set_relay_desc',
      'set_lock_desc',
      'home_location_required_body',
      'chat_not_sent',
    ];
    for (final key in sentences) {
      expect(Translations.languagesFor(key).toSet(), AppLanguage.values.toSet(),
          reason: key);
      expect(_ha(key), isNot(_en(key)), reason: '$key Hausa');
      expect(_pcm(key), isNot(_en(key)), reason: '$key Pidgin');
    }
  });
}
