/// Shared cloud-password rules for registration and reset (must match Laravel).
class PasswordRules {
  PasswordRules._();

  static const int minLength = 8;
  static final RegExp _letter = RegExp(r'[A-Za-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9]');

  static const String requirementHint =
      'At least 8 characters, with a letter, a number, and a symbol (e.g. !@#\$%)';

  /// Null when valid; otherwise a teacher-facing error.
  static String? validationError(String password) {
    final value = password;
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (!_letter.hasMatch(value)) {
      return 'Password must include at least one letter.';
    }
    if (!_digit.hasMatch(value)) {
      return 'Password must include at least one number.';
    }
    if (!_symbol.hasMatch(value)) {
      return 'Password must include at least one special character (e.g. !@#\$%).';
    }
    return null;
  }

  static bool isValid(String password) => validationError(password) == null;
}
