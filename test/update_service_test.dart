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

    test('Should instantiate UpdateInfo correctly', () {
      final info = UpdateInfo(
        hasUpdate: true,
        isForceUpdate: false,
        updateUrl: 'https://example.com',
        latestVersion: '2.0.0',
      );

      expect(info.hasUpdate, isTrue);
      expect(info.isForceUpdate, isFalse);
      expect(info.updateUrl, equals('https://example.com'));
      expect(info.latestVersion, equals('2.0.0'));
    });
  });
}
