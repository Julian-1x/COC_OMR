import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';

void main() {
  setUp(() {
    globalStudentDatabase = <Student>[];
    rebuildStudentIndex();
    resetOmrCounter();
  });

  Student student({
    required String schoolId,
    required String omrId,
    String section = 'BSIT-1A',
  }) {
    return Student(
      schoolId: schoolId,
      name: 'Student $omrId',
      section: section,
      omrId: omrId,
    );
  }

  group('OMR ID assignment', () {
    test('empty roster first import starts at 0001 even if counter is stale', () {
      restoreCounters(omrCounter: 99, subjectCounter: 1, sheetCounter: 1);

      final first = buildStudentOmrId('S1', reservedOmrIds: {});
      final second = buildStudentOmrId(
        'S2',
        reservedOmrIds: {first},
      );

      expect(first, '0001');
      expect(second, '0002');
      expect(nextOmrIdValue, 3);
    });

    test('continues after highest existing ID for later imports', () {
      globalStudentDatabase = [
        for (var i = 1; i <= 48; i++)
          student(
            schoolId: 'SCH-$i',
            omrId: i.toString().padLeft(4, '0'),
          ),
      ];
      rebuildStudentIndex();
      syncOmrCounterToRoster();

      final next = buildStudentOmrId('SCH-NEW', reservedOmrIds: {});
      expect(next, '0049');
    });

    test('empty roster after students cleared restarts at 0001', () {
      globalStudentDatabase = [
        student(schoolId: 'A', omrId: '0001'),
        student(schoolId: 'B', omrId: '0048'),
      ];
      syncOmrCounterToRoster();
      expect(nextOmrIdValue, 49);

      globalStudentDatabase = <Student>[];
      rebuildStudentIndex();
      syncOmrCounterToRoster();

      expect(nextOmrIdValue, 1);
      expect(buildStudentOmrId('C', reservedOmrIds: {}), '0001');
    });

    test('skips reserved IDs in the same import batch', () {
      final reserved = <String>{'0001', '0002'};
      final next = buildStudentOmrId('S3', reservedOmrIds: reserved);
      expect(next, '0003');
    });

    test('same school ID keeps existing OMR when student already on roster', () {
      final existing = student(
        schoolId: '2025-001',
        omrId: '0007',
        section: 'BSIT-1A',
      );
      globalStudentDatabase = [existing];
      rebuildStudentIndex();

      // Import path matches by school ID and reuses omrId via copyWith —
      // assert the identity contract here.
      final match = globalStudentDatabase.firstWhere(
        (s) => s.schoolId == '2025-001',
      );
      final moved = match.copyWith(section: 'BSIT-1B');

      expect(moved.omrId, '0007');
      expect(moved.section, 'BSIT-1B');
      expect(
        buildStudentOmrId('someone-else', reservedOmrIds: {moved.omrId}),
        '0008',
      );
    });
  });
}
