import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/item_analysis_service.dart';

void main() {
  final subject = Subject(
    id: 'SUB-0001',
    name: 'Math',
    answerKey: {
      1: ['A'],
      2: ['B'],
      3: ['A', 'B'],
    },
    totalQuestions: 3,
    passingScore: 2,
    sectionNames: ['BSIT-1A'],
    usePartialCredit: true,
  );

  ScanResult scan({
    required String omrId,
    required Map<int, String> answers,
    required double confidence,
    bool needsReview = false,
    DateTime? scanTime,
  }) {
    return ScanResult(
      studentOmrId: omrId,
      subjectId: subject.id,
      subjectName: subject.name,
      detectedAnswers: answers,
      correctnessMap: const {},
      score: 0,
      totalQuestions: 3,
      confidence: confidence,
      scanTime: scanTime ?? DateTime(2026, 4, 8),
      needsReview: needsReview,
    );
  }

  test('excludes scans that still need review', () {
    final report = ItemAnalysisService.buildFromData(
      subject: subject,
      results: [
        scan(
          omrId: '0001',
          answers: {1: 'A', 2: 'B', 3: 'A+B'},
          confidence: 0.4,
          needsReview: true,
        ),
      ],
    );

    expect(report, isNull);
  });

  test('uses latest approved scan per student', () {
    final report = ItemAnalysisService.buildFromData(
      subject: subject,
      results: [
        scan(
          omrId: '0001',
          answers: {1: 'B', 2: 'B', 3: 'A'},
          confidence: 0.9,
          scanTime: DateTime(2026, 4, 8, 9),
        ),
        scan(
          omrId: '0001',
          answers: {1: 'A', 2: 'B', 3: 'A+B'},
          confidence: 0.95,
          scanTime: DateTime(2026, 4, 8, 10),
        ),
      ],
    );

    expect(report, isNotNull);
    expect(report!.gradedStudentCount, 1);
    expect(report.supersededScanCount, 1);
    expect(report.questions[0].correctCount, 1);
    expect(report.questions[2].correctCount, 1);
  });

  test('counts blanks as attempts but not correct', () {
    final report = ItemAnalysisService.buildFromData(
      subject: subject,
      results: [
        scan(
          omrId: '0001',
          answers: {1: 'A', 2: '', 3: 'A+B'},
          confidence: 0.9,
        ),
        scan(
          omrId: '0002',
          answers: {1: 'B', 2: 'B', 3: 'A'},
          confidence: 0.9,
        ),
      ],
    );

    expect(report, isNotNull);
    final q2 = report!.questions[1];
    expect(q2.totalAttempts, 2);
    expect(q2.correctCount, 1);
    expect(q2.answerDistribution['—'], 1);
    expect(q2.answerDistribution['B'], 1);
  });

  test('scores multi-answer items with calculateQuestionScore', () {
    final report = ItemAnalysisService.buildFromData(
      subject: subject,
      results: [
        scan(
          omrId: '0001',
          answers: {1: 'A', 2: 'B', 3: 'A+B'},
          confidence: 0.95,
        ),
        scan(
          omrId: '0002',
          answers: {1: 'A', 2: 'B', 3: 'A'},
          confidence: 0.9,
        ),
      ],
    );

    expect(report, isNotNull);
    final q3 = report!.questions[2];
    expect(q3.correctAnswer, 'A+B');
    expect(q3.correctCount, 1);
    expect(q3.partialCount, 1);
  });

  test('isDistributionChoiceCorrect matches scoring', () {
    expect(
      ItemAnalysisService.isDistributionChoiceCorrect(subject, 3, 'A+B'),
      isTrue,
    );
    expect(
      ItemAnalysisService.isDistributionChoiceCorrect(subject, 3, 'A'),
      isFalse,
    );
    expect(
      ItemAnalysisService.isDistributionChoiceCorrect(
        subject,
        2,
        ItemAnalysisService.blankDistributionLabel,
      ),
      isFalse,
    );
  });
}
