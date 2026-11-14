import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/guardian/distress_detector.dart';

void main() {
  final t0 = DateTime(2026, 11, 14, 20);

  GuardianMatch? once(String text, {String? secret}) =>
      DistressDetector(secretPhrase: secret).hear(text, t0, isFinal: true);

  group('the examples in the assessment', () {
    test('"Help me, they\'re trying to kill me!" sends', () {
      expect(once("Help me, they're trying to kill me!"),
          const GuardianMatch(GuardianTrigger.distressPhrase, 'threat_to_life'));
    });

    test('"They have a gun. Please don\'t shoot!" sends', () {
      expect(once("They have a gun. Please don't shoot!"),
          const GuardianMatch(GuardianTrigger.distressPhrase, 'weapon_plea'));
    });

    test('"They\'re kidnapping me!" sends', () {
      expect(once("They're kidnapping me!"),
          const GuardianMatch(GuardianTrigger.distressPhrase, 'abduction'));
    });

    test('"Please leave me alone!" once does not send', () {
      expect(once('Please leave me alone!'), isNull);
    });

    test('"The movie was about a kidnapping." does not send', () {
      expect(once('The movie was about a kidnapping.'), isNull);
    });

    test('the secret phrase sends', () {
      expect(once('I think the mangoes are ripe today', secret: 'The mangoes are ripe'),
          const GuardianMatch(GuardianTrigger.secretPhrase, 'secret_phrase'));
    });
  });

  group('strong rules', () {
    for (final s in [
      "don't kill me",
      'no no please dont shoot me',
      'he is stabbing me',
      "I'm being kidnapped",
      'we have been abducted',
      'they are going to shoot me',
      'he has a knife help me',
    ]) {
      test('"$s" sends', () => expect(once(s), isNotNull));
    }
  });

  group('things that must not send', () {
    for (final s in [
      'help',
      'can you help me with this bag',
      'nobody is kidnapping me relax',
      'they are not trying to kill me',
      'please pass the knife',
      'I saw it on the news, they were kidnapping people',
      'he said they wanted to kill me, the joker',
      'the gun show is on Saturday',
      'kill the engine',
      '',
    ]) {
      test('"$s" does not send', () => expect(once(s), isNull));
    }
  });

  group('repeated pleas', () {
    test('two pleas within two minutes send', () {
      final d = DistressDetector();
      expect(d.hear('leave me alone', t0, isFinal: true), isNull);
      expect(
        d.hear('let me go', t0.add(const Duration(seconds: 90)), isFinal: true),
        const GuardianMatch(GuardianTrigger.distressPhrase, 'repeated_plea'),
      );
    });

    test('two everyday requests for help do not', () {
      final d = DistressDetector();
      expect(d.hear('can you help me with this bag', t0, isFinal: true), isNull);
      expect(d.hear('help me carry it', t0.add(const Duration(seconds: 20)), isFinal: true), isNull);
    });

    test('two pleas further apart do not', () {
      final d = DistressDetector();
      expect(d.hear('leave me alone', t0, isFinal: true), isNull);
      expect(d.hear('let me go', t0.add(const Duration(minutes: 3)), isFinal: true), isNull);
    });

    test('partial reports of one utterance count once', () {
      final d = DistressDetector();
      expect(d.hear('leave me', t0, isFinal: false), isNull);
      expect(d.hear('leave me alone', t0, isFinal: false), isNull);
      expect(d.hear('leave me alone', t0, isFinal: true), isNull);
      // Only one plea has been counted; a non-plea does not complete it.
      expect(d.hear('ok', t0.add(const Duration(seconds: 5)), isFinal: true), isNull);
    });

    test('reset forgets a counted plea', () {
      final d = DistressDetector();
      d.hear('leave me alone', t0, isFinal: true);
      d.reset();
      expect(d.hear('let me go', t0.add(const Duration(seconds: 10)), isFinal: true), isNull);
    });
  });

  test('a strong rule fires on a partial report, before the utterance ends', () {
    final d = DistressDetector();
    expect(d.hear('help they are trying to kill me', t0, isFinal: false), isNotNull);
  });

  test('the secret phrase is matched on whole words only', () {
    expect(once('the mangoes are ripened', secret: 'the mangoes are ripe'), isNull);
  });

  group('choosing a secret phrase', () {
    test('needs three words', () {
      expect(DistressDetector.checkSecretPhrase('red mango'), SecretPhraseProblem.tooShort);
    });

    test('may not be a distress phrase already', () {
      expect(DistressDetector.checkSecretPhrase('please leave me alone'),
          SecretPhraseProblem.tooCommon);
      expect(DistressDetector.checkSecretPhrase("they're kidnapping me"),
          SecretPhraseProblem.tooCommon);
    });

    test('may not be everyday filler', () {
      expect(DistressDetector.checkSecretPhrase('how are you'), SecretPhraseProblem.tooCommon);
    });

    test('an unusual phrase is accepted', () {
      expect(DistressDetector.checkSecretPhrase('the mangoes are ripe'), isNull);
    });
  });

  test('HQ is told the rule, never the words', () {
    const secret = GuardianMatch(GuardianTrigger.secretPhrase, 'secret_phrase');
    expect(secret.description, 'Guardian: secret phrase heard');
    const weapon = GuardianMatch(GuardianTrigger.distressPhrase, 'weapon_plea');
    expect(weapon.description, 'Guardian: distress phrase heard (weapon and a plea)');
  });
}
