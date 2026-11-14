import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/features/report/report_category_screen.dart';
import 'package:rainbow_app/shared/widgets/evidence_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Situation Report narrows the category list', () {
    test('each situation offers its own categories, never none', () {
      for (final s in situationCategoryLabels.keys) {
        final shown = categoriesForSituation(s);
        expect(shown, isNotEmpty, reason: s);
        expect(shown.length, lessThan(alertCategories.length), reason: s);
      }
    });

    test('every label in the map is a real category', () {
      final real = alertCategories.map((c) => c.label).toSet();
      for (final labels in situationCategoryLabels.values) {
        for (final l in labels) {
          expect(real, contains(l));
        }
      }
    });

    test('every category is reachable from at least one situation', () {
      final reached = situationCategoryLabels.values.expand((l) => l).toSet();
      for (final c in alertCategories) {
        expect(reached, contains(c.label), reason: c.label);
      }
    });

    test('no situation, or an unknown one, shows all twelve', () {
      expect(categoriesForSituation(null), alertCategories);
      expect(categoriesForSituation('nonsense'), alertCategories);
    });

    testWidgets('a civil hazard shows hazards, and SHOW ALL brings back the rest',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ReportCategoryScreen(situation: 'environment'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FLOOD'), findsOneWidget);
      expect(find.text('KIDNAP'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('show_all_categories')));
      await tester.pumpAndSettle();
      expect(find.text('KIDNAP'), findsOneWidget);
      expect(find.byKey(const ValueKey('show_all_categories')), findsNothing);
    });
  });

  group('evidence opens the way its kind needs', () {
    test('kinds are read from the address', () {
      expect(evidenceKindOf('https://res.cloudinary.com/x/video/upload/a.mp4'),
          EvidenceKind.video);
      expect(evidenceKindOf('https://x/clip.MOV'), EvidenceKind.video);
      expect(evidenceKindOf('https://res.cloudinary.com/x/raw/upload/a'),
          EvidenceKind.audio);
      expect(evidenceKindOf('https://x/note.m4a'), EvidenceKind.audio);
      expect(evidenceKindOf('https://x/photo.jpg'), EvidenceKind.photo);
    });

    testWidgets('a video is handed to the phone, and a refusal is said out loud',
        (tester) async {
      final opened = <Uri>[];
      var answer = true;
      openExternallyOverride = (uri) async {
        opened.add(uri);
        return answer;
      };
      addTearDown(() => openExternallyOverride = null);

      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ));

      await openEvidence(ctx, 'https://x/clip.mp4');
      await tester.pump();
      expect(opened.single.toString(), 'https://x/clip.mp4');
      expect(find.byType(SnackBar), findsNothing);

      answer = false;
      await openEvidence(ctx, 'https://x/clip.mp4');
      await tester.pump();
      expect(find.textContaining('could not open the video'), findsOneWidget);
    });
  });
}
