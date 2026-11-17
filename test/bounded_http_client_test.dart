// Every Supabase request is bounded: a response must start, and keep arriving,
// within the limit. See lib/core/net/bounded_http_client.dart.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rainbow_app/core/net/bounded_http_client.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';

void main() {
  const limit = Duration(milliseconds: 100);
  final rest = Uri.parse('https://x.supabase.co/rest/v1/alerts?select=id');
  final upload = Uri.parse('https://x.supabase.co/storage/v1/object/evidence/a.mp4');

  test('a response that never starts fails with a timeout', () async {
    final c = BoundedHttpClient(
      MockClient.streaming((_, __) => Completer<http.StreamedResponse>().future),
      limit: limit,
    );
    await expectLater(
      c.get(rest).timeout(const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>().having((e) => e.message, 'message', contains('/rest/v1/alerts'))),
    );
  });

  test('a body that stops arriving fails with a timeout', () async {
    final c = BoundedHttpClient(
      MockClient.streaming((_, __) async {
        final body = StreamController<List<int>>();
        body.add(utf8.encode('[{"id":')); // and then nothing
        return http.StreamedResponse(body.stream, 200);
      }),
      limit: limit,
    );
    await expectLater(
      c.get(rest).timeout(const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a slow response that keeps arriving is not cut off', () async {
    final c = BoundedHttpClient(
      MockClient.streaming((_, __) async {
        // Five chunks, each well inside the limit, the whole well over it.
        final chunks = Stream<List<int>>.periodic(
          const Duration(milliseconds: 60),
          (i) => utf8.encode('$i'),
        ).take(5);
        return http.StreamedResponse(chunks, 200);
      }),
      limit: limit,
    );
    final r = await c.get(rest);
    expect(r.statusCode, 200);
    expect(r.body, '01234');
  });

  test('a normal response passes through unchanged', () async {
    final c = BoundedHttpClient(
      MockClient((_) async => http.Response('[{"id":1}]', 200, headers: {'content-type': 'application/json'})),
      limit: limit,
    );
    final r = await c.get(rest);
    expect(r.statusCode, 200);
    expect(jsonDecode(r.body), [
      {'id': 1}
    ]);
    expect(r.headers['content-type'], 'application/json');
  });

  test('storage uploads are not limited', () async {
    expect(BoundedHttpClient.isExempt(upload), isTrue);
    expect(BoundedHttpClient.isExempt(rest), isFalse);
    final c = BoundedHttpClient(
      MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 250)); // over the limit
        return http.Response('{"Key":"evidence/a.mp4"}', 200);
      }),
      limit: limit,
    );
    final r = await c.post(upload, body: 'video bytes');
    expect(r.statusCode, 200);
  });

  test('the app gives Supabase the bounded client', () {
    final c = SupabaseConfig.newHttpClient();
    addTearDown(c.close);
    expect(c, isA<BoundedHttpClient>());
    expect((c as BoundedHttpClient).limit, const Duration(seconds: 20));
  });
}
