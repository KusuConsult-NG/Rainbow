import 'dart:convert';
import 'package:crypto/crypto.dart';

class HmacService {
  static const String _sharedSecret = "RAINBOW_PLATEAU_SECURE_HMAC_GATEWAY_KEY_2026";

  /// Generates a unique HMAC signature for the given payload using a derived key
  static String generateSignature({
    required String uid,
    required String badgeId,
    required Map<String, dynamic> payload,
    required int timestamp,
  }) {
    // 1. Derive a unique device-specific key using user credentials
    final keySource = "$_sharedSecret:$uid:$badgeId";
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
