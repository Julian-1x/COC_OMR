import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/utils/student_identity.dart';

void main() {
  test('dedupe keeps lower omr id for same school id', () {
    final students = [
      Student(
        schoolId: '02-2223-44444',
        omrId: '0007',
        name: 'Marjorie Agcopra',
        section: 'BSIT-01',
      ),
      Student(
        schoolId: '02-2223-44444',
        omrId: '0025',
        name: 'Marjorie Agcopra',
        section: 'BSIT-01',
      ),
    ];

    final result = dedupeStudentRoster(
      students: students,
      scanResults: const <ScanResult>[],
    );

    expect(result.mergedCount, 1);
    expect(result.students.length, 1);
    expect(result.students.single.omrId, '0007');
    expect(result.removedOmrIds, ['0025']);
  });

  test('dedupe keeps omr id with scans when school id matches', () {
    final students = [
      Student(
        schoolId: '02-2223-10456',
        omrId: '0001',
        name: 'Alexander Julian',
        section: 'BSIT-02',
      ),
      Student(
        schoolId: '02-2223-10456',
        omrId: '0019',
        name: 'Alexander Julian',
        section: 'BSIT-02',
      ),
    ];
    final scans = [
      ScanResult(
        studentOmrId: '0019',
        subjectName: 'Math',
        detectedAnswers: const {1: 'A'},
        correctnessMap: const {1: 1.0},
        score: 1,
        totalQuestions: 1,
        confidence: 0.95,
        scanTime: DateTime(2026, 4, 1),
      ),
    ];

    final result = dedupeStudentRoster(
      students: students,
      scanResults: scans,
    );

    expect(result.students.single.omrId, '0019');
    expect(result.scanResults.single.studentOmrId, '0019');
    expect(result.removedOmrIds, ['0001']);
  });

  test('dedupe repoints scans from removed omr id to canonical omr id', () {
    final students = [
      Student(
        schoolId: '02-2024-11111',
        omrId: '0002',
        name: 'Jyll',
        section: 'BSIT-02',
      ),
      Student(
        schoolId: '02-2024-11111',
        omrId: '0020',
        name: 'Jyll',
        section: 'BSIT-02',
      ),
    ];
    final scans = [
      ScanResult(
        studentOmrId: '0020',
        subjectName: 'English',
        detectedAnswers: const {1: 'B'},
        correctnessMap: const {1: 1.0},
        score: 1,
        totalQuestions: 1,
        confidence: 0.9,
        scanTime: DateTime(2026, 4, 2),
      ),
    ];

    final result = dedupeStudentRoster(
      students: students,
      scanResults: scans,
    );

    expect(result.students.single.omrId, '0020');
    expect(result.scanResults.single.studentOmrId, '0020');
  });

  test('normalizeSchoolId trims and uppercases', () {
    expect(normalizeSchoolId(' 02-2223-44444 '), '02-2223-44444');
  });
}
