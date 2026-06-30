import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rainbow_app/services/update_service.dart';

void main() {
  group('UpdateService Unit Tests', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'Rainbow App',
        packageName: 'com.RainbowEwer.RainbowEwer',
        version: '1.0.2',
        buildNumber: '12',
        buildSignature: 'signature',
        installerStore: null,
      );
    });

    test('Should return no update when config document is missing', () async {
      final firestore = FakeFirebaseFirestore();
      final service = UpdateService(firestore);

      final updateInfo = await service.checkForUpdates();

      expect(updateInfo.hasUpdate, isFalse);
      expect(updateInfo.isForceUpdate, isFalse);
    });

    test('Should return force update when build code is below minimum', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('config').doc('app').set({
        'minIosBuild': 13,
        'latestIosBuild': 14,
        'iosStoreUrl': 'https://apps.apple.com/app/id6770007275',
        'latestIosVersion': '1.0.3',
      });

      final service = UpdateService(firestore);
      final updateInfo = await service.checkForUpdates();

      // Current mock is 12, min is 13.
      expect(updateInfo.hasUpdate, isTrue);
      expect(updateInfo.isForceUpdate, isTrue);
      expect(updateInfo.updateUrl, equals('https://apps.apple.com/app/id6770007275'));
      expect(updateInfo.latestVersion, equals('1.0.3'));
    });

    test('Should return optional update when build code is below latest but above minimum', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('config').doc('app').set({
        'minIosBuild': 10,
        'latestIosBuild': 14,
        'iosStoreUrl': 'https://apps.apple.com/app/id6770007275',
        'latestIosVersion': '1.0.3',
      });

      final service = UpdateService(firestore);
      final updateInfo = await service.checkForUpdates();

      // Current mock is 12, min is 10, latest is 14.
      expect(updateInfo.hasUpdate, isTrue);
      expect(updateInfo.isForceUpdate, isFalse);
      expect(updateInfo.updateUrl, equals('https://apps.apple.com/app/id6770007275'));
      expect(updateInfo.latestVersion, equals('1.0.3'));
    });

    test('Should return no update when build code is up to date', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('config').doc('app').set({
        'minIosBuild': 10,
        'latestIosBuild': 12,
        'iosStoreUrl': 'https://apps.apple.com/app/id6770007275',
        'latestIosVersion': '1.0.2',
      });

      final service = UpdateService(firestore);
      final updateInfo = await service.checkForUpdates();

      // Current mock is 12, latest is 12.
      expect(updateInfo.hasUpdate, isFalse);
      expect(updateInfo.isForceUpdate, isFalse);
    });
  });
}
