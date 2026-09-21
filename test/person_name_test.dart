import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/utils/person_name.dart';

void main() {
  group('PersonName', () {
    test('title-cases plain names', () {
      expect(PersonName.normalize('maria santos'), 'Maria Santos');
      expect(PersonName.normalize('  ALEXANDER   JULIAN   BALABA  '), 'Alexander Julian Balaba');
    });

    test('reorders Last, First to First Last', () {
      expect(PersonName.normalize('Santos, Maria'), 'Maria Santos');
      expect(PersonName.normalize('Balaba, Alexander Julian'), 'Alexander Julian Balaba');
    });

    test('lowercases name particles', () {
      expect(PersonName.normalize('MARIA DE LA CRUZ'), 'Maria de la Cruz');
      expect(PersonName.normalize('Ana Del Rosario'), 'Ana del Rosario');
    });

    test('combines first and last into normalized full name', () {
      expect(PersonName.normalizeFromParts(lastName: 'santos', firstName: 'maria'),
          'Maria Santos');
      expect(PersonName.normalizeFromParts(lastName: 'BALABA', firstName: 'ALEXANDER'),
          'Alexander Balaba');
    });

    test('appends optional suffix', () {
      expect(
        PersonName.normalizeFromParts(
          lastName: 'Santos',
          firstName: 'Maria',
          suffix: 'jr',
        ),
        'Maria Santos JR',
      );
    });

    test('returns empty when either part is missing', () {
      expect(PersonName.normalizeFromParts(lastName: '', firstName: 'Maria'), '');
      expect(PersonName.normalizeFromParts(lastName: 'Santos', firstName: '  '), '');
    });

    test('handles hyphenated and Mc names', () {
      expect(PersonName.normalize('mary-jane watson'), 'Mary-Jane Watson');
      expect(PersonName.normalize('RONALD MCDONALD'), 'Ronald McDonald');
    });
  });
}
