// What a citizen is told when the code does not arrive.
//
// Sign-in is phone + one-time code, with no email path and no password. When
// the send fails there are only two useful things to say: "this is yours to
// retry" or "this is ours, report it". Saying the first about the second is
// telling somebody to keep pulling a lever that is not connected to anything —
// and the person pulling it may be reporting a kidnapping.
//
// These messages were untested. `_describeOtpSendFailure` is private and
// nothing exercised it, which is how `contains('rate')` survived: it also
// matches "generated", "accurate" and "operate", any of which would have sent
// somebody away to wait a minute for a fault that waiting does not fix.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/auth_service.dart';

void main() {
  // Static, so no SecureStorageService fixture is needed for a method that
  // does nothing but map an error to words.
  String describe(String error) =>
      AuthService.describeOtpSendFailure(Exception(error));

  group('the provider is not switched on at all', () {
    // Supabase refuses signInWithOtp outright when the project has no SMS
    // provider. Until the Send SMS hook is wired up, EVERY citizen sign-in
    // lands here, so this is the message that matters most.
    const wordings = [
      'Unsupported phone provider',
      'sms provider is not configured',
      'phone_provider_disabled',
      'Signups not allowed for otp',
    ];

    for (final wording in wordings) {
      test('"$wording" says it is not the person\'s phone', () {
        final said = describe(wording);
        expect(said, contains('NOT SWITCHED ON'));
        expect(said, contains('IT IS NOT YOUR PHONE'));
        expect(said, isNot(contains('TRY AGAIN')));
      });
    }
  });

  group('the hook answered with a failure', () {
    // The provider IS on and send-sms returned non-200. Every one of these is a
    // deployment fault that retrying cannot clear, and they are the hook's own
    // messages — matched on strings this repository controls rather than on
    // Supabase's wording.
    const wordings = [
      'hook is not configured',
      'hook secret is configured under the old name',
      'TERMII_API_KEY is not set in Supabase secrets',
      'Termii refused the message',
      'could not reach Termii: socket hang up',
    ];

    for (final wording in wordings) {
      test('"$wording" is reported as misconfiguration, not as retry', () {
        final said = describe(wording);
        expect(said, contains('MISCONFIGURED'));
        expect(said, contains('IT IS NOT YOUR PHONE'));
        // The whole point: this must not be the TRY AGAIN fallback.
        expect(said, isNot(contains('TRY AGAIN')));
      });
    }
  });

  group('rate limiting', () {
    test('a real rate-limit message says to wait', () {
      for (final wording in [
        'over_sms_send_rate_limit',
        'SMS rate limit exceeded',
        'too many requests',
      ]) {
        expect(describe(wording), contains('WAIT A MINUTE'), reason: wording);
      }
    });

    test('a message that merely contains "rate" is NOT a rate limit', () {
      // The defect this group was written for. `contains('rate')` matched all
      // of these, and the person was told to wait a minute for something that
      // waiting does not fix.
      for (final wording in [
        'could not be generated',
        'the operation failed',
        'inaccurate request',
      ]) {
        expect(describe(wording), isNot(contains('WAIT A MINUTE')), reason: wording);
      }
    });
  });

  group('no connection', () {
    test('is distinguished from everything else, because it IS the person\'s to fix', () {
      for (final wording in [
        'SocketException: Failed host lookup',
        'Connection timeout',
        'network is unreachable',
      ]) {
        final said = describe(wording);
        expect(said, contains('NO CONNECTION'), reason: wording);
      }
    });
  });

  group('anything else', () {
    test('falls back to retry, which is the only honest answer when unknown', () {
      expect(describe('something nobody has seen before'),
          'THE CODE COULD NOT BE SENT. TRY AGAIN.');
    });

    test('every message is shoutable without being abusive about the person', () {
      // The app renders these in upper case in a tactical style. The property
      // worth holding is that no message blames the user for a server fault.
      for (final wording in [
        'Unsupported phone provider',
        'hook is not configured',
        'over_sms_send_rate_limit',
        'SocketException',
        'unknown',
      ]) {
        final said = describe(wording);
        expect(said, said.toUpperCase(), reason: wording);
        expect(said, isNot(contains('INVALID')), reason: wording);
      }
    });
  });
}
