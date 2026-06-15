import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';
import 'package:omr_app/services/import_service.dart';

void main() {
  setUp(() {
    globalStudentDatabase = [];
    globalSections = [];
    globalSubjects = [];
    globalScanResults = [];
    resetOmrCounter();
    resetSubjectCounter();
    resetSheetCounter();
  });

  test('importRows reports imported skipped and duplicate counts', () {
    globalStudentDatabase.add(
      Student(
        schoolId: '2024001',
        omrId: '0001',
        name: 'Existing Student',
        section: 'BSIT-01',
      ),
    );

    final summary = ImportService.importRows(
      [
        ['School ID', 'Name', 'Section'],
        ['2024001', 'Existing Student', 'BSIT-01'],
        ['2024002', 'Ava Cruz', 'BSIT-01'],
        ['', 'Missing Id', 'BSIT-01'],
        ['2024002', 'Ava Cruz', 'BSIT-01'],
        ['2024003', 'Liam Santos', 'BSIT-02'],
      ],
      fileName: 'StudentRoster.xlsx',
    );

    expect(summary.imported, 2);
    expect(summary.unchanged, 1);
    expect(summary.skipped, 1);
    expect(summary.duplicates, 1);
    expect(
      summary.feedbackMessage,
      'added 2, unchanged 1, skipped 1, duplicate rows 1',
    );
    expect(globalStudentDatabase.length, 3);
    expect(globalStudentDatabase[0].omrId, '0001');
    expect(globalStudentDatabase[1].omrId, '0002');
    expect(globalStudentDatabase[2].omrId, '0003');
    expect(globalSections.map((section) => section.name), contains('BSIT-01'));
    expect(globalSections.map((section) => section.name), contains('BSIT-02'));
  });

  test('re-importing the same roster does not duplicate students', () {
    ImportService.importRows(
      [
        ['School ID', 'Name', 'Section'],
        ['2024001', 'Ava Cruz', 'BSIT-1A'],
        ['2024002', 'Liam Santos', 'BSIT-1A'],
      ],
      fileName: 'first.xlsx',
    );

    final summary = ImportService.importRows(
      [
        ['School ID', 'Name', 'Section'],
        ['2024001', 'Ava Cruz', 'BSIT-1A'],
        ['2024002', 'Liam Santos', 'BSIT-1A'],
      ],
      fileName: 'same-again.xlsx',
    );

    expect(summary.imported, 0);
    expect(summary.unchanged, 2);
    expect(summary.duplicates, 0);
    expect(globalStudentDatabase.length, 2);
    expect(globalStudentDatabase.every((s) => s.section == 'BSIT-1A'), isTrue);
    expect(globalStudentDatabase[0].omrId, '0001');
    expect(globalStudentDatabase[1].omrId, '0002');
  });

  test('re-import adds only new students and keeps existing in place', () {
    ImportService.importRows(
      [
        ['School ID', 'Name', 'Section'],
        ['2024001', 'Ava Cruz', 'BSIT-1A'],
      ],
      fileName: 'first.xlsx',
    );

    final summary = ImportService.importRows(
      [
        ['School ID', 'Name', 'Section'],
        ['2024001', 'Ava Cruz', 'BSIT-1A'],
        ['2024002', 'New Student', 'BSIT-1A'],
      ],
      fileName: 'with-new.xlsx',
    );

    expect(summary.imported, 1);
    expect(summary.unchanged, 1);
    expect(globalStudentDatabase.length, 2);
    expect(globalStudentDatabase[0].section, 'BSIT-1A');
    expect(globalStudentDatabase[1].section, 'BSIT-1A');
    expect(globalStudentDatabase[0].omrId, '0001');
    expect(globalStudentDatabase[1].omrId, '0002');
  });

  test('re-import keeps the same OMR ID for the same student ID', () {
    ImportService.importRows(
      [
        ['Student ID', 'Name', 'Section'],
        ['2024001', 'Ava Cruz', 'BSIT-1A'],
      ],
      fileName: 'first.xlsx',
    );

    expect(globalStudentDatabase.single.omrId, '0001');

    ImportService.importRows(
      [
        ['Student ID', 'Name', 'Section'],
        ['2024001', 'Ava Cruz', 'BSIT-1A'],
      ],
      fileName: 'same-again.xlsx',
    );

    expect(globalStudentDatabase.length, 1);
    expect(globalStudentDatabase.single.schoolId, '2024001');
    expect(globalStudentDatabase.single.omrId, '0001');
    expect(globalStudentDatabase.single.section, 'BSIT-1A');
  });

  test('importRows allows same names when school IDs are different', () {
    final summary = ImportService.importRows(
      [
        ['School ID', 'Name', 'Section'],
        ['2024101', 'Alex Reyes', 'BSIT-01'],
        ['2024102', 'Alex Reyes', 'BSIT-02'],
      ],
      fileName: 'StudentRoster.xlsx',
    );

    expect(summary.imported, 2);
    expect(summary.skipped, 0);
    expect(summary.duplicates, 0);
    expect(
      globalStudentDatabase.every(
        (student) => RegExp(r'^\d{4}$').hasMatch(student.omrId),
      ),
      isTrue,
    );
    expect(globalStudentDatabase[0].omrId, isNot(globalStudentDatabase[1].omrId));
  });

  test('buildStudentOmrId is sequential and skips reserved slots', () {
    resetOmrCounter();
    final first = buildStudentOmrId('2024101');
    final second = buildStudentOmrId('2024102', reservedOmrIds: {first});
    expect(first, matches(RegExp(r'^\d{4}$')));
    expect(second, matches(RegExp(r'^\d{4}$')));
    expect(second, isNot(first));
  });

  test('sheet QR payload resolves a subject by unique subject ID', () {
    final mathA = Subject(
      name: 'Math',
      answerKey: const {1: 'A'},
      sectionNames: ['BSIT-01'],
    );
    final mathB = Subject(
      name: 'Math',
      answerKey: const {1: 'B'},
      sectionNames: ['BSIT-02'],
    );
    globalSubjects = [mathA, mathB];

    final qrData = AnswerSheetGenerator.buildSheetQrCodeData(
      mathB,
      sheetId: 'SHEET-000123',
    );
    final payload = SubjectSheetQrPayload.fromJson(
      Map<String, dynamic>.from(
        (const JsonDecoder().convert(qrData) as Map<String, dynamic>),
      ),
    );

    expect(payload.subjectId, mathB.id);
    expect(payload.sheetId, 'SHEET-000123');
    expect(payload.resolveSubject()?.id, mathB.id);
  });
}
