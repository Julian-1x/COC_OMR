import 'package:omr_app/models/exam_data.dart';

enum ExamDayStatus {
  missing,
  needsReview,
  duplicate,
  absent,
  done,
}

class ExamDayBoardRow {
  const ExamDayBoardRow({
    required this.omrId,
    required this.status,
    required this.scans,
    this.student,
  });

  final String omrId;
  final Student? student;
  final ExamDayStatus status;
  final List<ScanResult> scans;

  String get displayName => student?.name.trim().isNotEmpty == true
      ? student!.name.trim()
      : 'OMR $omrId';

  ScanResult? get latestScan {
    if (scans.isEmpty) {
      return null;
    }
    return scans.reduce(
      (best, next) => next.scanTime.isAfter(best.scanTime) ? next : best,
    );
  }

  String? get statusDetail {
    switch (status) {
      case ExamDayStatus.missing:
        return 'No sheet scanned for this exam.';
      case ExamDayStatus.absent:
        return 'Marked absent. Scan later if the paper is found.';
      case ExamDayStatus.needsReview:
        final reasons = latestScan?.reviewReasons ?? const <String>[];
        if (reasons.isNotEmpty) {
          return reasons.first;
        }
        if (latestScan?.isLowConfidence == true) {
          return 'Low confidence — check this sheet before counting the score.';
        }
        return 'Waiting in the review queue.';
      case ExamDayStatus.duplicate:
        if (scans.length > 1) {
          return '${scans.length} scans for this student. Keep the correct sheet.';
        }
        return 'This student was scanned more than once. Confirm which sheet to keep.';
      case ExamDayStatus.done:
        final scan = latestScan;
        if (scan == null) {
          return null;
        }
        return '${scan.scoreDisplay}/${scan.totalQuestions}';
    }
  }
}

class ExamDayBoardReport {
  const ExamDayBoardReport({
    required this.sectionName,
    required this.subject,
    required this.rows,
    required this.unmatchedScans,
  });

  final String sectionName;
  final Subject subject;
  final List<ExamDayBoardRow> rows;
  final List<ScanResult> unmatchedScans;

  int get rosterCount => rows.length;
  int get doneCount => _count(ExamDayStatus.done);
  int get missingCount => _count(ExamDayStatus.missing);
  int get reviewCount => _count(ExamDayStatus.needsReview);
  int get duplicateCount => _count(ExamDayStatus.duplicate);
  int get absentCount => _count(ExamDayStatus.absent);
  int get unmatchedCount => unmatchedScans.length;

  bool get isReadyToClose =>
      missingCount == 0 && reviewCount == 0 && duplicateCount == 0;

  int _count(ExamDayStatus status) =>
      rows.where((row) => row.status == status).length;
}

/// Joins a section roster with scans for one exam. No bubble geometry involved.
abstract final class ExamDayBoardService {
  static ExamDayBoardReport build({
    required Subject subject,
    required String sectionName,
    required List<Student> students,
    required List<ScanResult> scans,
    Set<String> absentOmrIds = const <String>{},
  }) {
    final normalizedSection = normalizeSectionName(sectionName);
    final roster = students
        .where(
          (student) =>
              normalizeSectionName(student.section) == normalizedSection,
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final subjectScans = scans.where((scan) => _matchesSubject(scan, subject)).toList();
    final rosterOmrIds = {
      for (final student in roster) student.omrId,
    };

    final scansByOmr = <String, List<ScanResult>>{};
    final unmatched = <ScanResult>[];
    for (final scan in subjectScans) {
      if (rosterOmrIds.contains(scan.studentOmrId)) {
        scansByOmr.putIfAbsent(scan.studentOmrId, () => <ScanResult>[]).add(scan);
      } else {
        unmatched.add(scan);
      }
    }

    final rows = <ExamDayBoardRow>[
      for (final student in roster)
        ExamDayBoardRow(
          omrId: student.omrId,
          student: student,
          scans: scansByOmr[student.omrId] ?? const <ScanResult>[],
          status: classify(
            scans: scansByOmr[student.omrId] ?? const <ScanResult>[],
            markedAbsent: absentOmrIds.contains(student.omrId),
          ),
        ),
    ];

    unmatched.sort((a, b) => b.scanTime.compareTo(a.scanTime));

    return ExamDayBoardReport(
      sectionName: normalizedSection,
      subject: subject,
      rows: rows,
      unmatchedScans: unmatched,
    );
  }

  static ExamDayStatus classify({
    required List<ScanResult> scans,
    bool markedAbsent = false,
  }) {
    if (scans.length > 1 || (scans.length == 1 && _looksLikeRescan(scans.first))) {
      return ExamDayStatus.duplicate;
    }
    if (scans.length == 1 && scans.first.requiresReview) {
      return ExamDayStatus.needsReview;
    }
    if (scans.isNotEmpty) {
      return ExamDayStatus.done;
    }
    if (markedAbsent) {
      return ExamDayStatus.absent;
    }
    return ExamDayStatus.missing;
  }

  static bool _matchesSubject(ScanResult scan, Subject subject) {
    final scanId = scan.subjectId?.trim();
    if (scanId != null && scanId.isNotEmpty) {
      return scanId == subject.id;
    }
    return scan.subjectName.trim().toLowerCase() ==
        subject.name.trim().toLowerCase();
  }

  static bool _looksLikeRescan(ScanResult scan) {
    if (!scan.requiresReview) {
      return false;
    }
    final blob = scan.reviewReasons.join(' ').toLowerCase();
    return blob.contains('rescan') ||
        blob.contains('already-scanned') ||
        blob.contains('already scanned');
  }
}
