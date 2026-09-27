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

  /// Initializes Supabase Flutter SDK
  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      debug: false,
    );
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

  /// Convenience getter for SupabaseClient instance
  static SupabaseClient get client => _override ?? Supabase.instance.client;
}
