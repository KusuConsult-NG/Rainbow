// What a responder needs to know, and whether the report carries it.
//
// Every report used to carry the same three things whatever it was about: a
// free-text narrative, optional media, and a place. For a responder that is
// the difference between "Kidnap - Immediate Abduction near Naraguta" and
// knowing whether the people who took them were armed, how long ago it
// happened, and whether they left in a vehicle. The first is a reason to send
// somebody; the second decides who, how many, and how fast.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';

void main() {
  AlertCategoryInfo byLabel(String label) =>
      alertCategories.firstWhere((c) => c.label == label);

  group('the categories that need detail have it', () {
    // Not every category: a cyber crime report is a story, not a set of
    // fields. These are the ones where the answer changes the response.
    for (final label in [
      'Kidnap',
      'Fire',
      'Flood',
      'Domestic violence',
      'Community attack',
      'Child abuse',
      'Cattle rustling',
    ]) {
      test('$label asks what a responder has to know', () {
        expect(byLabel(label).responsePrompts, isNotEmpty);
      });
    }

    test('kidnap asks whether they are armed, when, and how they left', () {
      final questions =
          byLabel('Kidnap').responsePrompts.map((p) => p.question).join(' ');
      expect(questions.toLowerCase(), contains('armed'));
      expect(questions.toLowerCase(), contains('how long ago'));
      expect(questions.toLowerCase(), contains('leave'));
    });
  });

  group('every prompt is answerable in one tap', () {
    test('each has at least two options and no more than five', () {
      for (final category in alertCategories) {
        for (final prompt in category.responsePrompts) {
          expect(
            prompt.options.length,
            inInclusiveRange(2, 5),
            reason: '${category.label} / "${prompt.question}" offers '
                '${prompt.options.length} options. One is not a question; '
                'six does not fit on a phone and is not a tap any more.',
          );
        }
      }
    });

    test('no category asks more than three questions', () {
      for (final category in alertCategories) {
        expect(
          category.responsePrompts.length,
          lessThanOrEqualTo(3),
          reason: '${category.label} asks '
              '${category.responsePrompts.length} questions. This is a '
              'person in trouble, not a form.',
        );
      }
    });

    test('an option is short enough to read on a chip', () {
      for (final category in alertCategories) {
        for (final prompt in category.responsePrompts) {
          for (final option in prompt.options) {
            expect(option.length, lessThanOrEqualTo(24),
                reason: '"$option" in ${category.label} is too long to read '
                    'at a glance');
            expect(option.trim(), option);
            expect(option, isNotEmpty);
          }
        }
      }
    });

    // "Don't know" is not padding. A reporter who cannot see whether the
    // attackers are armed must be able to say so, rather than guessing or
    // leaving it blank — those two look identical to a responder and mean
    // very different things.
    test('a reporter can say they do not know', () {
      for (final label in ['Kidnap', 'Community attack', 'Cattle rustling']) {
        final armed = byLabel(label).responsePrompts.firstWhere(
              (p) => p.question.toLowerCase().contains('armed'),
            );
        expect(
          armed.options.any((o) => o.toLowerCase().contains("don't know")),
          isTrue,
          reason: '$label gives no way to say the reporter cannot tell',
        );
      }
    });
  });
}
