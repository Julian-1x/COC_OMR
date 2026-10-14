import 'package:shared_preferences/shared_preferences.dart';

/// Saves in-progress teacher registration fields on this phone.
/// Password is never stored.
class RegisterFormDraft {
  const RegisterFormDraft({
    this.lastName = '',
    this.firstName = '',
    this.suffix = '',
    this.email = '',
    this.department,
    this.preferRegisterTab = false,
  });

  final String lastName;
  final String firstName;
  final String suffix;
  final String email;
  final String? department;
  final bool preferRegisterTab;

  bool get hasAnyField =>
      lastName.trim().isNotEmpty ||
      firstName.trim().isNotEmpty ||
      suffix.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      (department != null && department!.trim().isNotEmpty);
}

class RegisterFormDraftService {
  RegisterFormDraftService._();

  static const _lastNameKey = 'register_draft_last_name_v1';
  static const _firstNameKey = 'register_draft_first_name_v1';
  static const _suffixKey = 'register_draft_suffix_v1';
  static const _emailKey = 'register_draft_email_v1';
  static const _departmentKey = 'register_draft_department_v1';
  static const _preferRegisterKey = 'register_draft_prefer_register_v1';

  static Future<RegisterFormDraft> load() async {
    final prefs = await SharedPreferences.getInstance();
    return RegisterFormDraft(
      lastName: prefs.getString(_lastNameKey) ?? '',
      firstName: prefs.getString(_firstNameKey) ?? '',
      suffix: prefs.getString(_suffixKey) ?? '',
      email: prefs.getString(_emailKey) ?? '',
      department: prefs.getString(_departmentKey),
      preferRegisterTab: prefs.getBool(_preferRegisterKey) ?? false,
    );
  }

  static Future<void> save(RegisterFormDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!draft.hasAnyField && !draft.preferRegisterTab) {
      await clear();
      return;
    }
    await prefs.setString(_lastNameKey, draft.lastName.trim());
    await prefs.setString(_firstNameKey, draft.firstName.trim());
    await prefs.setString(_suffixKey, draft.suffix.trim());
    await prefs.setString(_emailKey, draft.email.trim().toLowerCase());
    final dept = draft.department?.trim().toUpperCase();
    if (dept == null || dept.isEmpty) {
      await prefs.remove(_departmentKey);
    } else {
      await prefs.setString(_departmentKey, dept);
    }
    await prefs.setBool(_preferRegisterKey, draft.preferRegisterTab);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastNameKey);
    await prefs.remove(_firstNameKey);
    await prefs.remove(_suffixKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_departmentKey);
    await prefs.remove(_preferRegisterKey);
  }
}
