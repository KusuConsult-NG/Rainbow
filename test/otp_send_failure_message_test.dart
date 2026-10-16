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
  String describe(String error, {bool? hasNetwork}) =>
      AuthService.describeOtpSendFailure(
        Exception(error),
        hasNetwork: hasNetwork,
      );

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
    // THIS TEST USED TO PIN THE DEFECT.
    //
    // It asserted that `Failed host lookup`, a timeout and an unreachable
    // network ALL produce "NO CONNECTION", with nobody having asked the
    // handset anything. That is what a citizen saw on a phone showing four
    // bars of 4G: the app told them their connection was missing when what
    // had failed was resolving the service's own hostname.
    //
    // "No connection" is the one message in this method that IS the person's
    // to fix, so it has to be earned: say it when the handset says it is
    // offline, and not otherwise.
    const offline = [
      'SocketException: Failed host lookup',
      'Connection timeout',
      'network is unreachable',
    ];

    test('is said when the handset says it is offline', () {
      for (final wording in offline) {
        expect(
          describe(wording, hasNetwork: false),
          contains('NO CONNECTION'),
          reason: wording,
        );
      }
    });

    test('is never said when the handset says it is online', () {
      for (final wording in offline) {
        final said = describe(wording, hasNetwork: true);
        expect(said, isNot(contains('NO CONNECTION')), reason: wording);
      }
    });

    test('is not guessed at when nobody asked the handset', () {
      for (final wording in offline) {
        final said = describe(wording);
        expect(said, isNot(contains('NO CONNECTION')), reason: wording);
        // The DECLARATIVE claim is what must not appear. "IF THIS PHONE IS
        // ONLINE, REPORT IT TO HQ" is a conditional, and is the honest
        // wording when nobody checked — it is this assertion that was wrong
        // the first time, not the message.
        expect(
          said,
          isNot(contains('PHONE IS ONLINE BUT')),
          reason: 'unknown is unknown, in both directions: $wording',
        );
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


  const lookupFailed =
      "SocketException: Failed host lookup: 'abc.supabase.co' "
      '(OS Error: No address associated with hostname, errno = 7)';

  group('a resolve failure on a live network', () {
    test('does not tell an online citizen they have no connection', () {
      final said = describe(lookupFailed, hasNetwork: true);
      expect(said, isNot(contains('NO CONNECTION')));
      expect(said, contains('IT IS NOT YOUR PHONE'));
      expect(said, contains('WILL NOT RESOLVE'));
    });

    test('still says no connection when the handset really is offline', () {
      final said = describe(lookupFailed, hasNetwork: false);
      expect(said, contains('NO CONNECTION'));
    });

    test('says the honest thing when nobody asked the handset', () {
      // null means "we did not find out". Blaming the phone needs evidence.
      final said = describe(lookupFailed);
      expect(said, isNot(contains('NO CONNECTION')));
    });
  });

  group('a timeout on a live network', () {
    test('blames the service, not the phone', () {
      final said =
          describe('TimeoutException after 0:00:10.000000', hasNetwork: true);
      expect(said, contains('DID NOT ANSWER'));
      expect(said, isNot(contains('NO CONNECTION')));
    });

    test('and says no connection when there is none', () {
      final said = describe('SocketException: failed', hasNetwork: false);
      expect(said, contains('NO CONNECTION'));
    });
  });
}
