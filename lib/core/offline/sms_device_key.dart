/// The per-device key that makes the SMS fallback worth having.
///
/// An alert sent by SMS is encrypted and authenticated with a 32-byte key that
/// belongs to this handset alone. This is where that key is obtained, kept and
/// given up.
///
/// ## Obtained once, while there is still a network
///
/// The whole point of the channel is that it works when there is no data, so
/// the key cannot be fetched at the moment it is needed. It is issued at
/// registration — the first time the app has a session AND a connection — and
/// held from then on. A handset that has never been online cannot use the SMS
/// fallback, and there is no way around that: a key agreed over the air with
/// nobody to agree with is not a key.
///
/// ## Kept in secure storage, not SharedPreferences
///
/// `flutter_secure_storage` puts it in the Android Keystore / iOS Keychain.
/// SharedPreferences is a world-readable XML file on a rooted device, and this
/// key can both decrypt and forge that citizen's emergency traffic.
///
/// ## Given up on sign-out
///
/// Both ends: the local copy is deleted and the server retires it. Signing out
/// already had to be taught to stop location tracking for the same reason —
/// it is the clearest statement a person can make that this handset is no
/// longer theirs to speak for.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';

/// A device's SMS credentials: which key, and HQ's handle for it.
@immutable
class SmsDeviceKey {
  /// Creates a key pair-up.
  const SmsDeviceKey({required this.deviceRef, required this.secret});

  /// HQ's four-byte handle, sent in the clear so ingest knows what to try.
  final Uint8List deviceRef;

  /// The 32-byte shared secret.
  final Uint8List secret;

  /// Whether this is structurally usable.
  bool get isValid => deviceRef.length == 4 && secret.length == 32;
}

/// Obtains, stores and retires the SMS device key.
class SmsDeviceKeyService {
  /// Creates a service. [storage] is injectable so the logic can be tested
  /// without a keystore.
  SmsDeviceKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _refKey = 'sms_device_ref';
  static const _secretKey = 'sms_device_secret';

  /// Test seam: the server round-trip, so provisioning can be tested without
  /// Supabase. Returns `{device_ref, secret}` as base64, or null.
  @visibleForTesting
  static Future<Map<String, String>?> Function()? registerOverride;

  /// The key held on this device, or null if it has never registered.
  Future<SmsDeviceKey?> current() async {
    try {
      final ref = await _storage.read(key: _refKey);
      final secret = await _storage.read(key: _secretKey);
      if (ref == null || secret == null) return null;
      final key = SmsDeviceKey(
        deviceRef: Uint8List.fromList(base64Decode(ref)),
        secret: Uint8List.fromList(base64Decode(secret)),
      );
      // A key of the wrong shape is worse than no key: it would produce
      // messages HQ silently cannot open. Treat it as absent so the next
      // provision replaces it.
      return key.isValid ? key : null;
    } catch (e) {
      debugPrint('[SMS_KEY] could not read the stored key: $e');
      return null;
    }
  }

  /// Makes sure this device has a key, obtaining one if it does not.
  ///
  /// Safe to call on every sign-in: it does nothing when a key is already
  /// held, so it costs one secure-storage read in the common case. It is NOT
  /// safe to call when offline — it will simply fail and return null, which is
  /// why it belongs on the sign-in path rather than on the SOS path.
  Future<SmsDeviceKey?> ensureProvisioned() async {
    final existing = await current();
    if (existing != null) return existing;
    return provision();
  }

  /// Obtains a fresh key, replacing any this device holds.
  ///
  /// The server retires the previous key for this user, so calling this twice
  /// does not leave an old handset able to speak.
  Future<SmsDeviceKey?> provision() async {
    try {
      final result = registerOverride != null
          ? await registerOverride!()
          : await _registerOnServer();
      if (result == null) return null;

      final key = SmsDeviceKey(
        deviceRef: Uint8List.fromList(base64Decode(result['device_ref']!)),
        secret: Uint8List.fromList(base64Decode(result['secret']!)),
      );
      if (!key.isValid) {
        debugPrint('[SMS_KEY] server returned material of the wrong shape');
        return null;
      }
      await _storage.write(key: _refKey, value: result['device_ref']);
      await _storage.write(key: _secretKey, value: result['secret']);
      return key;
    } catch (e) {
      // Never fatal. A device with no SMS key still works normally; it just
      // has one fewer way to reach HQ when the data connection dies.
      debugPrint('[SMS_KEY] provisioning failed: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _registerOnServer() async {
    final rows = await SupabaseConfig.client.rpc<dynamic>('register_sms_device');
    final list = rows is List ? rows : <dynamic>[rows];
    if (list.isEmpty) return null;
    final row = Map<String, dynamic>.from(list.first as Map);
    // PostgREST renders BYTEA as a `\x...` hex string.
    return {
      'device_ref': base64Encode(_fromPgBytea(row['device_ref'] as String)),
      'secret': base64Encode(_fromPgBytea(row['secret'] as String)),
    };
  }

  static Uint8List _fromPgBytea(String value) {
    final hex = value.startsWith(r'\x') ? value.substring(2) : value;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Forgets the key locally and retires it at HQ.
  ///
  /// Local deletion happens FIRST and unconditionally. If the server call
  /// fails — which it will, if the reason for signing out is a dead network —
  /// the handset must still stop holding material it can send emergencies
  /// with.
  Future<void> forget() async {
    try {
      await _storage.delete(key: _refKey);
      await _storage.delete(key: _secretKey);
    } catch (e) {
      debugPrint('[SMS_KEY] could not clear the local key: $e');
    }
    try {
      await SupabaseConfig.client.rpc<dynamic>('revoke_sms_device_keys');
    } catch (e) {
      debugPrint('[SMS_KEY] could not retire the key at HQ: $e');
    }
  }
}
