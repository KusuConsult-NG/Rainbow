// The key the SMS fallback depends on: where it comes from, and when it goes.
//
// It is obtained once while there is still a network, because a channel that
// exists for the case where there is no data cannot fetch a key at the moment
// it is needed. It lives in the keystore rather than SharedPreferences,
// because it can both decrypt and forge that citizen's emergency traffic. And
// it is given up on sign-out, at both ends.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/offline/sms_device_key.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';

/// An in-memory stand-in for the keystore.
class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};
  int writes = 0;

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value,
      dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions,
      dynamic mOptions, dynamic wOptions}) async {
    writes++;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions, dynamic wOptions}) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final goodRef = base64Encode(Uint8List.fromList([1, 2, 3, 4]));
  final goodSecret = base64Encode(
      Uint8List.fromList(List<int>.generate(32, (i) => i)));

  tearDown(() {
    SmsDeviceKeyService.registerOverride = null;
    AuthService.forgetSmsKeyOverride = null;
    AuthService.stopTrackingOverride = null;
  });

  group('obtaining a key', () {
    test('a device with no key has none', () async {
      final svc = SmsDeviceKeyService(storage: _MemoryStorage());
      expect(await svc.current(), isNull);
    });

    test('provisioning stores a usable key', () async {
      final store = _MemoryStorage();
      SmsDeviceKeyService.registerOverride =
          () async => {'device_ref': goodRef, 'secret': goodSecret};

      final key = await SmsDeviceKeyService(storage: store).provision();
      expect(key, isNotNull);
      expect(key!.isValid, isTrue);
      expect(key.deviceRef.length, 4);
      expect(key.secret.length, 32);
      expect(store.values.containsKey('sms_device_secret'), isTrue);
    });

    test('a stored key is read back intact', () async {
      final store = _MemoryStorage();
      SmsDeviceKeyService.registerOverride =
          () async => {'device_ref': goodRef, 'secret': goodSecret};
      final svc = SmsDeviceKeyService(storage: store);
      final written = await svc.provision();
      final read = await svc.current();
      expect(read!.deviceRef, written!.deviceRef);
      expect(read.secret, written.secret);
    });

    test('ensureProvisioned does not re-register when a key is held', () async {
      final store = _MemoryStorage();
      var calls = 0;
      SmsDeviceKeyService.registerOverride = () async {
        calls++;
        return {'device_ref': goodRef, 'secret': goodSecret};
      };
      final svc = SmsDeviceKeyService(storage: store);
      await svc.ensureProvisioned();
      await svc.ensureProvisioned();
      await svc.ensureProvisioned();
      expect(calls, 1, reason: 'it is called on every sign-in');
    });

    test('material of the wrong shape is refused, not stored', () async {
      // A key of the wrong length would produce messages HQ silently cannot
      // open — worse than having none, because the phone would believe it had
      // a working fallback.
      final store = _MemoryStorage();
      SmsDeviceKeyService.registerOverride = () async => {
            'device_ref': base64Encode(Uint8List.fromList([1, 2])),
            'secret': goodSecret,
          };
      expect(await SmsDeviceKeyService(storage: store).provision(), isNull);
      expect(store.values, isEmpty);
    });

    test('a corrupted stored key reads as absent, so it gets replaced', () async {
      final store = _MemoryStorage()
        ..values['sms_device_ref'] = goodRef
        ..values['sms_device_secret'] = base64Encode(Uint8List(8));
      expect(await SmsDeviceKeyService(storage: store).current(), isNull);
    });

    test('a failed registration is not fatal', () async {
      // No key means one fewer way to reach HQ. It must not mean a broken app.
      SmsDeviceKeyService.registerOverride =
          () async => throw StateError('offline');
      expect(
        await SmsDeviceKeyService(storage: _MemoryStorage()).provision(),
        isNull,
      );
    });
  });

  group('giving it up', () {
    test('forget clears the local copy', () async {
      final store = _MemoryStorage();
      SmsDeviceKeyService.registerOverride =
          () async => {'device_ref': goodRef, 'secret': goodSecret};
      final svc = SmsDeviceKeyService(storage: store);
      await svc.provision();
      expect(store.values, isNotEmpty);

      await svc.forget();
      expect(
        store.values,
        isEmpty,
        reason: 'the local copy goes even when HQ cannot be reached to retire '
            'it — which is exactly the case when the network is why you are '
            'signing out',
      );
    });

    test('signing out gives up the key', () async {
      var forgotten = false;
      AuthService.stopTrackingOverride = () async {};
      AuthService.forgetSmsKeyOverride = () async {
        forgotten = true;
      };
      try {
        await AuthService(SecureStorageService()).signOut();
      } catch (_) {
        // no Supabase client under `flutter test`
      }
      expect(
        forgotten,
        isTrue,
        reason: 'the key can both send an emergency in that person\'s name and '
            'decrypt the ones they send, so it goes when they do',
      );
    });

    test('a failure to retire it does not abandon the sign-out', () async {
      var attempted = false;
      AuthService.stopTrackingOverride = () async {};
      AuthService.forgetSmsKeyOverride = () async {
        attempted = true;
        throw StateError('no network');
      };
      try {
        await AuthService(SecureStorageService()).signOut();
      } catch (_) {
        // expected
      }
      expect(attempted, isTrue);
    });
  });

  group('signing IN is where the key comes from', () {
    // The channels authenticate with a key fetched from the server, and their
    // whole purpose is to work when there is no data — so the key cannot be
    // fetched at the moment it is needed. Sign-in is the one moment the app is
    // guaranteed to have both a session and a network.
    tearDown(() => AuthService.provisionSmsKeyOverride = null);

    test('a new session provisions the device key', () async {
      var provisioned = false;
      AuthService.provisionSmsKeyOverride = () async => provisioned = true;
      final ok = await AuthService(SecureStorageService())
          .onSessionEstablished(true);
      expect(ok, isTrue);
      expect(provisioned, isTrue,
          reason: 'otherwise the SMS and mesh channels are dead on a handset '
              'that has been signed in for months');
    });

    test('a failed sign-in provisions nothing', () async {
      var provisioned = false;
      AuthService.provisionSmsKeyOverride = () async => provisioned = true;
      final ok = await AuthService(SecureStorageService())
          .onSessionEstablished(false);
      expect(ok, isFalse);
      expect(provisioned, isFalse);
    });

    test('a provisioning failure does not block the sign-in', () async {
      // A handset with no key still works normally; it just has one fewer way to
      // reach HQ when the network dies. Refusing the sign-in over it would be a
      // far worse outcome than the thing it protects against.
      AuthService.provisionSmsKeyOverride =
          () async => throw StateError('offline at sign-in');
      final ok = await AuthService(SecureStorageService())
          .onSessionEstablished(true);
      expect(ok, isTrue);
    });
  });
}
