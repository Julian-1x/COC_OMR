import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPreferencesService {
  OnboardingPreferencesService._();

  static const String _completedKey = 'onboarding_completed_v1';
  static const String _customSheetGuideKey = 'custom_sheet_editor_guide_seen_v1';

  static String _completedKeyFor(String? teacherId) {
    final id = teacherId?.trim() ?? '';
    if (id.isEmpty) {
      return _completedKey;
    }
    return '${_completedKey}_$id';
  }

  /// Prefer per-teacher completion so a new account on a shared phone still
  /// sees the welcome tutorial.
  static Future<bool> hasCompletedOnboarding({String? teacherId}) async {
    final prefs = await SharedPreferences.getInstance();
    final scoped = _completedKeyFor(teacherId);
    if (prefs.containsKey(scoped)) {
      return prefs.getBool(scoped) ?? false;
    }
    // Legacy device-wide flag (pre per-teacher keys).
    if (teacherId == null || teacherId.trim().isEmpty) {
      return prefs.getBool(_completedKey) ?? false;
    }
    return false;
  }

  static Future<void> setOnboardingCompleted({String? teacherId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKeyFor(teacherId), true);
  }

  static Future<bool> hasSeenCustomSheetGuide() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_customSheetGuideKey) ?? false;
  }

  static Future<void> setCustomSheetGuideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_customSheetGuideKey, true);
  }
}
