import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central configuration for Supabase client initialization.
class SupabaseConfig {
  /// The project this build talks to.
  ///
  /// Overridable at build time so a build can be pointed somewhere that is not
  /// production:
  ///
  ///     flutter build web --dart-define=SUPABASE_URL=http://127.0.0.1:54321
  ///
  /// The defaults are the production values and are unchanged, so a build that
  /// passes nothing behaves exactly as before. This is not a secret — the
  /// publishable key is public by design, since row-level security is the whole
  /// access model — but a hard-coded endpoint meant every local run, every test
  /// harness and every screenshot pass talked to the live project, which is a
  /// different problem from secrecy and a worse one: there is no safe way to
  /// exercise the app without writing to production data.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wpffwoblxuogemxcqpep.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_9ufgK7BJ8Zy8x7-K133NRQ_8myILNuw',
  );

  static bool _initialized = false;

  /// Whether [init] has completed successfully.
  ///
  /// `main()` checks this before building the app, because the app cannot work
  /// without a client and must say so rather than show a blank page.
  static bool get isInitialized => _initialized || _override != null;

  /// Initializes Supabase Flutter SDK.
  ///
  /// Does no network I/O: `Supabase.initialize` reads the persisted session
  /// from local storage and registers a deep-link observer, and the token
  /// refresh it kicks off (`recoverSession()`) is deliberately NOT awaited by
  /// the SDK (supabase_flutter/lib/src/supabase.dart:146-155). So a failure
  /// here is a local fault — storage, plugin registration, a bad URL — not a
  /// slow network, and retrying it is worth offering.
  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      debug: false,
    );
    _initialized = true;
  }

  static SupabaseClient? _override;

  /// Replaces the client returned by [client]. **Tests only.**
  ///
  /// `Supabase.instance` asserts that `Supabase.initialize` has run, and that
  /// assertion fires during `build()` in any widget that reaches for the
  /// client — so a widget test could not render an alert card, a mission list,
  /// or the map at all. Whole screens were therefore untestable, and the gap
  /// was invisible: tests asserting on empty states passed happily, because
  /// they never built the widgets that touch the client.
  ///
  /// This getter is the only path to the client anywhere in `lib/`, so
  /// overriding it here reaches every call site without threading a client
  /// through 84 of them.
  ///
  /// Set it to install a stand-in; set it to null to restore the real
  /// singleton. Always restore it — `addTearDown(() =>
  /// SupabaseConfig.clientOverride = null)` — or the override leaks into the
  /// next test in the same process.
  @visibleForTesting
  static set clientOverride(SupabaseClient? value) => _override = value;

  /// The stand-in installed by [clientOverride], or null. **Tests only.**
  @visibleForTesting
  static SupabaseClient? get clientOverride => _override;

  /// Convenience getter for SupabaseClient instance.
  ///
  /// Throws a [StateError] naming the problem when [init] has not succeeded.
  ///
  /// The plain `Supabase.instance.client` does not. `Supabase.instance` guards
  /// itself with an `assert`
  /// (supabase_flutter/lib/src/supabase.dart:43-49), which is STRIPPED from a
  /// release build, and `client` is a `late` field (line 173) — so in release
  /// the first caller got `LateInitializationError: Field 'client' has not
  /// been initialized`, thrown from whatever widget happened to ask first.
  /// `main()` caught the init failure, logged it and carried on, so the error
  /// surfaced during the very first `build()`, and a build-time throw in
  /// release paints a blank pale box. That was the blank page: the app's own
  /// start-up failure, wearing no message at all.
  static SupabaseClient get client {
    final override = _override;
    if (override != null) return override;
    if (!_initialized) {
      throw StateError(
        'Supabase is not initialized. SupabaseConfig.init() either was never '
        'called or threw, so there is no client to talk to. Start-up must '
        'report this rather than build a UI that reaches for it.',
      );
    }
    return Supabase.instance.client;
  }
}
