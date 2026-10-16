import 'dart:async';
import 'dart:io';

import 'doh_resolver.dart';

/// Every outgoing connection in the app, with a second resolver behind it.
///
/// Installed once in `main()`, before anything opens a socket, this routes
/// every `HttpClient` the process creates — including the one `dart:io` keeps
/// for WebSockets, which is how the Supabase realtime channel connects —
/// through a connection factory that falls back to [DohResolver] when the
/// device's own resolver returns nothing.
///
/// ## The order matters
///
/// The system resolver is tried FIRST, every time. On a healthy network
/// nothing here changes behaviour: the connection is made exactly as before
/// and no DNS-over-HTTPS request is ever sent. The fallback runs only after
/// the handset has already said it cannot resolve the name.
///
/// ## What `connectionFactory` does and does not do for you
///
/// Checked against the SDK rather than assumed, because getting it wrong here
/// means shipping unencrypted traffic:
///
///   * With a factory installed and a DIRECT connection, `dart:io` does NOT
///     wrap the socket in TLS — the `SecureSocket.startConnect` call sits in
///     the `else` branch that only runs when there is no factory
///     (`_http/http_impl.dart`). So this factory must negotiate TLS itself,
///     and it does: `SecureSocket.secure(socket, host: <hostname>)`, which
///     sends the HOSTNAME for SNI and validates the certificate against it
///     while the socket is open to the resolved ADDRESS.
///   * With a PROXY, `dart:io` builds the CONNECT tunnel and secures it
///     itself, so the factory must hand back a plain socket to the proxy.
///     Securing it here would give a TLS handshake inside a TLS handshake.
///
/// `ConnectionTask.fromSocket` is the documented way to return a socket from
/// a factory; its own doc comment names `HttpClient.connectionFactory` as the
/// use case.
class ResolvingHttpOverrides extends HttpOverrides {
  ResolvingHttpOverrides({DohResolver? resolver})
      : _resolver = resolver ?? DohResolver(newClient: _unroutedClient);

  /// The resolver this will consult. Exposed so a test can see which one is
  /// in use without reaching into the override.
  DohResolver get resolver => _resolver;

  final DohResolver _resolver;

  /// A client that does not go through these overrides.
  ///
  /// The resolver uses it, and must: a client that routed through the factory
  /// below would need a name resolved in order to resolve a name.
  /// `HttpOverrides.createHttpClient` returns a plain client, so calling the
  /// base implementation is the whole trick.
  static HttpClient _unroutedClient() => _Base().createHttpClient(null);

  /// Installs this for the whole process. Call it before anything connects:
  /// `dart:io` keeps its WebSocket client in a `static final`, so a socket
  /// opened before this runs keeps the unmodified client for the session.
  static void install() {
    HttpOverrides.global = ResolvingHttpOverrides();
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = _connect;
    return client;
  }

  Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final direct = proxyHost == null;
    final host = direct ? uri.host : proxyHost;
    final port = direct ? uri.port : (proxyPort ?? 80);
    final secure = direct && (uri.scheme == 'https' || uri.scheme == 'wss');

    var cancelled = false;
    final socket = _open(host, port, secure ? uri.host : null);
    // If the client cancels while this is still connecting, the socket still
    // arrives — and an orphaned socket on a handset is a radio that stays
    // awake. Nothing waits on this; the caller gets `socket` itself.
    unawaited(socket.then((s) {
      if (cancelled) s.destroy();
    }).catchError((Object _) {}));

    // A STATIC METHOD, not a named constructor — `ConnectionTask<Socket>.
    // fromSocket(...)` does not compile.
    return ConnectionTask.fromSocket<Socket>(socket, () => cancelled = true);
  }

  Future<Socket> _open(String host, int port, String? tlsName) async {
    try {
      return await _secure(await Socket.connect(host, port), tlsName);
    } on SocketException catch (error) {
      if (!DohResolver.isHostLookupFailure(error)) rethrow;
      final address = await _resolver.resolve(host);
      if (address == null) rethrow;
      return _secure(await Socket.connect(address, port), tlsName);
    }
  }

  /// TLS against the NAME, over a socket open to the ADDRESS.
  ///
  /// `host:` is what makes that safe — it is the name sent in SNI and the name
  /// the certificate is checked against. Dropping it would leave the
  /// certificate being validated against an IP address, which is the point at
  /// which this stops being a DNS workaround and becomes a vulnerability.
  Future<Socket> _secure(Socket socket, String? tlsName) async {
    if (tlsName == null) return socket;
    try {
      return await SecureSocket.secure(socket, host: tlsName);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }
}

/// `HttpOverrides` is abstract only in the sense that it is meant to be
/// subclassed; its `createHttpClient` already returns a plain client, which is
/// what the resolver needs.
class _Base extends HttpOverrides {}
