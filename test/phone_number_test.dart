// One phone number, one person, one account.
//
// A citizen signs in by typing their number and reading back an SMS code. The
// number IS the identity — no email, no password, and `profiles.phone` is
// UNIQUE — so the string that reaches Supabase decides which account they land
// in. The app passed whatever was typed with the non-digits stripped, and
// Nigerians write their number four ways.
//
// These are the four ways, and they must all be the same person.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/auth/phone_number.dart';

void main() {
  group('the same number, however it is written', () {
    const canonical = '+2348030001111';

    for (final written in <String>[
      '08030001111',
      '8030001111',
      '2348030001111',
      '+2348030001111',
      '+234 803 000 1111',
      '0803 000 1111',
      '0803-000-1111',
      '(0803) 000 1111',
      '00234 803 000 1111',
      '2340803 000 1111', // country code AND the trunk zero
      '  08030001111  ',
    ]) {
      test('"$written" is $canonical', () {
        expect(normaliseNigerianPhone(written), canonical);
      });
    }

    test('every spelling produces exactly one identity', () {
      // The defect, stated as a property: a person who types their number the
      // other way they habitually do must not get a second account with no
      // incident history, no emergency contacts and no PIN.
      final forms = <String>[
        '08030001111',
        '8030001111',
        '2348030001111',
        '+2348030001111',
        '+234 803 000 1111',
      ];
      expect(forms.map(normaliseNigerianPhone).toSet(), hasLength(1));
    });
  });

  group('numbers that cannot receive the code', () {
    test('a landline is refused, before an SMS is paid for', () {
      // 073 is Jos. An SMS to it can never arrive, so accepting it means
      // charging for a message that goes nowhere and leaving the person on a
      // screen waiting for it.
      final result = readNigerianPhone('07312345678');
      expect(result.isValid, isFalse);
      expect(result.problem, contains('mobile'));
    });

    test('too short says so', () {
      expect(readNigerianPhone('0803000').problem, contains('too short'));
    });

    test('too long says so', () {
      expect(readNigerianPhone('080300011119').problem, contains('too long'));
    });

    test('empty asks for the number rather than complaining', () {
      expect(readNigerianPhone('   ').problem, 'Enter your phone number.');
    });

    test('letters are a different mistake and get a different message', () {
      expect(readNigerianPhone('0803OOO1111').problem, contains('no letters'));
    });

    test('an invalid number yields no identity at all', () {
      // It must not fall through to something that looks usable.
      expect(normaliseNigerianPhone('12345'), isNull);
      expect(normaliseNigerianPhone(''), isNull);
    });
  });

  group('every Nigerian mobile prefix is accepted', () {
    // MTN, Airtel, Glo and 9mobile. Refusing a live prefix locks that network's
    // subscribers out of the app entirely, which is the worst possible failure
    // for a validator that exists to be helpful.
    for (final prefix in nigerianMobilePrefixes) {
      test('0$prefix… is a mobile number', () {
        expect(readNigerianPhone('0${prefix}30001111').isValid, isTrue);
      });
    }

    test('a prefix that is not allocated to mobile is refused', () {
      expect(readNigerianPhone('01230001111').isValid, isFalse); // 12 — landline
    });
  });

  group('showing the number back', () {
    test('is the form people write, not E.164', () {
      // "Code sent to +2348030001111" invites a "…is that mine?" pause. This is
      // read on the OTP screen and on the lock screen.
      expect(displayNigerianPhone('+2348030001111'), '0803 000 1111');
    });

    test('leaves anything it does not recognise alone', () {
      expect(displayNigerianPhone('+14155550123'), '+14155550123');
    });

    test('round-trips: what is displayed reads back to what was stored', () {
      const stored = '+2348130009999';
      expect(normaliseNigerianPhone(displayNigerianPhone(stored)), stored);
    });
  });

  group('while the person is still typing', () {
    test('the first few digits are not an error', () {
      expect(couldStillBeAPhoneNumber(''), isTrue);
      expect(couldStillBeAPhoneNumber('080'), isTrue);
    });

    test('a complete, valid number is fine', () {
      expect(couldStillBeAPhoneNumber('08030001111'), isTrue);
    });

    test('a complete number that is wrong is not', () {
      expect(couldStillBeAPhoneNumber('0123000111100'), isFalse);
    });
  });
}
