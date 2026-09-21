import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/scan_confidence_service.dart';

void main() {
  group('ScanConfidenceService.assess', () {
    test('clean scan is Safe to keep', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[],
        flaggedQuestions: const <int>[],
        confidence: 0.95,
      );
      expect(report.level, ScanConfidenceLevel.safe);
      expect(report.title, 'Safe to keep');
      expect(report.requiresReview, isFalse);
    });

    test('light marks are Check before counting', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[
          'Q3 looks lightly marked — confirm it is intentional.',
        ],
        flaggedQuestions: const <int>[3],
        confidence: 0.88,
      );
      expect(report.level, ScanConfidenceLevel.check);
      expect(report.title, 'Check before counting');
      expect(report.requiresReview, isTrue);
    });

    test('simple blanks are Check, not Must', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>['4 questions left blank.'],
        confidence: 0.9,
      );
      expect(report.level, ScanConfidenceLevel.check);
    });

    test('double marks are Must review', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[
          '2 questions have more than one mark — left blank; tap flagged cells to choose.',
        ],
        flaggedQuestions: const <int>[5, 6],
        confidence: 0.85,
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
      expect(report.title, 'Must review');
    });

    test('low confidence is Must review', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[
          'Low scan confidence (62%).',
        ],
        confidence: 0.62,
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
    });

    test('low confidence alone with no reasons is Must review', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[],
        confidence: 0.55,
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
      expect(report.reasons, isNotEmpty);
    });

    test('OMR ID ambiguity is Must review', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[
          'OMR ID digit 2 was unclear — verify the 4-digit ID.',
        ],
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
    });

    test('crumple blanks escalate to Must review', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[
          '12 blanks with weak sheet alignment — page may be crumpled. '
              'Flatten under a book and rescan, or fill blanks in review.',
        ],
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
    });

    test('mixed reasons take the highest severity', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>[
          '1 question left blank.',
          'OMR ID digit 1 was unclear — verify the 4-digit ID.',
        ],
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
      expect(report.topReasons.length, 2);
    });

    test('unknown reason fails safe to Must review', () {
      final report = ScanConfidenceService.assess(
        reviewReasons: const <String>['Unexpected scanner anomaly XYZ.'],
      );
      expect(report.level, ScanConfidenceLevel.mustReview);
    });
  });

  group('ScanConfidenceService.summarizeBatch', () {
    test('counts safe / check / must', () {
      final summary = ScanConfidenceService.summarizeBatch([
        _scan(reasons: const <String>[]),
        _scan(reasons: const <String>['2 questions left blank.']),
        _scan(
          reasons: const <String>[
            '1 question has more than one mark — left blank; tap to choose the answer.',
          ],
        ),
      ]);
      expect(summary.safe, 1);
      expect(summary.check, 1);
      expect(summary.mustReview, 1);
      expect(summary.needsAttention, 2);
      expect(summary.riskyScans, hasLength(2));
    });
  });
}

ScanResult _scan({required List<String> reasons}) {
  return ScanResult(
    studentOmrId: '0001',
    subjectId: 'math',
    subjectName: 'Math',
    detectedAnswers: const {1: 'A'},
    correctnessMap: const {1: 1.0},
    score: 1,
    totalQuestions: 50,
    confidence: 0.9,
    scanTime: DateTime.parse('2026-01-01T00:00:00Z'),
    reviewReasons: reasons,
    needsReview: reasons.isNotEmpty,
  );
}
