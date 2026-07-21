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

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
