/// A limit on every Supabase request, so no screen waits on a dead link
/// for as long as the operating system allows.
///
/// Neither the Supabase client nor dart:io sets one. On a connection that is
/// "up" and carries nothing (a captive portal, a dead 2G link, a congested
/// tower) a request waited on TCP timeouts, which run to minutes: an officer's
/// ACCEPT, an escalation, a chat message or a sign-in sat with its spinner and
/// its button disabled, with no error to act on. The SOS path has shorter
/// limits of its own (alert_service.dart, emergency_provider.dart); this is the
/// floor under everything else.
///
/// Two limits, both [limit]:
///  * the response must START within it (headers received);
///  * once started, the body may not go silent for longer than it.
/// A slow response that keeps arriving is never cut off.
///
/// Storage uploads and downloads are left alone: a video uploaded over a slow
/// link legitimately takes longer than any limit sensible for a query, and
/// its progress is the request body, which no response arrives to time.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

class BoundedHttpClient extends http.BaseClient {
  BoundedHttpClient(this._inner, {this.limit = const Duration(seconds: 20)});

  final http.Client _inner;

  /// How long a request may go without a response, or a body without data.
  final Duration limit;

  /// Requests no limit applies to: Supabase Storage objects.
  static bool isExempt(Uri url) => url.path.contains('/storage/v1/object');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (isExempt(request.url)) return _inner.send(request);

    final where = '${request.method} ${request.url.path}';
    final response = await _inner.send(request).timeout(
          limit,
          onTimeout: () => throw TimeoutException(
            'no response to $where within ${limit.inSeconds} s',
            limit,
          ),
        );
    return http.StreamedResponse(
      response.stream.timeout(
        limit,
        onTimeout: (sink) {
          sink
            ..addError(TimeoutException(
              'the response to $where stopped arriving for ${limit.inSeconds} s',
              limit,
            ))
            ..close();
        },
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
