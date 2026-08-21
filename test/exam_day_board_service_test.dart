import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/exam_day_board_service.dart';

Subject _subject() {
  return Subject(
    id: 'SUB-QUIZ-1',
    name: 'Midterm Quiz 1',
    answerKey: {
      1: ['A'],
    },
    totalQuestions: 1,
    passingScore: 1,
    sectionNames: ['BSIT-1A'],
  );
}

Student _student(String omrId, String name) {
  return Student(
    schoolId: 'SID-$omrId',
    omrId: omrId,
    name: name,
    section: 'BSIT-1A',
  );
}

ScanResult _scan({
  required String omrId,
  bool needsReview = false,
  List<String>? reviewReasons,
  DateTime? scanTime,
  String? subjectId,
}) {
  return ScanResult(
    studentOmrId: omrId,
    subjectId: subjectId ?? 'SUB-QUIZ-1',
    subjectName: 'Midterm Quiz 1',
    detectedAnswers: {1: 'A'},
    correctnessMap: {1: 1.0},
    score: 1,
    totalQuestions: 1,
    confidence: needsReview ? 0.4 : 0.95,
    scanTime: scanTime ?? DateTime(2026, 8, 18, 9),
    needsReview: needsReview,
    reviewReasons: reviewReasons,
  );
}

void main() {
  test('classifies done, missing, review, duplicate, absent, and unmatched', () {
    final subject = _subject();
    final report = ExamDayBoardService.build(
      subject: subject,
      sectionName: 'bsit-1a',
      students: [
        _student('0001', 'Ana Santos'),
        _student('0002', 'Ben Cruz'),
        _student('0003', 'Cara Lim'),
        _student('0004', 'Dan Reyes'),
        _student('0005', 'Eva Go'),
      ],
      scans: [
        _scan(omrId: '0001'),
        _scan(omrId: '0003', needsReview: true),
        _scan(
          omrId: '0004',
          needsReview: true,
          reviewReasons: [
            'Rescan detected for an already-scanned student and subject.',
          ],
        ),
        _scan(omrId: '0005', scanTime: DateTime(2026, 8, 18, 8)),
        _scan(omrId: '0005', scanTime: DateTime(2026, 8, 18, 10)),
        _scan(omrId: '0999'),
      ],
      absentOmrIds: {'0002'},
    );

    ExamDayStatus statusOf(String omrId) =>
        report.rows.firstWhere((row) => row.omrId == omrId).status;

    expect(statusOf('0001'), ExamDayStatus.done);
    expect(statusOf('0002'), ExamDayStatus.absent);
    expect(statusOf('0003'), ExamDayStatus.needsReview);
    expect(statusOf('0004'), ExamDayStatus.duplicate);
    expect(statusOf('0005'), ExamDayStatus.duplicate);
    expect(report.unmatchedScans.single.studentOmrId, '0999');
    expect(report.doneCount, 1);
    expect(report.missingCount, 0);
    expect(report.absentCount, 1);
    expect(report.reviewCount, 1);
    expect(report.duplicateCount, 2);
    expect(report.isReadyToClose, isFalse);
  });

  test('missing students keep the exam open', () {
    final report = ExamDayBoardService.build(
      subject: _subject(),
      sectionName: 'BSIT-1A',
      students: [_student('0001', 'Ana Santos')],
      scans: const [],
    );

    expect(report.rows.single.status, ExamDayStatus.missing);
    expect(report.isReadyToClose, isFalse);
  });

  test('all confirmed scans means the class can close', () {
    final report = ExamDayBoardService.build(
      subject: _subject(),
      sectionName: 'BSIT-1A',
      students: [_student('0001', 'Ana Santos')],
      scans: [_scan(omrId: '0001')],
    );

    expect(report.rows.single.status, ExamDayStatus.done);
    expect(report.isReadyToClose, isTrue);
  });

  test('ignores scans from a different exam', () {
    final report = ExamDayBoardService.build(
      subject: _subject(),
      sectionName: 'BSIT-1A',
      students: [_student('0001', 'Ana Santos')],
      scans: [_scan(omrId: '0001', subjectId: 'OTHER')],
    );

    expect(report.rows.single.status, ExamDayStatus.missing);
  });
}
