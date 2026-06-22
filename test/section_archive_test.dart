import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/utils/academic_term.dart';

void main() {
  test('schoolYearForDate uses June boundary', () {
    expect(
      AcademicTerm.schoolYearForDate(DateTime(2025, 5, 15)),
      '2024-2025',
    );
    expect(
      AcademicTerm.schoolYearForDate(DateTime(2025, 6, 1)),
      '2025-2026',
    );
  });

  test('Section serializes archive and term fields', () {
    final archivedAt = DateTime.utc(2025, 12, 1);
    final section = Section(
      name: 'BSIT-01',
      schoolYear: '2025-2026',
      termLabel: '1st Sem',
      archivedAt: archivedAt,
    );

    final restored = Section.fromJson(section.toJson());
    expect(restored.schoolYear, '2025-2026');
    expect(restored.termLabel, '1st Sem');
    expect(restored.isArchived, isTrue);
    expect(restored.archivedAt, archivedAt);
  });

  test('Section copyWith can clear archivedAt for reactivation', () {
    final section = Section(
      name: 'BSIT-01',
      archivedAt: DateTime.utc(2024, 6, 1),
    );
    final active = section.copyWith(clearArchivedAt: true);
    expect(active.isArchived, isFalse);
  });
}
