import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';

void main() {
  setUp(() {
    globalStudentDatabase = [];
    globalSections = [];
    globalSubjects = [];
    globalScanResults = [];
    globalDeadlines = [];
    globalExportRecords = [];
    rebuildStudentIndex();
    resetOmrCounter();
    resetSubjectCounter();
    resetSheetCounter();
  });

  test('deleting an answer key removes linked data and refreshes students', () {
    final subjectMath = Subject(
      id: 'SUB-0001',
      name: 'Math',
      answerKey: {
        1: ['A'],
      },
      totalQuestions: 30,
      sectionNames: ['BSIT-1A'],
      examDate: DateTime(2026, 4, 8),
    );
    final subjectScience = Subject(
      id: 'SUB-0002',
      name: 'Science',
      answerKey: {
        1: ['B'],
      },
      totalQuestions: 30,
      sectionNames: ['BSIT-1A'],
      examDate: DateTime(2026, 4, 8),
    );

    globalSubjects = [subjectMath, subjectScience];
    globalStudentDatabase = [
      Student(
        schoolId: '2024-001',
        omrId: '0001',
        name: 'Ana',
        section: 'BSIT-1A',
        score: 18,
        answers: {1: 'B'},
        scanDate: DateTime(2026, 4, 3),
        confidence: 0.95,
      ),
      Student(
        schoolId: '2024-002',
        omrId: '0002',
        name: 'Ben',
        section: 'BSIT-1A',
        score: 20,
        answers: {1: 'B'},
        scanDate: DateTime(2026, 4, 4),
        confidence: 0.91,
      ),
    ];

    globalScanResults = [
      ScanResult(
        studentOmrId: '0001',
        subjectId: subjectMath.id,
        subjectName: subjectMath.name,
        detectedAnswers: {1: 'A'},
        correctnessMap: {1: 1.0},
        score: 12,
        totalQuestions: 30,
        confidence: 0.88,
        scanTime: DateTime(2026, 4, 2),
      ),
      ScanResult(
        studentOmrId: '0001',
        subjectId: subjectScience.id,
        subjectName: subjectScience.name,
        detectedAnswers: {1: 'B'},
        correctnessMap: {1: 1.0},
        score: 18,
        totalQuestions: 30,
        confidence: 0.95,
        scanTime: DateTime(2026, 4, 3),
      ),
      ScanResult(
        studentOmrId: '0002',
        subjectId: subjectScience.id,
        subjectName: subjectScience.name,
        detectedAnswers: {1: 'B'},
        correctnessMap: {1: 1.0},
        score: 20,
        totalQuestions: 30,
        confidence: 0.91,
        scanTime: DateTime(2026, 4, 4),
      ),
    ];

    globalDeadlines = [
      Deadline(
        id: 'DL-1',
        title: 'Science checking',
        subjectId: subjectScience.id,
        dueDate: DateTime(2026, 4, 10),
      ),
      Deadline(
        id: 'DL-2',
        title: 'Math checking',
        subjectId: subjectMath.id,
        dueDate: DateTime(2026, 4, 11),
      ),
    ];

    rebuildStudentIndex();

    final summary = deleteSubjectAndRelatedData(subjectScience);

    expect(summary.removedSubjects, 1);
    expect(summary.removedScans, 2);
    expect(summary.removedDeadlines, 1);
    expect(summary.affectedStudents, 2);

    expect(globalSubjects.map((subject) => subject.id), [subjectMath.id]);
    expect(globalDeadlines.map((deadline) => deadline.id), ['DL-2']);
    expect(findScansBySubject(subjectScience.id), isEmpty);
    expect(findScansBySubject(subjectMath.id), hasLength(1));

    final updatedAna = findStudentByOmrId('0001');
    expect(updatedAna, isNotNull);
    expect(updatedAna!.score, 12);
    expect(updatedAna.answers, {1: 'A'});
    expect(updatedAna.scanDate, DateTime(2026, 4, 2));
    expect(updatedAna.confidence, 0.88);

    final updatedBen = findStudentByOmrId('0002');
    expect(updatedBen, isNotNull);
    expect(updatedBen!.score, isNull);
    expect(updatedBen.answers, isNull);
    expect(updatedBen.scanDate, isNull);
    expect(updatedBen.confidence, isNull);
  });
}
