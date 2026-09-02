// A SupabaseClient that never touches the network, for widget tests.
//
// THE PROBLEM THIS SOLVES
//
// `Supabase.instance` asserts that `Supabase.initialize` has run. That
// assertion fires during `build()`, so any widget that reaches for the client
// — an alert card, the mission list, the map — could not be rendered in a
// widget test at all. Whole screens were untestable, and worse, the gap was
// invisible: tests that only ever hit empty states passed happily, because
// they never built the widgets that touch the client.
//
// WHY A REAL CLIENT AND NOT A MOCK
//
// `SupabaseClient` accepts an `httpClient`, so a genuine client can be built
// over an http mock. That keeps the real query builders, the real auth object
// and the real types in play — a `Mock implements SupabaseClient` would have
// to fake `.from().select().eq()` chains and would drift from the SDK. Here
// only the transport is faked, which is the one part a test has no business
// exercising.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Answers every REST call with these rows.
///
/// PostgREST returns a JSON array; `.maybeSingle()`/`.single()` ask for a
/// single object via the Accept header, so the shape is chosen accordingly —
/// otherwise `maybeSingle()` sees a list and throws instead of returning null.
///
/// Every response carries `request:`. postgrest dereferences
/// `response.request!` while parsing, so a response without it fails with a
/// bare "Null check operator used on a null value" that looks like a bug in
/// the code under test rather than in the fixture.
Future<http.Response> Function(http.Request) jsonRows(
  List<Map<String, dynamic>> rows,
) =>
    (request) async {
      final wantsSingle =
          (request.headers['Accept'] ?? '').contains('vnd.pgrst.object');
      if (wantsSingle) {
        if (rows.isEmpty) {
          // PostgREST answers a no-rows `maybeSingle` with 200 and an empty
          // body; the client turns that into null rather than an error.
          return http.Response('', 200,
              headers: _jsonHeaders, request: request);
        }
        return http.Response(jsonEncode(rows.first), 200,
            headers: _jsonHeaders, request: request);
      }
      return http.Response(jsonEncode(rows), 200,
          headers: _jsonHeaders, request: request);
    };

/// Answers every REST call with a PostgREST-shaped error.
Future<http.Response> Function(http.Request) jsonError(
  int status,
  String message,
) =>
    (request) async => http.Response(
          jsonEncode({'message': message}),
          status,
          headers: _jsonHeaders,
          request: request,
        );

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// Thrown when a widget test reaches realtime. See [installOfflineSupabase].
class RealtimeNotAvailableInTests extends StateError {
  RealtimeNotAvailableInTests()
      : super(
          'A test opened a Supabase realtime subscription.\n'
          '\n'
          'installOfflineSupabase() fakes the HTTP transport, but realtime\n'
          'speaks WebSocket and would try to open a real socket, which hangs\n'
          'the test with a pending timer rather than failing.\n'
          '\n'
          'Override the provider that calls .stream() instead — e.g.\n'
          '  broadcastProvider.overrideWith((ref) => Stream.value(const [])),\n'
          'so the widget under test gets its data from the test, not a socket.',
        );
}

/// Installs an offline [SupabaseClient] as [SupabaseConfig.client] for the
/// duration of the current test, and registers its own teardown.
///
/// [handler] lets a test answer specific REST calls; the default answers every
/// request with an empty JSON array, which is what PostgREST returns for a
/// query matching no rows.
///
/// **Realtime is deliberately not supported.** `httpClient` covers REST only;
/// `.stream()` subscriptions speak WebSocket and would open a real socket,
/// which leaves a pending timer and hangs the test instead of failing it. The
/// transport below throws [RealtimeNotAvailableInTests] so that mistake names
/// itself. Override the provider that subscribes, rather than trying to serve
/// it from here.
SupabaseClient installOfflineSupabase({
  Future<http.Response> Function(http.Request request)? handler,
}) {
  final client = SupabaseClient(
    // Not a reachable host. Anything that escapes the fake transports fails
    // loudly rather than quietly reaching the real project.
    'http://offline.invalid',
    'test-anon-key',
    httpClient: MockClient(
      handler ??
          (request) async => http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              ),
    ),
    realtimeClientOptions: RealtimeClientOptions(
      transport: (url, headers) => throw RealtimeNotAvailableInTests(),
    ),
  );

  SupabaseConfig.clientOverride = client;
  addTearDown(() async {
    SupabaseConfig.clientOverride = null;
    await client.dispose();
  });

  return client;
}
