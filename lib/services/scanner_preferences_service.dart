import 'package:shared_preferences/shared_preferences.dart';

/// Scanner tuning preferences (exam-day speed vs thorough processing).
class ScannerPreferencesService {
  ScannerPreferencesService._();

  static const String _examTurboModeKey = 'scanner_exam_turbo_mode';

  /// Faster exam-day pipeline on by default.
  static Future<bool> getExamTurboMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_examTurboModeKey) ?? true;
  }

  static Future<void> setExamTurboMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_examTurboModeKey, value);
  }
}
