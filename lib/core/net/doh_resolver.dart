import 'dart:convert';
import 'dart:io';

/// Resolving a hostname when the device's own resolver will not.
///
/// ## Why this exists
///
/// Reported from a handset in Plateau, on a phone showing four bars of 4G:
///
///     SocketException: Failed host lookup: '<project>.supabase.co'
///     (OS Error: No address associated with hostname, errno = 7)
///
/// That errno is not "no such name". It is an EMPTY ANSWER: the resolver was
/// reached, asked for the address records, and returned none. The same
/// hostname opened in Chrome on the same handset answered immediately —
/// because Chrome can resolve over its own DNS-over-HTTPS, while Flutter goes
/// through the system `getaddrinfo()`. A Private DNS profile, a carrier
/// resolver filtering cloud hostnames, or a VPN that intercepts system DNS
/// all produce exactly this split.
///
/// The app cannot ask a citizen to fix that. Somebody reporting a kidnapping
/// at two in the morning is not going to open Settings and read about DNS over
/// TLS, and an emergency app that needs them to is not an emergency app. So
/// the handset resolves the name itself.
///
/// ## Why it is safe
///
/// The resolvers are addressed BY IP — `1.1.1.1` and `8.8.8.8` — so reaching
/// them needs no DNS at all, which is the whole point. Both present their own
/// address in the certificate's subjectAltNames, so the TLS connection to the
/// resolver is verified normally rather than waved through.
///
/// Nothing here weakens the connection to the service itself either: the
/// socket is opened to the resolved ADDRESS, and TLS is then negotiated
/// against the HOSTNAME, so SNI and certificate validation are unchanged. See
/// `ResolvingHttpOverrides`, which is the only caller.
///
/// ## What it does not do
///
/// It does not validate DNSSEC, and it trusts the two public resolvers to
/// answer honestly. That is the same trust the device's own resolver already
/// has, and strictly less than the trust placed in a resolver that is lying by
/// omission — which is the case this exists for.
class DohResolver {
  /// [newClient] makes a client that does NOT route through the overrides, or
  /// resolving a name would require resolving a name.
  DohResolver({
    required HttpClient Function() newClient,
    this.timeout = const Duration(seconds: 4),
    List<String>? endpoints,
  })  : _newClient = newClient,
        _endpoints = endpoints ?? publicEndpoints;

  final HttpClient Function() _newClient;
  final Duration timeout;

  /// Overridable so a test can stand one up on loopback. Nothing in `lib/`
  /// passes it: a resolver pointed somewhere a deployment chose would be a
  /// place to redirect the whole app by configuration.
  final List<String> _endpoints;

  /// Addressed by IP on purpose. A resolver you have to resolve is no use on a
  /// handset whose resolver is the broken part.
  ///
  /// Cloudflare and Google both serve the JSON API; the paths differ, which is
  /// why these are whole URLs rather than hosts.
  static const List<String> publicEndpoints = <String>[
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/resolve',
  ];

  final Map<String, _Answer> _cache = <String, _Answer>{};

  /// The address for [host], or null if no resolver would say.
  ///
  /// Never throws: a failure here must leave the caller free to report the
  /// original network error rather than one from the workaround.
  Future<InternetAddress?> resolve(String host) async {
    final cached = _cache[host];
    if (cached != null && !cached.isStale) {
      return cached.address;
    }
    for (final endpoint in _endpoints) {
      try {
        final address = await _ask(endpoint, host).timeout(timeout);
        if (address != null) {
          _cache[host] = _Answer(address, DateTime.now().add(const Duration(minutes: 5)));
          return address;
        }
      } catch (_) {
        // Try the next resolver. The caller's own error is the one worth
        // reporting, so nothing is rethrown from here.
      }
    }
    return null;
  }

  Future<InternetAddress?> _ask(String endpoint, String host) async {
    final client = _newClient();
    try {
      final uri = Uri.parse(endpoint).replace(queryParameters: <String, String>{
        'name': host,
        'type': 'A',
      });
      final request = await client.getUrl(uri);
      // Both resolvers answer JSON only when asked for it; without this header
      // Cloudflare replies with the DNS wire format and the parse below fails.
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      return parseAnswer(body);
    } finally {
      client.close(force: true);
    }
  }

  /// The first A record in a DNS JSON answer, or null.
  ///
  /// Separated from the request so it can be tested against recorded answers
  /// without a network. CNAMEs appear in the same `Answer` list with
  /// `"type": 5`, so taking the first entry blindly returns a NAME where an
  /// address is wanted — which is why this filters on the record type.
  static InternetAddress? parseAnswer(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      // Status 0 is NOERROR. Anything else, including the NODATA this whole
      // file exists for, has no address to give.
      if (decoded['Status'] != 0) return null;
      final answers = decoded['Answer'];
      if (answers is! List) return null;
      for (final answer in answers) {
        if (answer is! Map) continue;
        if (answer['type'] != 1 && answer['type'] != 28) continue; // A, AAAA
        final data = answer['data'];
        if (data is! String) continue;
        final address = InternetAddress.tryParse(data.trim());
        if (address != null) return address;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Whether [error] is the device's resolver failing, rather than the service
  /// being unreachable for some other reason.
  ///
  /// Only a resolution failure is worth retrying through a different resolver.
  /// A refused connection, a timeout or an unreachable network would fail the
  /// same way again and the retry would only make the citizen wait longer.
  static bool isHostLookupFailure(Object error) {
    if (error is! SocketException) return false;
    final text = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('no address associated') ||
        text.contains('nodename nor servname') ||
        text.contains('temporary failure in name resolution');
  }
}

class _Answer {
  _Answer(this.address, this.expires);

  final InternetAddress address;
  final DateTime expires;

  bool get isStale => DateTime.now().isAfter(expires);
}
