// The handset resolves the backend itself when the device will not.
//
// A phone in Plateau showing four bars of 4G could not resolve the backend:
// "No address associated with hostname, errno = 7" — an EMPTY answer, not a
// missing name. Chrome on the same handset loaded the same URL, because it can
// resolve over DNS-over-HTTPS while Flutter goes through the system
// getaddrinfo(). Nobody reporting an emergency can be asked to go and fix
// Private DNS, so the app carries a second resolver.
//
// The end-to-end test below is the one that matters, and it needs no network:
// a stub resolver and a stub service, both on loopback, and a request for a
// name that cannot resolve. If the request arrives at the service, the whole
// mechanism works — system lookup fails, the fallback answers, the socket is
// opened to the address it gave.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/net/doh_resolver.dart';
import 'package:rainbow_app/core/net/resolving_http_overrides.dart';

void main() {
  group('reading a resolver answer', () {
    test('takes the A record', () {
      final address = DohResolver.parseAnswer(jsonEncode({
        'Status': 0,
        'Answer': <Map<String, Object?>>[
          <String, Object?>{'name': 'x.supabase.co', 'type': 1, 'TTL': 60, 'data': '104.18.38.10'},
        ],
      }));
      expect(address?.address, '104.18.38.10');
    });

    test('walks past a CNAME to the address behind it', () {
      // Supabase project hostnames are CNAMEs. Taking `Answer[0].data`
      // blindly returns the NAME it points at, and `InternetAddress.tryParse`
      // on a name returns null — so the fallback would quietly do nothing on
      // the exact hostnames it exists for.
      final address = DohResolver.parseAnswer(jsonEncode({
        'Status': 0,
        'Answer': <Map<String, Object?>>[
          <String, Object?>{'name': 'x.supabase.co', 'type': 5, 'TTL': 60, 'data': 'alias.supabase.co'},
          <String, Object?>{'name': 'alias.supabase.co', 'type': 1, 'TTL': 60, 'data': '172.64.149.246'},
        ],
      }));
      expect(address?.address, '172.64.149.246');
    });

    test('an empty answer is not an address', () {
      // NOERROR with no Answer section: this is the fault being worked around,
      // arriving from the public resolver too. It must read as "no answer",
      // not as a crash and not as a wrong address.
      expect(
        DohResolver.parseAnswer(jsonEncode(<String, Object?>{'Status': 0, 'Comment': 'no records'})),
        isNull,
      );
    });

    test('NXDOMAIN is not an address', () {
      expect(
        DohResolver.parseAnswer(jsonEncode(<String, Object?>{'Status': 3, 'Answer': <Object?>[]})),
        isNull,
      );
    });

    test('garbage is not an address, and does not throw', () {
      expect(DohResolver.parseAnswer('<html>blocked by your network</html>'), isNull);
      expect(DohResolver.parseAnswer(''), isNull);
      expect(DohResolver.parseAnswer('null'), isNull);
    });
  });

  group('which failures are worth a second resolver', () {
    test('the handset error is one', () {
      const message = "Failed host lookup: 'x.supabase.co'";
      final error = SocketException(
        message,
        osError: const OSError('No address associated with hostname', 7),
      );
      expect(DohResolver.isHostLookupFailure(error), isTrue);
    });

    test('a refused connection is not', () {
      // Retrying a refused port through another resolver finds the same port
      // refused, and the citizen waits longer for the same answer.
      final error = SocketException(
        'Connection refused',
        osError: const OSError('Connection refused', 111),
      );
      expect(DohResolver.isHostLookupFailure(error), isFalse);
    });

    test('a timeout is not, and neither is anything that is not a socket error', () {
      expect(
        DohResolver.isHostLookupFailure(
          SocketException('Connection timed out', osError: const OSError('timeout', 110)),
        ),
        isFalse,
      );
      expect(DohResolver.isHostLookupFailure(Exception('failed host lookup')), isFalse);
    });
  });

  group('end to end, with no network at all', () {
    late HttpServer service;
    late HttpServer stubResolver;
    var resolverCalls = 0;

    setUp(() async {
      resolverCalls = 0;
      service = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      service.listen((request) {
        request.response
          ..statusCode = 200
          ..write('reached the service');
        unawaited(request.response.close());
      });
      stubResolver = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      stubResolver.listen((request) {
        resolverCalls++;
        request.response
          ..statusCode = 200
          ..write(jsonEncode(<String, Object?>{
            'Status': 0,
            'Answer': <Map<String, Object?>>[
              <String, Object?>{
                'name': request.uri.queryParameters['name'],
                'type': 1,
                'TTL': 60,
                'data': '127.0.0.1',
              },
            ],
          }));
        unawaited(request.response.close());
      });
    });

    tearDown(() async {
      HttpOverrides.global = null;
      await service.close(force: true);
      await stubResolver.close(force: true);
    });

    void installPointingAtTheStub() {
      HttpOverrides.global = ResolvingHttpOverrides(
        resolver: DohResolver(
          newClient: HttpClient.new,
          endpoints: <String>['http://127.0.0.1:${stubResolver.port}/dns-query'],
        ),
      );
    }

    test('a name the device cannot resolve still reaches the service', () async {
      installPointingAtTheStub();
      // `.invalid` can never resolve (RFC 2606), so the system lookup fails
      // exactly as the handset's did.
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://unresolvable.invalid:${service.port}/'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      expect(response.statusCode, 200);
      expect(body, 'reached the service');
      expect(resolverCalls, 1, reason: 'the fallback resolver should have been asked once');
      client.close(force: true);
    });

    test('a name that already resolves never touches the fallback', () async {
      // The whole design rests on this: on a healthy network nothing changes
      // and no DNS-over-HTTPS request is ever sent. A fallback that runs
      // first would put a public resolver in the path of every emergency.
      installPointingAtTheStub();
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${service.port}/'),
      );
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 200);
      expect(resolverCalls, 0, reason: 'the device resolved it; the fallback is not needed');
      client.close(force: true);
    });

    test('a failure that is not DNS is reported as itself', () async {
      // Nothing is listening on this port. The fallback must not be consulted,
      // and the caller must get the connection error rather than a resolver
      // error that would send somebody looking in the wrong place.
      installPointingAtTheStub();
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close(force: true);

      final client = HttpClient();
      await expectLater(
        client.getUrl(Uri.parse('http://127.0.0.1:$port/')).then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
      expect(resolverCalls, 0);
      client.close(force: true);
    });

    test('when no resolver answers either, the original error stands', () async {
      // The stub is closed, so the fallback cannot answer. The citizen must
      // see the real failure — "cannot resolve" — not a second error from the
      // workaround, which is what would reach the classifier in auth_service
      // and decide what they are told.
      // Install first: `installPointingAtTheStub` reads `stubResolver.port`,
      // and a closed server has none.
      installPointingAtTheStub();
      await stubResolver.close(force: true);

      final client = HttpClient();
      await expectLater(
        client
            .getUrl(Uri.parse('http://unresolvable.invalid:${service.port}/'))
            .then((r) => r.close()),
        throwsA(
          isA<SocketException>().having(
            DohResolver.isHostLookupFailure,
            'is still a host lookup failure',
            isTrue,
          ),
        ),
      );
      client.close(force: true);
    });
  });
}
