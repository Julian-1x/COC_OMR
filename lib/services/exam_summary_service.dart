import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/local_data_store.dart';

class MissedQuestionSummary {
  const MissedQuestionSummary({
    required this.questionNumber,
    required this.correctAnswer,
    required this.attempts,
    required this.correctCount,
  });

  final int questionNumber;
  final String correctAnswer;
  final int attempts;
  final int correctCount;

  double get percentCorrect =>
      attempts > 0 ? (correctCount / attempts) * 100 : 0;

  int get missedCount => attempts - correctCount;
}

class ExamSummaryReport {
  const ExamSummaryReport({
    required this.sectionName,
    required this.subject,
    required this.examDate,
    required this.generatedAt,
    required this.rosterCount,
    required this.scannedCount,
    required this.pendingReviewCount,
    required this.averagePercentage,
    required this.passRate,
    required this.passedCount,
    required this.failedCount,
    required this.topMissedQuestions,
  });

  final String sectionName;
  final Subject subject;
  final DateTime? examDate;
  final DateTime generatedAt;
  final int rosterCount;
  final int scannedCount;
  final int pendingReviewCount;
  final double averagePercentage;
  final double passRate;
  final int passedCount;
  final int failedCount;
  final List<MissedQuestionSummary> topMissedQuestions;

  String get subjectName => subject.displayName;
  int get totalQuestions => subject.totalQuestions;
  int get passingScorePoints => subject.passingScore;

  double get passThresholdPercent => totalQuestions > 0
      ? (passingScorePoints / totalQuestions) * 100
      : 60;
}

abstract final class ExamSummaryService {
  static Future<ExamSummaryReport?> build({
    required Subject subject,
    required String sectionName,
    int topMissedCount = 5,
  }) async {
    final students = await LocalDataStore.instance.fetchStudents(
      sectionName: sectionName,
    );
    final results = await LocalDataStore.instance.fetchScanResults(
      subjectId: subject.id,
      sectionName: sectionName,
    );

    return buildFromData(
      subject: subject,
      sectionName: sectionName,
      students: students,
      results: results,
      topMissedCount: topMissedCount,
    );
  }

  static ExamSummaryReport? buildFromData({
    required Subject subject,
    required String sectionName,
    required List<Student> students,
    required List<ScanResult> results,
    int topMissedCount = 5,
    DateTime? generatedAt,
  }) {
    if (results.isEmpty) {
      return null;
    }

    final normalizedSection = sectionName.trim().toUpperCase();
    final rosterCount = students.length;
    final gradedResults =
        results.where((result) => !result.requiresReview).toList();
    final pendingReviewCount = results.length - gradedResults.length;

    if (gradedResults.isEmpty) {
      return null;
    }

    final scannedStudentIds =
        gradedResults.map((result) => result.studentOmrId).toSet();

    final averagePercentage = gradedResults
            .map((result) => result.percentage)
            .reduce((a, b) => a + b) /
        gradedResults.length;

    final passedCount = gradedResults
        .where((result) => _passed(result, subject))
        .length;
    final failedCount = gradedResults.length - passedCount;
    final passRate =
        (passedCount / gradedResults.length) * 100;

    final examDate = _resolveExamDate(subject, results);
    final topMissed = _computeTopMissed(
      subject: subject,
      results: gradedResults,
      limit: topMissedCount,
    );

    return ExamSummaryReport(
      sectionName: normalizedSection,
      subject: subject,
      examDate: examDate,
      generatedAt: generatedAt ?? DateTime.now(),
      rosterCount: rosterCount,
      scannedCount: scannedStudentIds.length,
      pendingReviewCount: pendingReviewCount,
      averagePercentage: averagePercentage,
      passRate: passRate,
      passedCount: passedCount,
      failedCount: failedCount,
      topMissedQuestions: topMissed,
    );
  }

  static bool _passed(ScanResult result, Subject subject) {
    final threshold = subject.totalQuestions > 0
        ? (subject.passingScore / subject.totalQuestions) * 100
        : 60.0;
    return result.percentage >= threshold;
  }

  static DateTime? _resolveExamDate(
    Subject subject,
    List<ScanResult> results,
  ) {
    if (subject.examDate != null) {
      return subject.examDate;
    }

    DateTime? latest;
    for (final result in results) {
      if (latest == null || result.scanTime.isAfter(latest)) {
        latest = result.scanTime;
      }
    }
    return latest;
  }

  static List<MissedQuestionSummary> _computeTopMissed({
    required Subject subject,
    required List<ScanResult> results,
    required int limit,
  }) {
    final answerKey = subject.answerKey;
    final totalQuestions = subject.totalQuestions;
    final summaries = <MissedQuestionSummary>[];

    for (var qNum = 1; qNum <= totalQuestions; qNum++) {
      final correctAns = answerKey[qNum]?.isNotEmpty == true
          ? answerKey[qNum]!.first
          : '?';
      var attempts = 0;
      var correctCount = 0;

      for (final result in results) {
        final studentAnswer = result.detectedAnswers[qNum] ?? '';
        if (studentAnswer.isEmpty) {
          continue;
        }

        attempts++;
        if (answerKey[qNum]?.contains(studentAnswer) == true) {
          correctCount++;
        }
      }

      if (attempts == 0 || correctCount == attempts) {
        continue;
      }

      summaries.add(
        MissedQuestionSummary(
          questionNumber: qNum,
          correctAnswer: correctAns,
          attempts: attempts,
          correctCount: correctCount,
        ),
      );
    }

    summaries.sort((a, b) => a.percentCorrect.compareTo(b.percentCorrect));
    if (summaries.length <= limit) {
      return summaries;
    }
    return summaries.sublist(0, limit);
  }
}
