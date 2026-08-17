import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/utils/password_rules.dart';

void main() {
  group('PasswordRules', () {
    test('rejects short passwords', () {
      expect(PasswordRules.validationError('Ab1!'), isNotNull);
    });

    test('requires letter, number, and symbol', () {
      expect(PasswordRules.validationError('abcdefgh'), isNotNull);
      expect(PasswordRules.validationError('abcdefg1'), isNotNull);
      expect(PasswordRules.validationError('abcdefg!'), isNotNull);
      expect(PasswordRules.validationError('ABCD1234'), isNotNull);
    });

    test('accepts a strong password', () {
      expect(PasswordRules.validationError('Teacher1!'), isNull);
      expect(PasswordRules.isValid(r'Coc@2026x'), isTrue);
    });
  });
}
