import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdateInfo {
  final bool hasUpdate;
  final bool isForceUpdate;
  final String updateUrl;
  final String latestVersion;

  UpdateInfo({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.updateUrl,
    required this.latestVersion,
  });
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

class UpdateService {
  Future<UpdateInfo> checkAppVersion() async {
    return UpdateInfo(
      hasUpdate: false,
      isForceUpdate: false,
      updateUrl: '',
      latestVersion: '2.0.0',
    );
  }

  Future<UpdateInfo> checkForUpdates() async {
    return checkAppVersion();
  }
}
