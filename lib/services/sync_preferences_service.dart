import 'package:shared_preferences/shared_preferences.dart';

class SyncPreferencesService {
  SyncPreferencesService._();

  static const String _lastSyncAtKey = 'sync_last_completed_at';
  static const String _lastPullAtKey = 'sync_last_pull_at';
  static const String _autoSyncOnWifiKey = 'sync_auto_on_wifi';

  /// Auto-sync on connectivity is on by default so grades don't strand on one phone.
  static Future<bool> getAutoSyncOnWifi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSyncOnWifiKey) ?? true;
  }

  static Future<void> setAutoSyncOnWifi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncOnWifiKey, value);
  }

  static Future<DateTime?> getLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastSyncAtKey) ?? '');
  }

  static Future<DateTime?> getLastPullAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastPullAtKey) ?? '');
  }

  static Future<void> setLastSyncAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncAtKey, value.toIso8601String());
  }

  static Future<void> setLastPullAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPullAtKey, value.toIso8601String());
  }
}
