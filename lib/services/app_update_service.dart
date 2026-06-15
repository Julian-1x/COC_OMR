import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:omr_app/services/supabase_service.dart';

/// Result of an update check. [updateAvailable] is only true when a newer
/// build number is published in Supabase `app_releases`.
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

/// Optional, safe update check.
///
/// Reads a single public row from a Supabase `app_releases` table:
///   - `build_number` (int)   — latest published build
///   - `version_name` (text)  — e.g. "1.0.1"
///   - `download_url` (text)  — where to get the APK
///   - `notes` (text, null)   — short "what's new"
///   - `mandatory` (bool)     — force update
///
/// If Supabase is not ready or the table/row is missing, this returns
/// `updateAvailable: false` and never throws — so it can't produce false
/// prompts before the school sets it up.
class AppUpdateService {
  AppUpdateService._();

  static Future<AppUpdateInfo> check() async {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final currentVersion = '${info.version}+${info.buildNumber}';

    final client = SupabaseService.client;
    if (client == null) {
      return AppUpdateInfo(
        updateAvailable: false,
        currentVersion: currentVersion,
      );
    }

    try {
      final row = await client
          .from('app_releases')
          .select('build_number, version_name, download_url, notes, mandatory')
          .order('build_number', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) {
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
