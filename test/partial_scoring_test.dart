import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';

void main() {
  test('partial credit scoring parses multi-answer responses', () {
    final subject = Subject(
      name: 'Science',
      answerKey: {
        1: ['A', 'C'],
        2: ['B'],
      },
      totalQuestions: 2,
      usePartialCredit: true,
    );

    expect(subject.calculateQuestionScore(1, 'A,C'), 1.0);
    expect(subject.calculateQuestionScore(1, 'A'), 0.5);
    expect(subject.calculateQuestionScore(1, 'A,D'), 0.0);
    expect(subject.calculateSmartScore({1: 'A', 2: 'B'}), 1.5);
  });

  test('scan results load legacy bool correctness maps', () {
    final result = ScanResult.fromJson({
      'studentOmrId': '0001',
      'subjectId': 'SUB-0001',
      'subjectName': 'Math',
      'detectedAnswers': {'1': 'A'},
      'correctnessMap': {'1': true, '2': false},
      'score': 1,
      'totalQuestions': 2,
      'confidence': 0.9,
      'scanTime': DateTime(2026, 4, 8).toIso8601String(),
    });

    expect(result.correctnessMap[1], 1.0);
    expect(result.correctnessMap[2], 0.0);
  });
}
