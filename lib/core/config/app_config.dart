import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised, validated access to runtime configuration.
///
/// ## Why this exists
///
/// Configuration used to be read ad-hoc as `dotenv.env['X'] ?? '<literal>'` at a
/// dozen call sites, with divergent fallbacks for the same key and a `.env`
/// load failure that only logged a warning. Every consumer now reads one
/// accessor, and [validate] is the single place to assert configuration at
/// startup.
///
/// ## What is deliberately NOT here any more
///
/// `SAFE_PIN` and `DURESS_PIN` were build-time constants in `.env` — a Flutter
/// **asset**, shipped verbatim inside every APK and extractable with `unzip`.
/// Every install shared the same two codes, and anyone who downloaded the app
/// could read the duress one. A duress code a captor can look up is worse than
/// none.
///
/// PINs are now per-user and verified on the server
/// (`supabase/migrations/20260902000000_per_user_emergency_pins.sql`): only
/// bcrypt hashes exist, in a table the API cannot read, and the device holds no
/// PIN material at all. See `EmergencyNotifier.verifyCancellation`.
///
/// Nothing safety-critical remains in this file, which is the correct state
/// for something that ships inside the binary.
class AppConfig {
  AppConfig._();

  static String? _read(String key) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  // ── Non-safety-critical: defaults are acceptable ───────────────────────────

  /// Base URL of the HQ dashboard backend, e.g. `https://hq.example.gov.ng`.
  ///
  /// Public by nature — it is a hostname, not a credential — so it is safe in a
  /// bundled asset. Any trailing slash is stripped so callers can append paths
  /// unconditionally. `null` when unconfigured, which disables the SOS escalation
  /// SMS (the alert row is still written).
  static String? get hqApiBaseUrl {
    final raw = _read('HQ_API_BASE_URL');
    if (raw == null) return null;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static String? get cloudinaryCloudName => _read('CLOUDINARY_CLOUD_NAME');
  static String? get cloudinaryUploadPreset => _read('CLOUDINARY_UPLOAD_PRESET');
  static String? get demoCitizenEmail => _read('DEMO_CITIZEN_EMAIL');
  static String? get demoCitizenPass => _read('DEMO_CITIZEN_PASS');
  static String? get agentDefaultPass => _read('AGENT_DEFAULT_PASS');

  /// Keys whose absence disables a safety-critical feature.
  ///
  /// Empty, and that is the point: nothing the app needs to keep people safe
  /// may depend on a value baked into the binary. `HMAC_SECRET` left when its
  /// signing service was found to have zero callers; `TERMII_API_KEY` moved to
  /// the server (H-3); `SAFE_PIN`/`DURESS_PIN` moved to the server too. If a
  /// key ever reappears here, ask why a bundled asset is being trusted with it.
  static const List<String> requiredKeys = <String>[];

  /// Returns the required keys that are missing or blank.
  static List<String> missingRequiredKeys() =>
      requiredKeys.where((k) => _read(k) == null).toList();

  /// Call once after `dotenv.load()`. Logs loudly, and in debug builds throws so
  /// a misconfigured build cannot reach a tester unnoticed.
  static void validate() {
    final missing = missingRequiredKeys();
    if (missing.isEmpty) {
      debugPrint('[CONFIG] OK — no required keys outstanding.');
      return;
    }
    final message =
        '[CONFIG] MISSING REQUIRED KEYS: ${missing.join(', ')}. '
        'Copy .env.example to .env and fill it in.';
    debugPrint('🔥 $message');
    assert(false, message);
  }
}
