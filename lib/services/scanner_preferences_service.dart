import 'package:shared_preferences/shared_preferences.dart';

/// Scanner tuning preferences (exam-day speed vs thorough processing).
class ScannerPreferencesService {
  ScannerPreferencesService._();

  static const String _examTurboModeKey = 'scanner_exam_turbo_mode';
  static const String _autoCaptureKey = 'scanner_auto_capture_enabled';
  static const String _reviewBeforeSaveKey = 'scanner_review_before_save';

  /// Faster exam-day pipeline on by default.
  static Future<bool> getExamTurboMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_examTurboModeKey) ?? true;
  }

  static Future<void> setExamTurboMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_examTurboModeKey, value);
  }

  /// Auto-capture when the sheet is aligned. Off by default (opt-in).
  static Future<bool> getAutoCaptureEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCaptureKey) ?? false;
  }

  static Future<void> setAutoCaptureEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCaptureKey, value);
  }

  /// Show Scan Review before saving. On by default.
  static Future<bool> getReviewBeforeSave() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reviewBeforeSaveKey) ?? true;
  }

  static Future<void> setReviewBeforeSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reviewBeforeSaveKey, value);
  }
}
