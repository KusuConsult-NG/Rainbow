import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised, validated access to runtime configuration.
///
/// ## Why this exists
///
/// Configuration used to be read ad-hoc as `dotenv.env['X'] ?? '<literal>'` at a
/// dozen call sites. That produced two classes of defect that are hard to see in
/// review and impossible to see in logs:
///
///  1. **Divergent fallbacks for the same key.** `emergency_provider.dart` read
///     `dotenv.env['DURESS_PIN'] ?? '9999'` while `emergency_active_screen.dart`
///     read `dotenv.env['DURESS_PIN']` with no fallback. The UI would refuse to
///     accept a PIN it considered unconfigured, while the provider would happily
///     match the hardcoded `'9999'`. Two layers, two different notions of truth.
///
///  2. **Silent degradation.** `main.dart` wraps `dotenv.load()` in a try/catch
///     that only logs a warning. A missing or unreadable `.env` therefore did not
///     stop the app — it started with every fallback active, including a duress
///     PIN of `9999` that is published in this repository.
///
/// ## Rules enforced here
///
///  * Safety-critical secrets (`SAFE_PIN`, `DURESS_PIN`, `HMAC_SECRET`) have **no
///    fallback**. A publicly-known duress code is more dangerous than no duress
///    code: a captor who has read this repo would know that `9999` signals
///    distress. Misconfiguration must be loud, not silently wrong.
///  * Every consumer reads the same accessor, so the UI and the provider can no
///    longer disagree about whether a PIN is configured.
///  * [validate] gives a single place to assert configuration at startup.
///
/// ## Known limitation (not fixed here)
///
/// These PINs are still **build-time constants shared by every install**, shipped
/// inside the APK (`.env` is declared as a Flutter asset in `pubspec.yaml`), so
/// they are extractable with `unzip`. The correct design is per-user PINs verified
/// server-side. This class does not change that; it only removes the divergence
/// and the dangerous defaults. See E2E_AUDIT_REPORT.md H-3.
class AppConfig {
  AppConfig._();

  static String? _read(String key) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[key];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  // ── Safety-critical: no fallbacks, ever ────────────────────────────────────

  /// PIN that resolves an active emergency normally. `null` when unconfigured.
  static String? get safePin => _read('SAFE_PIN');

  /// PIN that silently flags the cancellation as made under duress.
  /// `null` when unconfigured.
  static String? get duressPin => _read('DURESS_PIN');

  /// True only when both emergency PINs are configured.
  static bool get hasEmergencyPins => safePin != null && duressPin != null;

  /// Number of digits the PIN pad should auto-submit at.
  ///
  /// Previously derived from `SAFE_PIN` alone, which made any `DURESS_PIN`
  /// *longer* than `SAFE_PIN` impossible to enter: the pad submitted as soon as
  /// the safe-PIN length was reached, cleared the field, and the user could never
  /// type the remaining digits. Taking the maximum keeps both codes reachable.
  static int get pinEntryLength {
    final lengths = <int>[
      if (safePin != null) safePin!.length,
      if (duressPin != null) duressPin!.length,
    ];
    if (lengths.isEmpty) return 4;
    return lengths.reduce(math.max);
  }

  /// HMAC signing secret. `null` when unconfigured — callers must fail closed
  /// rather than sign with a well-known constant.
  static String? get hmacSecret => _read('HMAC_SECRET');

  // ── Non-safety-critical: defaults are acceptable ───────────────────────────

  static String? get termiiApiKey => _read('TERMII_API_KEY');
  static String get sosPhone => _read('SOS_PHONE') ?? '0800RAINBOWHQ';
  static String? get cloudinaryCloudName => _read('CLOUDINARY_CLOUD_NAME');
  static String? get cloudinaryUploadPreset => _read('CLOUDINARY_UPLOAD_PRESET');
  static String? get demoCitizenEmail => _read('DEMO_CITIZEN_EMAIL');
  static String? get demoCitizenPass => _read('DEMO_CITIZEN_PASS');
  static String? get agentDefaultPass => _read('AGENT_DEFAULT_PASS');

  /// Keys whose absence disables a safety-critical feature.
  static const List<String> requiredKeys = <String>[
    'SAFE_PIN',
    'DURESS_PIN',
    'HMAC_SECRET',
  ];

  /// Returns the required keys that are missing or blank.
  static List<String> missingRequiredKeys() =>
      requiredKeys.where((k) => _read(k) == null).toList();

  /// Call once after `dotenv.load()`. Logs loudly, and in debug builds throws so
  /// a misconfigured build cannot reach a tester unnoticed.
  static void validate() {
    final missing = missingRequiredKeys();
    if (missing.isEmpty) {
      debugPrint('[CONFIG] OK — all required keys present.');
      return;
    }
    final message =
        '[CONFIG] MISSING REQUIRED KEYS: ${missing.join(', ')}. '
        'Safety-critical features (duress PIN, request signing) are DISABLED. '
        'Copy .env.example to .env and fill it in.';
    debugPrint('🔥 $message');
    assert(false, message);
  }
}
