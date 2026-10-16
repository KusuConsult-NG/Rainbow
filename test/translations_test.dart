// What the app says, and in which language.
//
// The Settings screen's "App Language" dropdown was bound to a private string
// and written to SharedPreferences as `app_language` = 'HA', while every
// translated string in the app watches `languageProvider` from
// shared/localization/translations.dart, which stores `app_lang` = 'ha'. Two
// providers, both called `languageProvider`, both with a class called
// `LanguageNotifier`. Choosing Hausa in Settings changed nothing.
//
// And `get()` returned the KEY on a miss, so the citizen's emergency chat
// header read `live_dispatch_channel` in every language.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/language_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('the table', () {
    test('every language the app offers has every key', () {
      for (final key in Translations.keys) {
        final langs = Translations.languagesFor(key).toSet();
        for (final lang in AppLanguage.values) {
          expect(langs.contains(lang), isTrue,
              reason: '$key has no ${lang.label} string');
        }
      }
    });

    test('the keys the dispatcher chat asks for exist', () {
      // These two were asked for and never defined. The header rendered the
      // key names to a citizen in an emergency.
      for (final key in ['live_dispatch_channel', 'alert_ref']) {
        expect(Translations.keys.contains(key), isTrue, reason: key);
        expect(Translations.get(key, AppLanguage.hausa), isNot(key));
        expect(Translations.get(key, AppLanguage.english), isNot(key));
      }
    });

    test('Hausa is not a copy of English', () {
      // A table that falls back silently can look complete while saying
      // nothing. At least the emergency strings must differ.
      for (final key in ['sos_button', 'silent_sos', 'report_incident']) {
        expect(
          Translations.get(key, AppLanguage.hausa),
          isNot(Translations.get(key, AppLanguage.english)),
          reason: key,
        );
      }
    });
  });

  group('a missing string', () {
    test('falls back to English rather than to the key name', () {
      // A key added in English only should read as English, not as a variable.
      expect(Translations.get('sos_button', AppLanguage.pidgin), isNotEmpty);
      expect(Translations.get('sos_button', AppLanguage.pidgin),
          isNot('sos_button'));
    });

    test('an undefined key is returned as itself, loudly', () {
      // Last resort, and the CI check is what stops one shipping.
      expect(Translations.get('no_such_key_at_all', AppLanguage.english),
          'no_such_key_at_all');
    });
  });

  group('the picker', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('offers every language the app has, not two of three',
        (tester) async {
      // The dropdown it replaced listed English and Hausa. Pidgin was in the
      // enum, in the table, and on no control in Settings.
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: LanguagePicker())),
      ));
      await tester.pumpAndSettle();

      for (final lang in AppLanguage.values) {
        expect(find.text(lang.label), findsOneWidget,
            reason: '${lang.label} is not on the picker');
      }
    });

    testWidgets('changing it changes what the rest of the app reads',
        (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            capturedRef = ref;
            return const Scaffold(body: LanguagePicker());
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(capturedRef.read(languageProvider), AppLanguage.english);

      await tester.tap(find.text('Hausa'));
      await tester.pumpAndSettle();

      // The provider every translated string watches, not a private field.
      expect(capturedRef.read(languageProvider), AppLanguage.hausa);
      // And it is persisted under the key the table reads.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_lang'), 'ha');
    });

    testWidgets('each chip is named for its language, not its flag',
        (tester) async {
      // `check_control_labels.py` exists because controls here had empty
      // accessible names. An emoji is not a name.
      // Before the pump: the semantics tree is not built otherwise, and the
      // assertion below would fail for the wrong reason.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: LanguagePicker())),
      ));
      await tester.pumpAndSettle();

      for (final lang in AppLanguage.values) {
        expect(
          find.bySemanticsLabel(lang.label),
          findsAtLeastNWidgets(1),
          reason: '${lang.label} has no accessible name',
        );
      }
      handle.dispose();
    });

    testWidgets('the chip for the current language says it is the chosen one',
        (tester) async {
      // ONE node with all of it: the button role, the name, the selection and
      // the tap. The first version split those across two nodes — the InkWell
      // outside carried the role and the tap, the Semantics inside the name and
      // the selection — and the consequence was not academic. Pressing the
      // chip for the language already in use is MEANT to do nothing: the
      // provider's state does not change and nothing rebuilds. Anything reading
      // the node it is about to press (a screen reader, the browser harness's
      // dead-control sweep) saw a button with no selection state and a press
      // that changed nothing, which is indistinguishable from a broken
      // control. It was reported as one.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: LanguagePicker())),
      ));
      await tester.pumpAndSettle();

      // `containsSemantics`, not `matchesSemantics`: the latter asserts every
      // property it was NOT given is absent, and an InkWell brings its own
      // (focusable, enabled). The claim here is about four facts being on ONE
      // node, not about the node having nothing else.
      expect(
        tester.getSemantics(find.bySemanticsLabel('English')),
        isSemantics(
          label: 'English',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
        reason: 'the button role, the name, the selection and the tap are not '
            'all on the node that carries the name',
      );

      // And the other two say they are NOT the chosen one, on the same node.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Hausa')),
        isSemantics(
          label: 'Hausa',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );

      handle.dispose();
    });
  });
}
