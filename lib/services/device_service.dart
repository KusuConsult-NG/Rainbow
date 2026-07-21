import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';

class DeviceService {
  factory DeviceService() => _instance;
  DeviceService._internal();
  static final DeviceService _instance = DeviceService._internal();

  final _storage = const FlutterSecureStorage();

  Future<String> getDeviceId() async {
    final deviceId = await _storage.read(key: 'device_fingerprint');
    if (deviceId != null) return deviceId;

    final platform = Platform.operatingSystem;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newId = '${platform}_${timestamp}_${DateTime.now().microsecond}';
    await _storage.write(key: 'device_fingerprint', value: newId);
    return newId;
  }

  Future<void> registerDeviceSession(String userId) async {
    try {
      final deviceId = await getDeviceId();
      await SupabaseConfig.client.from('profiles').update({
        'last_device_id': deviceId,
        'last_login_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {}
  }
}
