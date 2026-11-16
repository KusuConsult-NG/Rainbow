import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/guardian/distress_detector.dart';
import 'package:rainbow_app/core/guardian/hausa_prompts.dart';

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

    test('a Hausa greeting is everyday filler too', () {
      // Good morning, I'm well / welcome / thank you very much.
      expect(DistressDetector.checkSecretPhrase('ina kwana lafiya'), SecretPhraseProblem.tooCommon);
      expect(DistressDetector.checkSecretPhrase('sannu da zuwa'), SecretPhraseProblem.tooCommon);
      expect(DistressDetector.checkSecretPhrase('na gode sosai'), SecretPhraseProblem.tooCommon);
    });

    test('a Hausa call for help is refused, as an English one is', () {
      expect(DistressDetector.checkSecretPhrase('za su kashe ni'), SecretPhraseProblem.tooCommon);
      expect(DistressDetector.checkSecretPhrase('wani ya taimake ni'), SecretPhraseProblem.tooCommon);
    });

    test('an unusual Hausa phrase is accepted', () {
      expect(DistressDetector.checkSecretPhrase('mangwaro ya nuna sosai'), isNull);
    });
  });

  group('a secret phrase in Hausa', () {
    // With Hausa on, the Hausa recognizer's text goes through the same
    // detector, so a phrase typed in Hausa is matched against it.
    test('is matched in what the Hausa recognizer wrote', () {
      expect(once('Mangwaro ya nuna sosai.', secret: 'mangwaro ya nuna sosai'), isNotNull);
    });

    test('is matched whether or not the hooked letters were typed', () {
      // Typed with ɗ and written by the recognizer without, and the reverse.
      expect(once('ruwan dumi ya zuba', secret: 'ruwan ɗumi ya zuba'), isNotNull);
      expect(once('ruwan ɗumi ya zuba', secret: 'ruwan dumi ya zuba'), isNotNull);
    });

    test('is matched inside a longer sentence, on whole words only', () {
      expect(once('kai yau mangwaro ya nuna sosai fa', secret: 'mangwaro ya nuna sosai'), isNotNull);
      expect(once('mangwaron ya nuna sosai', secret: 'mangwaro ya nuna sosai'), isNull);
    });
  });

  test('HQ is told the rule, never the words', () {
    const secret = GuardianMatch(GuardianTrigger.secretPhrase, 'secret_phrase');
    expect(secret.description, 'Guardian: secret phrase heard');
    const weapon = GuardianMatch(GuardianTrigger.distressPhrase, 'weapon_plea');
    expect(weapon.description, 'Guardian: distress phrase heard (weapon and a plea)');
  });

  group('phase 2: Nigerian Pidgin, as the English recognizer writes it', () {
    for (final s in [
      'dem wan kill me',
      'THEM WANT KILL ME',
      'they one kill me o',
      'dem dey kill us',
      'dem don stab me',
      'abeg no kill me',
      'make una no shoot me',
      'dem don kidnap me',
      'THEY DONE KIDNAP US',
      'kidnappers wan kidnap me',
      'him get gun abeg no shoot',
    ]) {
      test('"$s" sends', () => expect(once(s), isNotNull));
    }

    for (final s in [
      'dem no wan kill me',
      'this work go kill me',
      'my oga go kill me if i late',
      'e go kill me with laugh',
      'dem talk say dem wan kidnap am',
      'abeg pass the knife',
      'abeg help me carry this load',
    ]) {
      test('"$s" does not send', () => expect(once(s), isNull));
    }

    test('two Pidgin pleas a minute apart send', () {
      final d = DistressDetector();
      expect(d.hear('abeg leave me', t0, isFinal: true), isNull);
      expect(d.hear('comot for my body', t0.add(const Duration(minutes: 1)), isFinal: true)?.rule,
          'repeated_plea');
    });
  });

  group('phase 2: what the offline recognizer actually produced', () {
    test('two different pleas in one breath send at once', () {
      expect(once('SOMEBODY HELP LEAVE ME ALONE GET OFF ME SOME ONE HELP')?.rule, 'repeated_plea');
    });

    test('one plea said twice in one breath does not', () {
      expect(once('leave me alone leave me alone'), isNull);
    });

    test('"some one help", as it writes "someone", counts as a plea', () {
      final d = DistressDetector();
      expect(d.hear('some one help', t0, isFinal: true), isNull);
      expect(d.hear('let me go', t0.add(const Duration(seconds: 30)), isFinal: true), isNotNull);
    });

    test('a misheard "kidnapped" still sends: "I AM BEING KIDNACKED HELP"', () {
      expect(once('I AM BEING KIDNACKED HELP')?.rule, 'abduction');
    });

    test('"KID NAPPING ME" is read as "kidnapping me"', () {
      expect(once('THEY ARE KID NAPPING ME')?.rule, 'abduction');
    });

    test('a misheard film about a kidnapping still sends nothing', () {
      expect(once('THE MOVY LAST NIGHT WAS ABOUT ACHE HID NAPPING'), isNull);
    });
  });

  group('phase 3: Hausa', () {
    // The recording prompts are the sentences native speakers will record for
    // the Hausa model. Every call for help among them must send, and no
    // everyday sentence may: this ties the rules to what will be measured.
    for (final p in hausaPrompts) {
      if (p.expect == 'sos') {
        test('prompt ${p.id} ("${p.english}") sends, at once or when repeated', () {
          // A strong phrase sends at once. A plea on its own only counts, as
          // "somebody help!" does in English: said again within a minute, it
          // sends.
          final d = DistressDetector();
          final first = d.hear(p.hausa, t0, isFinal: true);
          final second = first ?? d.hear(p.hausa, t0.add(const Duration(minutes: 1)), isFinal: true);
          expect(second, isNotNull, reason: p.hausa);
        });
      } else {
        test('prompt ${p.id} ("${p.english}") does not send', () {
          expect(once(p.hausa), isNull, reason: p.hausa);
        });
      }
    }

    test('hooked letters are made plain, not split on', () {
      expect(DistressDetector.normalize('Ƙasa ɗaya ɓera ƴaƴa'), 'kasa daya bera yaya');
    });

    test('"ba za su kashe ni ba" (they will not kill me) is negated', () {
      expect(once('ba za su kashe ni ba'), isNull);
    });

    test('"kashe wuta" (switch off the light) is not a threat', () {
      expect(once('don allah ka kashe wuta'), isNull);
    });

    test('"ka taimake ni" (help me carry this), said twice, does not add up', () {
      final d = DistressDetector();
      expect(d.hear('ka taimake ni in dauki kaya', t0, isFinal: true), isNull);
      expect(d.hear('ka taimake ni in dauki kaya', t0.add(const Duration(seconds: 20)), isFinal: true), isNull);
    });

    test('a weapon with a Hausa plea sends', () {
      expect(once('yana da bindiga don allah kar ka harbe ni')?.rule, isIn(['threat_to_life', 'weapon_plea']));
    });

    test('two Hausa pleas a minute apart send', () {
      final d = DistressDetector();
      expect(d.hear('ku bar ni', t0, isFinal: true), isNull);
      expect(d.hear('ku sake ni', t0.add(const Duration(minutes: 1)), isFinal: true)?.rule, 'repeated_plea');
    });
  });
}
