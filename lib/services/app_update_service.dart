import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:omr_app/services/api_service.dart';

/// Result of an update check. [updateAvailable] is only true when a newer
/// build number is published on the school API `app_releases` table.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.updateAvailable,
    required this.currentVersion,
    this.latestVersion,
    this.downloadUrl,
    this.notes,
    this.mandatory = false,
  });

  final bool updateAvailable;
  final String currentVersion;
  final String? latestVersion;
  final String? downloadUrl;
  final String? notes;
  final bool mandatory;
}

class AppUpdateService {
  AppUpdateService._();

  static Future<AppUpdateInfo> check() async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final currentVersion = '${info.version}+${info.buildNumber}';

    if (!ApiService.isReady || !ApiService.hasActiveSession) {
      return AppUpdateInfo(
        updateAvailable: false,
        currentVersion: currentVersion,
      );
    }

    try {
      final response = await ApiService.getJson('/app-releases/latest');
      final row = response['release'];
      if (row is! Map) {
        return AppUpdateInfo(
          updateAvailable: false,
          currentVersion: currentVersion,
        );
      }

      final latestBuild = (row['build_number'] as num?)?.toInt() ?? 0;
      final available = latestBuild > currentBuild;

      return AppUpdateInfo(
        updateAvailable: available,
        currentVersion: currentVersion,
        latestVersion: row['version_name']?.toString(),
        downloadUrl: row['download_url']?.toString(),
        notes: row['notes']?.toString(),
        mandatory: row['mandatory'] == true,
      );
    } catch (error) {
      debugPrint('App update check skipped: $error');
      return AppUpdateInfo(
        updateAvailable: false,
        currentVersion: currentVersion,
      );
    }
  }
}
