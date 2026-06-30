import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Representation of update status retrieved from server comparison.
class UpdateInfo {
  /// Whether a newer version is available.
  final bool hasUpdate;

  /// Whether the running version is deprecated and blocked.
  final bool isForceUpdate;

  /// The store/download link for platform package updates.
  final String updateUrl;

  /// The version name display string of the latest release.
  final String latestVersion;

  /// Creates a new update configuration container.
  UpdateInfo({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.updateUrl,
    required this.latestVersion,
  });
}

/// Service that retrieves the current version and checks against remote Firestore rules.
class UpdateService {
  final FirebaseFirestore? _firestore;

  /// Instantiate update check service.
  UpdateService(this._firestore);

  /// Compares local build identifier against database threshold settings.
  Future<UpdateInfo> checkForUpdates() async {
    try {
      final firestore = _firestore;
      if (kIsWeb || firestore == null) {
        return UpdateInfo(
          hasUpdate: false,
          isForceUpdate: false,
          updateUrl: '',
          latestVersion: '',
        );
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentVersion = packageInfo.version;

      final snapshot = await firestore.collection('config').doc('app').get();
      if (!snapshot.exists) {
        return UpdateInfo(
          hasUpdate: false,
          isForceUpdate: false,
          updateUrl: '',
          latestVersion: currentVersion,
        );
      }

      final data = snapshot.data() as Map<String, dynamic>;

      final int minBuild;
      final int latestBuild;
      final String storeUrl;
      final String latestVersionName;

      if (Platform.isAndroid) {
        minBuild = data['minAndroidBuild'] as int? ?? 0;
        latestBuild = data['latestAndroidBuild'] as int? ?? 0;
        storeUrl = data['androidStoreUrl'] as String? ?? '';
        latestVersionName = data['latestAndroidVersion'] as String? ?? currentVersion;
      } else {
        // Default to iOS parameters for iOS devices and macOS unit test environments
        minBuild = data['minIosBuild'] as int? ?? 0;
        latestBuild = data['latestIosBuild'] as int? ?? 0;
        storeUrl = data['iosStoreUrl'] as String? ?? '';
        latestVersionName = data['latestIosVersion'] as String? ?? currentVersion;
      }

      final isForceUpdate = currentBuildNumber < minBuild;
      final hasUpdate = currentBuildNumber < latestBuild;

      return UpdateInfo(
        hasUpdate: hasUpdate,
        isForceUpdate: isForceUpdate,
        updateUrl: storeUrl,
        latestVersion: latestVersionName,
      );
    } catch (e) {
      debugPrint('⚠️ [UPDATE_CHECK_ERR] Check failed: $e');
      return UpdateInfo(
        hasUpdate: false,
        isForceUpdate: false,
        updateUrl: '',
        latestVersion: '',
      );
    }
  }
}

/// Provider wrapper around the UpdateService.
final updateServiceProvider = Provider<UpdateService>((ref) {
  FirebaseFirestore? firestore;
  try {
    firestore = FirebaseFirestore.instance;
  } catch (e) {
    debugPrint('⚠️ [UPDATE_SERVICE] Firebase not initialized: $e');
  }
  return UpdateService(firestore);
});
