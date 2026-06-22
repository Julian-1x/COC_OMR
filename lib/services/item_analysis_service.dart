import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';

/// Per-question stats for item analysis (p-value, distribution, discrimination).
class QuestionAnalysis {
  const QuestionAnalysis({
    required this.questionNumber,
    required this.correctAnswer,
    required this.totalAttempts,
    required this.correctCount,
    required this.partialCount,
    required this.answerDistribution,
    this.discriminationIndex,
  });

  final int questionNumber;
  final String correctAnswer;
  final int totalAttempts;
  final int correctCount;
  final int partialCount;
  final Map<String, int> answerDistribution;
  final double? discriminationIndex;

  double get difficulty =>
      totalAttempts > 0 ? correctCount / totalAttempts : 0;

  String get difficultyLabel {
    if (difficulty >= 0.8) return 'Easy';
    if (difficulty >= 0.5) return 'Medium';
    if (difficulty >= 0.3) return 'Hard';
    return 'Very Hard';
  }

  Color get difficultyColor {
    if (difficulty >= 0.8) return AppColors.statusSuccess;
    if (difficulty >= 0.5) return AppColors.statusWarning;
    if (difficulty >= 0.3) return AppColors.statusDanger;
    return AppColors.error;
  }
}

class ItemAnalysisReport {
  const ItemAnalysisReport({
    required this.questions,
    required this.gradedStudentCount,
    required this.pendingReviewCount,
    required this.supersededScanCount,
  });

  final List<QuestionAnalysis> questions;
  final int gradedStudentCount;
  final int pendingReviewCount;
  final int supersededScanCount;

  bool get hasGradedData => gradedStudentCount > 0;

  double get overallDifficulty {
    if (questions.isEmpty) {
      return 0;
    }
    return questions.fold<double>(0, (sum, q) => sum + q.difficulty) /
        questions.length;
  }

  List<QuestionAnalysis> get hardestQuestions {
    final sorted = List<QuestionAnalysis>.from(questions)
      ..sort((a, b) => a.difficulty.compareTo(b.difficulty));
    return sorted.take(5).toList();
  }
}

/// Item analysis aligned with [ExamSummaryService] grading rules.
abstract final class ItemAnalysisService {
  /// Blank responses appear as this bucket in distributions.
  static const String blankDistributionLabel = '—';

  static Future<ItemAnalysisReport?> build({
    required Subject subject,
    String? sectionName,
  }) async {
    final results = await LocalDataStore.instance.fetchScanResults(
      subjectId: subject.id,
      sectionName: sectionName,
    );
    return buildFromData(subject: subject, results: results);
  }

  static ItemAnalysisReport? buildFromData({
    required Subject subject,
    required List<ScanResult> results,
  }) {
    final pendingReviewCount =
        results.where((result) => result.requiresReview).length;
    final graded = _gradedLatestPerStudent(results);
    if (graded.isEmpty) {
      return null;
    }

    final supersededScanCount =
        results.where((result) => !result.requiresReview).length -
            graded.length;

    final questions = _computeQuestions(subject: subject, graded: graded);

    return ItemAnalysisReport(
      questions: questions,
      gradedStudentCount: graded.length,
      pendingReviewCount: pendingReviewCount,
      supersededScanCount: supersededScanCount,
    );
  }

  /// Approved scans only; latest scan per student wins.
  static List<ScanResult> _gradedLatestPerStudent(List<ScanResult> results) {
    final latestByStudent = <String, ScanResult>{};
    for (final result in results) {
      if (result.requiresReview) {
        continue;
      }
      final existing = latestByStudent[result.studentOmrId];
      if (existing == null || result.scanTime.isAfter(existing.scanTime)) {
        latestByStudent[result.studentOmrId] = result;
      }
    }
    return latestByStudent.values.toList();
  }

  static List<QuestionAnalysis> _computeQuestions({
    required Subject subject,
    required List<ScanResult> graded,
  }) {
    final totalQuestions = subject.totalQuestions;
    final analyses = List<QuestionAnalysis>.generate(totalQuestions, (index) {
      final qNum = index + 1;
      return QuestionAnalysis(
        questionNumber: qNum,
        correctAnswer: _formatCorrectAnswer(subject.answerKey[qNum]),
        totalAttempts: 0,
        correctCount: 0,
        partialCount: 0,
        answerDistribution: const {},
      );
    });

    for (var qIndex = 0; qIndex < totalQuestions; qIndex++) {
      final qNum = qIndex + 1;
      var attempts = 0;
      var correctCount = 0;
      var partialCount = 0;
      final distribution = <String, int>{};

      for (final result in graded) {
        attempts++;
        final storedAnswer = result.detectedAnswers[qNum];
        final label = _distributionLabel(storedAnswer);
        distribution[label] = (distribution[label] ?? 0) + 1;

        final score = subject.calculateQuestionScore(qNum, storedAnswer);
        if (score >= 1.0) {
          correctCount++;
        } else if (score > 0) {
          partialCount++;
        }
      }

      analyses[qIndex] = QuestionAnalysis(
        questionNumber: qNum,
        correctAnswer: _formatCorrectAnswer(subject.answerKey[qNum]),
        totalAttempts: attempts,
        correctCount: correctCount,
        partialCount: partialCount,
        answerDistribution: distribution,
        discriminationIndex: _discriminationIndex(
          subject: subject,
          questionNumber: qNum,
          graded: graded,
        ),
      );
    }

    return analyses;
  }

  static double? _discriminationIndex({
    required Subject subject,
    required int questionNumber,
    required List<ScanResult> graded,
  }) {
    if (graded.length < 4) {
      return null;
    }

    final sorted = List<ScanResult>.from(graded)
      ..sort((a, b) => b.percentage.compareTo(a.percentage));

    final groupSize =
        (sorted.length * 0.27).ceil().clamp(1, sorted.length ~/ 2);
    final topGroup = sorted.take(groupSize);
    final bottomGroup = sorted.skip(sorted.length - groupSize).take(groupSize);

    var topCorrect = 0;
    var bottomCorrect = 0;
    for (final result in topGroup) {
      if (_isFullyCorrect(subject, questionNumber, result.detectedAnswers[questionNumber])) {
        topCorrect++;
      }
    }
    for (final result in bottomGroup) {
      if (_isFullyCorrect(subject, questionNumber, result.detectedAnswers[questionNumber])) {
        bottomCorrect++;
      }
    }

    return (topCorrect - bottomCorrect) / groupSize;
  }

  static bool _isFullyCorrect(
    Subject subject,
    int questionNumber,
    String? storedAnswer,
  ) =>
      subject.calculateQuestionScore(questionNumber, storedAnswer) >= 1.0;

  static bool isDistributionChoiceCorrect(
    Subject subject,
    int questionNumber,
    String distributionLabel,
  ) {
    if (distributionLabel == blankDistributionLabel) {
      return false;
    }
    return _isFullyCorrect(subject, questionNumber, distributionLabel);
  }

  static String _formatCorrectAnswer(List<String>? keyAnswers) {
    if (keyAnswers == null || keyAnswers.isEmpty) {
      return '?';
    }
    return keyAnswers.join('+');
  }

  static String _distributionLabel(String? storedAnswer) {
    final trimmed = storedAnswer?.trim() ?? '';
    return trimmed.isEmpty ? blankDistributionLabel : trimmed;
  }
}
