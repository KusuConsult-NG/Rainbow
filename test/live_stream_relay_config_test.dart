// Whether this build can relay media at all — the difference between the live
// stream working on a Nigerian handset and never connecting once.
//
// WHY THIS FILE EXISTS. `TURN_URL`, `TURN_USERNAME` and `TURN_CREDENTIAL` were
// read by lib/core/config/live_stream.dart and documented in two deployment
// guides, but were missing from `.env.example`. So every build made from the
// template shipped with `hasRelay` false and the live stream sat on
// "CONNECTING TO HQ — NOT LIVE YET" for ever. They are in the template now.
//
// `hasRelay` had no test of any kind. Its behaviour was asserted by a comment
// in the file that implements it, which is the same thing as not being
// asserted. STUN discovers an address; it cannot carry media, and a handset on
// mobile data sits behind carrier-grade NAT that is commonly symmetric, so
// without a relay there is no route.
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/config/live_stream.dart';

/// The repo's own way of putting values in front of dotenv in a test
/// (see error_reporting_test.dart).
/// The repo's own way of putting values in front of dotenv in a test (see
/// error_reporting_test.dart). An always-present throwaway key because
/// loadFromString refuses an empty string, and "no TURN_URL at all" is the
/// case that matters most here.
void load(Map<String, String> env) => dotenv.loadFromString(
      envString: <String>[
        'GUARDIAN_UNUSED_IN_THIS_TEST=1',
        ...env.entries.map((e) => '${e.key}=${e.value}'),
      ].join('\n'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => load({}));

  group('with no relay configured', () {
    test('hasRelay is false, which is what the screen is told', () {
      load({});
      expect(hasRelay, isFalse);
      expect(turnUrl, isNull);
    });

    test('the peer connection gets STUN only — nothing that can relay', () {
      load({});
      final urls = iceServers.map((s) => s['urls'] as String).toList();
      expect(urls, equals(defaultStunUrls));
      expect(urls.any((u) => u.startsWith('turn')), isFalse,
          reason: 'STUN discovers an address; it cannot carry media');
    });

    test('an empty TURN_URL is no relay, not a relay called ""', () {
      load({'TURN_URL': '   '});
      expect(hasRelay, isFalse);
    });
  });

  group('with a relay configured', () {
    test('hasRelay is true and the relay is handed to the peer connection',
        () {
      load({
        'TURN_URL': 'turn:relay.example.org:3478',
        'TURN_USERNAME': 'u',
        'TURN_CREDENTIAL': 'c',
      });
      expect(hasRelay, isTrue);
      final relay = iceServers.last;
      expect(relay['urls'], 'turn:relay.example.org:3478');
      expect(relay['username'], 'u');
      expect(relay['credential'], 'c');
      expect(iceServers.length, defaultStunUrls.length + 1,
          reason: 'STUN is kept: the relay is a fallback, not a replacement');
    });

    test('turns: is a relay too', () {
      load({'TURN_URL': 'turns:relay.example.org:5349'});
      expect(hasRelay, isTrue);
    });

    test('credentials are left out rather than sent empty', () {
      load({'TURN_URL': 'turn:relay.example.org:3478'});
      final relay = iceServers.last;
      expect(relay.containsKey('username'), isFalse);
      expect(relay.containsKey('credential'), isFalse);
    });
  });

  // A relay that is configured and silently ignored is the exact failure this
  // whole file is about: it looks set up and behaves identically to nothing.
  group('a malformed relay is reported as none, not as a relay', () {
    for (final bad in <String>[
      'relay.example.org:3478',
      'https://relay.example.org',
      'stun:relay.example.org:3478',
    ]) {
      test('"$bad" is not taken for a relay', () {
        load({'TURN_URL': bad});
        expect(hasRelay, isFalse,
            reason: 'the peer connection would ignore it without complaint');
        expect(iceServers.map((s) => s['urls']), equals(defaultStunUrls));
      });
    }
  });
}
