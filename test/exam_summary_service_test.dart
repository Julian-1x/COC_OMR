import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/exam_summary_service.dart';

void main() {
  test('buildFromData computes averages and hardest questions', () {
    final subject = Subject(
      id: 'SUB-0001',
      name: 'Math',
      answerKey: {
        1: ['A'],
        2: ['B'],
        3: ['C'],
      },
      totalQuestions: 3,
      passingScore: 2,
      sectionNames: ['BSIT-1A'],
      examDate: DateTime(2026, 4, 8),
    );

    final students = [
      Student(
        schoolId: '2024-001',
        omrId: '0001',
        name: 'Ana',
        section: 'BSIT-1A',
      ),
      Student(
        schoolId: '2024-002',
        omrId: '0002',
        name: 'Ben',
        section: 'BSIT-1A',
      ),
    ];

    final results = [
      ScanResult(
        studentOmrId: '0001',
        subjectId: subject.id,
        subjectName: subject.name,
        detectedAnswers: {1: 'A', 2: 'B', 3: 'D'},
        correctnessMap: {1: 1.0, 2: 1.0, 3: 0.0},
        score: 2,
        totalQuestions: 3,
        confidence: 0.95,
        scanTime: DateTime(2026, 4, 8, 9),
      ),
      ScanResult(
        studentOmrId: '0002',
        subjectId: subject.id,
        subjectName: subject.name,
        detectedAnswers: {1: 'B', 2: 'B', 3: 'C'},
        correctnessMap: {1: 0.0, 2: 1.0, 3: 1.0},
        score: 2,
        totalQuestions: 3,
        confidence: 0.91,
        scanTime: DateTime(2026, 4, 8, 10),
      ),
    ];

    final report = ExamSummaryService.buildFromData(
      subject: subject,
      sectionName: 'BSIT-1A',
      students: students,
      results: results,
      generatedAt: DateTime(2026, 4, 9),
    );

    expect(report, isNotNull);
    expect(report!.rosterCount, 2);
    expect(report.scannedCount, 2);
    expect(report.averagePercentage, closeTo(66.7, 0.1));
    expect(report.passedCount, 2);
    expect(report.passRate, 100);
    expect(report.topMissedQuestions.first.questionNumber, 1);
    expect(report.topMissedQuestions.last.questionNumber, 3);
    expect(report.examDate, DateTime(2026, 4, 8));
  });

  test('buildFromData excludes scans that still need review', () {
    final subject = Subject(
      id: 'SUB-0002',
      name: 'Science',
      answerKey: {1: ['A']},
      totalQuestions: 1,
      passingScore: 1,
      sectionNames: ['BSIT-1A'],
    );

    final report = ExamSummaryService.buildFromData(
      subject: subject,
      sectionName: 'BSIT-1A',
      students: [
        Student(
          schoolId: '2024-001',
          omrId: '0001',
          name: 'Ana',
          section: 'BSIT-1A',
        ),
      ],
      results: [
        ScanResult(
          studentOmrId: '0001',
          subjectId: subject.id,
          subjectName: subject.name,
          detectedAnswers: {1: 'A'},
          correctnessMap: {1: 1.0},
          score: 1,
          totalQuestions: 1,
          confidence: 0.4,
          scanTime: DateTime(2026, 4, 8),
          needsReview: true,
        ),
      ],
    );

    expect(report, isNull);
  });
}
