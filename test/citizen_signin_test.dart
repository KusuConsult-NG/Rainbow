// How a citizen gets into this app.
//
// There is no email and no password. A person types their phone number, reads
// back a code sent to it, and that number is their identity for as long as they
// use the app — it is what `profiles.phone` holds, what HQ rings back, and what
// the incident card on the command map shows.
//
// These tests cover the decisions in that path that can be made without a
// device, a network or a Supabase project: which of the two things typed into
// the one field it is, whether the demo bypass exists in this build, and what
// the person is told when the code cannot be sent. The parts that need a live
// GoTrue — `signInWithOtp`, `verifyOTP` — are exercised by the staging script,
// not here.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/auth/phone_number.dart';
import 'package:rainbow_app/services/auth_service.dart';

/// Mirrors `_isLikelyPhone` in `login_screen.dart`.
///
/// One field takes both a citizen's phone number and an officer's badge, so
/// something has to decide which was typed. Extracted here because the widget
/// needs a Riverpod scope and a Supabase client, and the decision is a string
/// question.
bool isLikelyPhone(String input) {
  final trimmed = input.trim();
  if (trimmed.contains('@') || RegExp('[A-Za-z]').hasMatch(trimmed)) {
    return false;
  }
  if (trimmed.startsWith('+')) return true;
  return readNigerianPhone(trimmed).isValid;
}

void main() {
  group('which of the two things was typed into the one field', () {
    test('a number written with dashes is a phone number', () {
      // It was not. The old test required the input to be ALL digits once
      // spaces were removed, so `0803-000-1111` went down the BADGE path and
      // came back "invalid access code" — to a citizen who had typed their own
      // number correctly.
      expect(isLikelyPhone('0803-000-1111'), isTrue);
      expect(isLikelyPhone('(0803) 000 1111'), isTrue);
      expect(isLikelyPhone('0803 000 1111'), isTrue);
    });

    test('every spelling of a number is a phone number', () {
      for (final written in <String>[
        '08030001111',
        '8030001111',
        '2348030001111',
        '+2348030001111',
      ]) {
        expect(isLikelyPhone(written), isTrue, reason: written);
      }
    });

    test('a badge is not a phone number', () {
      expect(isLikelyPhone('HQ-001'), isFalse);
      expect(isLikelyPhone('RSP-014'), isFalse);
      expect(isLikelyPhone('commander@operationrainbow.plateau.gov.ng'), isFalse);
    });

    test('a foreign number is treated as a phone, so the message is about it', () {
      // It fails validation either way. The difference is whether the person is
      // told "that is not a Nigerian mobile number" or "invalid access code",
      // and only one of those is true.
      expect(isLikelyPhone('+14155550123'), isTrue);
      expect(readNigerianPhone('+14155550123').isValid, isFalse);
    });

    test('a short numeric code is not mistaken for a number', () {
      expect(isLikelyPhone('12345'), isFalse);
    });
  });

  group('the demo bypass', () {
    test('does not exist in a release build', () {
      // `isDemoNumber` returned true in EVERY build, so a shipped APK accepted
      // 08000000000 with the code 123456 and signed you in as whoever
      // DEMO_CITIZEN_EMAIL is — a real account on the real database, with the
      // password sitting in the bundled .env that extracts with `unzip`.
      //
      // This asserts the guard in whichever mode the test runs in: under
      // `flutter test` that is debug, so the bypass is present; a release build
      // has no path to it at all.
      expect(AuthService.isDemoNumber('08000000000'), !kReleaseMode);
      expect(AuthService.isDemoNumber('+2348000000000'), !kReleaseMode);
    });

    test('never matches an ordinary number', () {
      expect(AuthService.isDemoNumber('08030001111'), isFalse);
      expect(AuthService.isDemoNumber('+2348130009999'), isFalse);
      expect(AuthService.isDemoNumber(''), isFalse);
    });

    test('once compiled out, the demo number is just a number', () {
      // Worth stating precisely, because the first version of this test
      // asserted the opposite and was wrong: `0800…` parses as an ordinary
      // MTN-format number (the allocation check is on the first two digits,
      // `80`). So in a release build the demo number is normalised like any
      // other, a code is sent to it, and nobody can sign in without reading
      // that code. There is no second door behind the bypass — the bypass WAS
      // the door.
      final read = readNigerianPhone('08000000000');
      expect(read.isValid, isTrue);
      expect(read.e164, '+2348000000000');
    });
  });
}
