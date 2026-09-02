// Tests for the SOS escalation SMS path after finding H-3 moved the Termii
// credential off the handset.
//
// Two properties matter here, and neither is happy-path plumbing:
//
//   1. The request carries the USER'S OWN access token and nothing else. If a
//      provider credential or a caller-chosen recipient ever reappears in this
//      request, the fix has been undone and the APK is leaking again.
//   2. Nothing on this path can throw or hang into the SOS flow. This is a
//      redundant channel; the alert row is the system of record.
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rainbow_app/services/sos_dispatch_service.dart';

const _baseUrl = 'https://hq.test';

/// Builds a service pointed at a fake backend, bypassing Supabase.
SosDispatchService _service(
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'user-access-token',
}) {
  return SosDispatchService(
    client: MockClient(handler),
    accessToken: () async => token,
  );
}

void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'HQ_API_BASE_URL=$_baseUrl');
  });

  tearDown(dotenv.clean);

  group('the request that leaves the device', () {
    late http.Request captured;

    Future<SosDispatchResult> dispatch({
      String? alertId = 'a1b2c3d4-0000-4000-8000-000000000000',
      double? latitude = 9.8965,
      double? longitude = 8.8583,
    }) {
      return _service((req) async {
        captured = req;
        return http.Response('{"sms":"SENT"}', 200);
      }).dispatchSos(
        alertId: alertId,
        latitude: latitude,
        longitude: longitude,
      );
    }

    test('goes to our own backend, not to the SMS provider', () async {
      await dispatch();
      expect(captured.url.toString(), '$_baseUrl/api/sos/dispatch-sms');
      expect(
        captured.url.host,
        isNot(contains('termii')),
        reason: 'The handset must never talk to Termii directly again (H-3).',
      );
    });

    test('authenticates with the user session token', () async {
      await dispatch();
      expect(captured.headers['Authorization'], 'Bearer user-access-token');
    });

    // REGRESSION for H-3. The old payload contained `api_key`, `to`, `from` and
    // a fully-composed `sms` string, all chosen on the device.
    test('carries facts only — no credential, no recipient, no message', () async {
      await dispatch();
      final body = jsonDecode(captured.body) as Map<String, dynamic>;

      expect(body.keys.toSet(), {'alertId', 'latitude', 'longitude'});
      for (final forbidden in ['api_key', 'apiKey', 'to', 'from', 'sms', 'channel']) {
        expect(
          body.containsKey(forbidden),
          isFalse,
          reason: "'$forbidden' is the server's decision, not the app's.",
        );
      }
      expect(
        captured.body.toLowerCase(),
        isNot(contains('termii')),
        reason: 'No trace of the SMS provider should remain in the client payload.',
      );
    });

    // C-5: a fabricated position sends responders to the wrong place, which is
    // worse than sending them none.
    test('a missing GPS fix is sent as null, never as a stand-in value', () async {
      await dispatch(latitude: null, longitude: null);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['latitude'], isNull);
      expect(body['longitude'], isNull);
    });

    test('real coordinates survive the round trip intact', () async {
      await dispatch();
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['latitude'], 9.8965);
      expect(body['longitude'], 8.8583);
    });
  });

  group('authentication', () {
    test('never reaches the backend without a session', () async {
      var called = false;
      final result = await _service(
        (_) async {
          called = true;
          return http.Response('{"sms":"SENT"}', 200);
        },
        token: null,
      ).dispatchSos(latitude: 9.9, longitude: 8.9);

      expect(result, SosDispatchResult.unauthenticated);
      expect(called, isFalse);
    });

    test('an empty token is treated as no session', () async {
      final result = await _service(
        (_) async => http.Response('{"sms":"SENT"}', 200),
        token: '',
      ).dispatchSos();
      expect(result, SosDispatchResult.unauthenticated);
    });
  });

  group('response handling', () {
    Future<SosDispatchResult> respond(String body, int status) =>
        _service((_) async => http.Response(body, status)).dispatchSos();

    test('SENT is reported as sent', () async {
      expect(await respond('{"sms":"SENT"}', 200), SosDispatchResult.sent);
    });

    // An unconfigured backend is not an app error and must be distinguishable
    // from a real failure, otherwise nobody can tell "SMS is off" from "SMS broke".
    test('SKIPPED is distinguished from FAILED', () async {
      expect(
        await respond('{"sms":"SKIPPED","reason":"not configured"}', 200),
        SosDispatchResult.skipped,
      );
      expect(await respond('{"sms":"FAILED"}', 200), SosDispatchResult.failed);
    });

    test('an error status is a failure, not a silent success', () async {
      expect(await respond('{"error":"Authentication required"}', 401),
          SosDispatchResult.failed,);
      expect(await respond('{"error":"Too many"}', 429), SosDispatchResult.failed);
      expect(await respond('{"error":"boom"}', 500), SosDispatchResult.failed);
    });

    test('an unrecognised body is a failure, not a crash', () async {
      expect(await respond('not json at all', 200), SosDispatchResult.failed);
      expect(await respond('{"sms":"WHAT"}', 200), SosDispatchResult.failed);
      expect(await respond('[]', 200), SosDispatchResult.failed);
    });
  });

  group('failure containment — the SOS must never break here', () {
    test('a transport exception becomes a value, not a throw', () async {
      final result = await _service(
        (_) async => throw const _TransportFailure(),
      ).dispatchSos();
      expect(result, SosDispatchResult.failed);
    });

    // The old TermiiService was awaited BEFORE the alert row was written, so a
    // slow SMS provider delayed the actual emergency. The call is now unawaited
    // and additionally bounded.
    test('a hung backend is bounded by the timeout', () async {
      final result = await _service((_) async {
        await Future<void>.delayed(SosDispatchService.timeout * 3);
        return http.Response('{"sms":"SENT"}', 200);
      }).dispatchSos();
      expect(result, SosDispatchResult.failed);
    }, timeout: const Timeout(Duration(seconds: 30)),);
  });

  group('configuration', () {
    test('no HQ_API_BASE_URL degrades to a value, and sends nothing', () async {
      dotenv.clean();
      var called = false;
      final result = await _service((_) async {
        called = true;
        return http.Response('{"sms":"SENT"}', 200);
      }).dispatchSos(alertId: 'abc', latitude: 9.9, longitude: 8.9);

      expect(result, SosDispatchResult.unconfigured);
      expect(called, isFalse);
    });

    test('a trailing slash in the base URL does not double up the path', () async {
      dotenv.loadFromString(envString: 'HQ_API_BASE_URL=$_baseUrl/');
      late Uri seen;
      await _service((req) async {
        seen = req.url;
        return http.Response('{"sms":"SENT"}', 200);
      }).dispatchSos();
      expect(seen.toString(), '$_baseUrl/api/sos/dispatch-sms');
    });
  });
}

/// Stand-in for a transport failure, without importing dart:io.
class _TransportFailure implements Exception {
  const _TransportFailure();
  @override
  String toString() => '_TransportFailure: connection refused';
}
