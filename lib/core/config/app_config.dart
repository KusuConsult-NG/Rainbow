import 'dart:typed_data';

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

  /// Where an SMS-borne alert is sent — the emergency shortcode or long number
  /// the HQ gateway receives on.
  ///
  /// A destination number, not a credential, so it is safe in a bundled asset.
  /// `null` disables the SMS fallback entirely: a message with nowhere to go
  /// would cost money and reach nobody.
  static String? get smsShortcode => _read('SMS_EMERGENCY_SHORTCODE');

  /// HQ's mesh PUBLIC key: a compressed P-256 point, 33 bytes as 66 hex
  /// characters.
  ///
  /// Public by definition — every handset has it and it can only seal, never
  /// open. The private half lives on the HQ server and nowhere else; see
  /// `docs/OFFLINE_CHANNELS_DESIGN.md`.
  ///
  /// Returns null unless the value is exactly a 33-byte point whose first byte
  /// is a valid compression prefix. A half-configured key is worse than none: it
  /// would seal alerts nobody can open, and the phone would believe it had a
  /// working channel.
  static Uint8List? get meshHqPublicKey {
    final raw = _read('MESH_HQ_PUBLIC_KEY')?.trim();
    if (raw == null || !RegExp(r'^[0-9a-fA-F]{66}$').hasMatch(raw)) return null;
    final bytes = Uint8List(33);
    for (var i = 0; i < 33; i++) {
      bytes[i] = int.parse(raw.substring(i * 2, i * 2 + 2), radix: 16);
    }
    // 0x02 and 0x03 are the compressed-point prefixes; anything else is not a
    // point, whatever else it might be.
    if (bytes[0] != 0x02 && bytes[0] != 0x03) return null;
    return bytes;
  }

  static String? get cloudinaryCloudName => _read('CLOUDINARY_CLOUD_NAME');
  static String? get cloudinaryUploadPreset => _read('CLOUDINARY_UPLOAD_PRESET');
  // REMOVED: demoCitizenEmail / demoCitizenPass. Both had ZERO callers —
  // AuthService reads `dotenv.env['DEMO_CITIZEN_EMAIL']` and
  // `dotenv.env['DEMO_CITIZEN_PASS']` directly for the demo bypass, which
  // `isDemoNumber` compiles out of release builds. Two credential-shaped
  // getters that nothing called are worth deleting rather than leaving for
  // someone to reach for. The KEYS are still live in debug builds, which is why
  // scripts/local_e2e/provision_env.sh still writes them.
  // REMOVED: agentDefaultPass. One shared staff password, read from a `.env`
  // that ships inside the APK as a Flutter asset. See AuthService for the
  // full note; the replacement is a per-officer password.

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
