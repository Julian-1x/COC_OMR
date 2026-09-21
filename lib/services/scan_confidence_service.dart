import 'package:omr_app/models/exam_data.dart';

/// Teacher-facing severity for a scan's existing safety reasons.
///
/// Does not re-run OMR detection — classifies output from `_assessScanSafety`
/// / [ScanResult.reviewReasons] into plain-language tiers.
enum ScanConfidenceLevel {
  /// No review reasons — score is fine to keep.
  safe,

  /// Soft risk (blanks, light marks) — still review, but less urgent.
  check,

  /// Hard risk (ID, doubles, alignment, mismatch) — must not count yet.
  mustReview,
}

class ScanConfidenceReport {
  const ScanConfidenceReport({
    required this.level,
    required this.reasons,
    required this.flaggedQuestions,
  });

  final ScanConfidenceLevel level;
  final List<String> reasons;
  final List<int> flaggedQuestions;

  String get title => switch (level) {
        ScanConfidenceLevel.safe => 'Safe to keep',
        ScanConfidenceLevel.check => 'Check before counting',
        ScanConfidenceLevel.mustReview => 'Must review',
      };

  bool get requiresReview => level != ScanConfidenceLevel.safe;

  /// Top reasons for teacher UI (max 3).
  List<String> get topReasons => reasons.take(3).toList(growable: false);

  String? get primaryReason => reasons.isEmpty ? null : reasons.first;
}

class ScanConfidenceBatchSummary {
  const ScanConfidenceBatchSummary({
    required this.safe,
    required this.check,
    required this.mustReview,
    required this.riskyScans,
  });

  final int safe;
  final int check;
  final int mustReview;
  final List<ScanResult> riskyScans;

  int get total => safe + check + mustReview;
  int get needsAttention => check + mustReview;
}

/// Maps stored review reasons into [ScanConfidenceLevel] labels.
abstract final class ScanConfidenceService {
  static ScanConfidenceReport assess({
    required List<String> reviewReasons,
    List<int> flaggedQuestions = const <int>[],
    double? confidence,
  }) {
    final reasons = <String>[
      for (final reason in reviewReasons)
        if (reason.trim().isNotEmpty) reason.trim(),
    ];
    final flags = flaggedQuestions.toSet().toList()..sort();

    if (reasons.isEmpty && flags.isEmpty) {
      if (confidence != null && confidence < 0.7) {
        return ScanConfidenceReport(
          level: ScanConfidenceLevel.mustReview,
          reasons: <String>[
            'Low scan confidence (${(confidence * 100).round()}%).',
          ],
          flaggedQuestions: flags,
        );
      }
      return ScanConfidenceReport(
        level: ScanConfidenceLevel.safe,
        reasons: const <String>[],
        flaggedQuestions: flags,
      );
    }

    var level = ScanConfidenceLevel.check;
    for (final reason in reasons) {
      final classified = classifyReason(reason);
      if (classified == ScanConfidenceLevel.mustReview) {
        level = ScanConfidenceLevel.mustReview;
        break;
      }
      if (classified == ScanConfidenceLevel.check) {
        level = ScanConfidenceLevel.check;
      }
    }

    // Flagged questions with no classifiable reasons still need eyes on them.
    if (reasons.isEmpty && flags.isNotEmpty) {
      level = ScanConfidenceLevel.mustReview;
    }

    if (confidence != null &&
        confidence < 0.7 &&
        level == ScanConfidenceLevel.check) {
      level = ScanConfidenceLevel.mustReview;
    }

    return ScanConfidenceReport(
      level: level,
      reasons: reasons,
      flaggedQuestions: flags,
    );
  }

  static ScanConfidenceReport fromScanResult(ScanResult scan) {
    return assess(
      reviewReasons: scan.reviewReasons,
      flaggedQuestions: scan.flaggedQuestions,
      confidence: scan.confidence,
    );
  }

  /// Classifies one reason string from the scanner safety assessment.
  static ScanConfidenceLevel classifyReason(String reason) {
    final text = reason.toLowerCase();

    // Hard risks first — identity, doubles, alignment, template.
    // (Checked before soft rules because some hard reasons also say "left blank".)
    if (text.contains('low scan confidence') ||
        text.contains('omr id digit') ||
        text.contains('not assigned') ||
        text.contains('subject has no assigned') ||
        text.contains('template qr') ||
        text.contains('invalid answer') ||
        text.contains('more than one mark') ||
        text.contains('needs your choice') ||
        text.contains('crumpled') ||
        text.contains('auto-calibration failed') ||
        text.contains('alignment marks only partly') ||
        text.contains('answer grid may not match') ||
        text.contains('last-resort') ||
        text.contains('layout could not be confirmed') ||
        text.contains('section mismatch') ||
        text.contains('does not match the saved answer key') ||
        text.contains('verify the sheet') ||
        text.contains('verify sheet positioning') ||
        text.contains('verify the marked answers') ||
        text.contains('verify the 4-digit id') ||
        text.contains('verify alignment')) {
      return ScanConfidenceLevel.mustReview;
    }

    // Soft / informational — confirm but not identity/template failure.
    if (text.contains('lightly marked') ||
        text.contains('faint scratch') ||
        text.contains('uncertain mark') ||
        text.contains('left blank') ||
        text.contains('questions left blank') ||
        text.contains('question left blank')) {
      return ScanConfidenceLevel.check;
    }

    // Unknown reason → fail safe (treat as must review).
    return ScanConfidenceLevel.mustReview;
  }

  static ScanConfidenceBatchSummary summarizeBatch(Iterable<ScanResult> scans) {
    var safe = 0;
    var check = 0;
    var mustReview = 0;
    final risky = <ScanResult>[];

    for (final scan in scans) {
      final report = fromScanResult(scan);
      switch (report.level) {
        case ScanConfidenceLevel.safe:
          safe++;
        case ScanConfidenceLevel.check:
          check++;
          risky.add(scan);
        case ScanConfidenceLevel.mustReview:
          mustReview++;
          risky.add(scan);
      }
    }

    return ScanConfidenceBatchSummary(
      safe: safe,
      check: check,
      mustReview: mustReview,
      riskyScans: risky,
    );
  }
}
