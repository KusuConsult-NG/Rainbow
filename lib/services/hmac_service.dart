import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:rainbow_app/core/config/app_config.dart';

class HmacService {
  /// Thrown when signing is attempted without HMAC_SECRET configured.
  ///
  /// This previously fell back to a constant committed to this repository, which
  /// meant a misconfigured build produced signatures that proved nothing while
  /// looking valid. Failing loudly is the only safe behaviour for a signature.
  static const String missingSecretMessage =
      'HMAC_SECRET is not configured — refusing to sign. See AppConfig.validate().';

  /// Generates a unique HMAC signature for the given payload using a derived key
  static String generateSignature({
    required String uid,
    required String badgeId,
    required Map<String, dynamic> payload,
    required int timestamp,
  }) {
    // 1. Derive a unique device-specific key using user credentials
    final secret = AppConfig.hmacSecret;
    if (secret == null) {
      throw StateError(missingSecretMessage);
    }
    final keySource = "$secret:$uid:$badgeId";
    final keyBytes = utf8.encode(keySource);

    // 2. Normalize and stringify payload sorted by keys
    final sortedPayload = _sortMap(payload);
    final payloadString = jsonEncode(sortedPayload);
    final signText = "$payloadString:$timestamp";

    // 3. Compute HmacSHA256
    final hmac = Hmac(sha256, keyBytes);
    final signature = hmac.convert(utf8.encode(signText));
    return signature.toString();
  }

  static Map<String, dynamic> _sortMap(Map<String, dynamic> map) {
    final sorted = <String, dynamic>{};
    final keys = map.keys.toList()..sort();
    for (final key in keys) {
      final value = map[key];
      if (value is Map<String, dynamic>) {
        sorted[key] = _sortMap(value);
      } else {
        sorted[key] = value;
      }
    }
    return sorted;
  }
}
