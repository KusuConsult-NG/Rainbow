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

      final isForceUpdateResult =
          forceUpdate || compareVersions(currentVersion, minVersion) < 0;
      final hasUpdate = compareVersions(currentVersion, latestVersion) < 0;

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

  /// Compares two dotted version strings numerically.
  ///
  /// Returns a negative number when [a] is older than [b], zero when they are
  /// equivalent, and a positive number when [a] is newer.
  ///
  /// A plain `String.compareTo` orders versions lexically, which gets every
  /// multi-digit segment wrong — `'1.0.10'.compareTo('1.0.9')` is negative, so
  /// 1.0.10 was treated as older than 1.0.9 and the update prompt stopped
  /// firing at double-digit patch numbers. Missing segments are treated as
  /// zero, and any non-numeric suffix (`1.2.3+45`, `1.2.3-beta`) is ignored.
  static int compareVersions(String a, String b) {
    final left = _segments(a);
    final right = _segments(b);
    final length = left.length > right.length ? left.length : right.length;

    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static List<int> _segments(String version) {
    final core = version.trim().split(RegExp('[+-]')).first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }
}
