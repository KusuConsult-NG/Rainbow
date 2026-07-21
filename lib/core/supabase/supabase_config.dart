import 'package:supabase_flutter/supabase_flutter.dart';

/// Central configuration for Supabase client initialization.
class SupabaseConfig {
  static const String url = 'https://wpffwoblxuogemxcqpep.supabase.co';
  static const String anonKey = 'sb_publishable_9ufgK7BJ8Zy8x7-K133NRQ_8myILNuw';

  /// Initializes Supabase Flutter SDK
  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: false,
    );
  }

  /// Convenience getter for SupabaseClient instance
  static SupabaseClient get client => Supabase.instance.client;
}
