import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';

class UpdateInfo {

  UpdateInfo({
    required this.hasUpdate,
    required this.isForceUpdate,
    required this.updateUrl,
    required this.latestVersion,
  });
  final bool hasUpdate;
  final bool isForceUpdate;
  final String updateUrl;
  final String latestVersion;
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

class UpdateService {
  Future<UpdateInfo> checkAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    try {
      final response = await SupabaseConfig.client
          .from('app_config')
          .select()
          .inFilter('key', ['min_version', 'latest_version', 'force_update', 'update_url']);

      var minVersion = '1.0.0';
      var latestVersion = '1.0.0';
      var forceUpdate = false;
      var updateUrl = '';

      for (final row in response) {
        if (row['key'] == 'min_version') minVersion = row['value']?.toString() ?? '1.0.0';
        if (row['key'] == 'latest_version') latestVersion = row['value']?.toString() ?? '1.0.0';
        if (row['key'] == 'force_update') forceUpdate = row['value']?.toString() == 'true';
        if (row['key'] == 'update_url') updateUrl = row['value']?.toString() ?? '';
      }

      final isForceUpdateResult = forceUpdate || currentVersion.compareTo(minVersion) < 0;
      final hasUpdate = currentVersion.compareTo(latestVersion) < 0;

      return UpdateInfo(
        hasUpdate: hasUpdate,
        isForceUpdate: isForceUpdateResult,
        updateUrl: updateUrl,
        latestVersion: latestVersion,
      );
    } catch (e) {
      return UpdateInfo(
        hasUpdate: false,
        isForceUpdate: false,
        updateUrl: '',
        latestVersion: currentVersion,
      );
    }
  }

  Future<UpdateInfo> checkForUpdates() async {
    return checkAppVersion();
  }
}
