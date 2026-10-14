/// Shared cloud-password rules for registration and reset (must match Laravel).
class PasswordRules {
  PasswordRules._();

  static const int minLength = 8;
  static final RegExp _lowercase = RegExp(r'[a-z]');
  static final RegExp _uppercase = RegExp(r'[A-Z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9]');

  static const String requirementHint =
      'At least 8 characters, with upper and lowercase letters, a number, and a symbol (e.g. !@#\$%)';

  /// Live checklist items — order matches teacher-facing UI.
  static const List<PasswordRequirement> requirements = [
    PasswordRequirement(
      id: 'length',
      label: 'Minimum of 8 characters',
    ),
    PasswordRequirement(
      id: 'lowercase',
      label: 'At least 1 lowercase letter (a-z)',
    ),
    PasswordRequirement(
      id: 'uppercase',
      label: 'At least 1 uppercase letter (A-Z)',
    ),
    PasswordRequirement(
      id: 'number',
      label: 'At least 1 number',
    ),
    PasswordRequirement(
      id: 'symbol',
      label: 'At least 1 special character (e.g. ! @ # \$ %)',
    ),
  ];

  static bool meets(String id, String password) {
    switch (id) {
      case 'length':
        return password.length >= minLength;
      case 'lowercase':
        return _lowercase.hasMatch(password);
      case 'uppercase':
        return _uppercase.hasMatch(password);
      case 'number':
        return _digit.hasMatch(password);
      case 'symbol':
        return _symbol.hasMatch(password);
      default:
        return false;
    }
  }

  /// Null when valid; otherwise a teacher-facing error.
  static String? validationError(String password) {
    for (final requirement in requirements) {
      if (!meets(requirement.id, password)) {
        return switch (requirement.id) {
          'length' => 'Password must be at least $minLength characters.',
          'lowercase' => 'Password must include at least one lowercase letter.',
          'uppercase' => 'Password must include at least one uppercase letter.',
          'number' => 'Password must include at least one number.',
          'symbol' =>
            'Password must include at least one special character (e.g. !@#\$%).',
          _ => 'Password does not meet requirements.',
        };
      }
    }
    return null;
  }

  static bool isValid(String password) => validationError(password) == null;
}

class PasswordRequirement {
  final String id;
  final String label;

  const PasswordRequirement({
    required this.id,
    required this.label,
  });
}
