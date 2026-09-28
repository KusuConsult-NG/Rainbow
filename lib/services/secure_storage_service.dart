import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Documentation for this public member.

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Documentation for this public member.

class SecureStorageService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const _badgeKey = 'staff_badge_id';
  static const _pinKey = 'staff_pin';

  /// Documentation for this public member.

  Future<void> saveCredentials(String badgeId, String pin) async {
    await _storage.write(key: _badgeKey, value: badgeId);
    await _storage.write(key: _pinKey, value: pin);
  }

  /// Documentation for this public member.

  Future<Map<String, String>?> getCredentials() async {
    final badgeId = await _storage.read(key: _badgeKey);
    final pin = await _storage.read(key: _pinKey);

    if (badgeId != null && pin != null) {
      return {'badgeId': badgeId, 'pin': pin};
    }
    return null;
  }

  /// Documentation for this public member.

  Future<bool> hasCredentials() async {
    final badgeId = await _storage.read(key: _badgeKey);
    return badgeId != null && badgeId.isNotEmpty;
  }

  /// Documentation for this public member.

  Future<void> clearCredentials() async {
    await _storage.delete(key: _badgeKey);
    await _storage.delete(key: _pinKey);
  }

  /// Reads a JSON object previously written by [writeJson].
  ///
  /// Anything that is not readable as an object comes back null rather than
  /// throwing. Callers use this for state they compare against — a stored
  /// value from an older build must degrade to "unknown", never to a false
  /// claim about what changed.
  Future<Map<String, dynamic>?> readJson(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Writes a JSON object.
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    await _storage.write(key: key, value: jsonEncode(value));
  }

  /// Removes one key.
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  /// Documentation for this public member.
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  /// Documentation for this public member.
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
