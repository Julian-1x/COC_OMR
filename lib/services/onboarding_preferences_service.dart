import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPreferencesService {
  OnboardingPreferencesService._();

  static const String _completedKey = 'onboarding_completed_v1';

  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  static Future<void> setOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
