import 'package:omr_app/models/exam_data.dart';

enum ScanReassignStatus {
  ready,
  sameStudent,
  targetNotFound,
  targetHasExistingScore,
}

/// Pure planning helper — never mutates scans. LocalDataStore applies the move.
class ScanReassignPlan {
  const ScanReassignPlan({
    required this.status,
    this.target,
    this.existingOnTarget,
  });

  final ScanReassignStatus status;
  final Student? target;
  final ScanResult? existingOnTarget;

  bool get canReassignWithoutReplace => status == ScanReassignStatus.ready;

  bool get requiresTeacherNameCheck =>
      status == ScanReassignStatus.targetHasExistingScore;
}

abstract final class ScanReassignService {
  static bool matchesSubject(ScanResult scan, ScanResult other) {
    if (scan.subjectId != null &&
        other.subjectId != null &&
        scan.subjectId!.isNotEmpty &&
        other.subjectId!.isNotEmpty) {
      return scan.subjectId == other.subjectId;
    }
    return scan.subjectName.trim().toLowerCase() ==
        other.subjectName.trim().toLowerCase();
  }

  static ScanResult? findExistingForStudentSubject({
    required String studentOmrId,
    required ScanResult template,
    required List<ScanResult> scans,
  }) {
    final matches = scans
        .where(
          (scan) =>
              scan.studentOmrId == studentOmrId &&
              matchesSubject(scan, template) &&
              // Do not treat the sheet we are moving as a conflict with itself.
              scan.scanTime != template.scanTime,
        )
        .toList()
      ..sort((a, b) => b.scanTime.compareTo(a.scanTime));
    return matches.isEmpty ? null : matches.first;
  }

  static ScanReassignPlan plan({
    required ScanResult scan,
    required String targetOmrId,
    required List<Student> students,
    required List<ScanResult> scans,
  }) {
    final normalized = targetOmrId.trim();
    if (normalized.isEmpty) {
      return const ScanReassignPlan(status: ScanReassignStatus.targetNotFound);
    }
    if (normalized == scan.studentOmrId) {
      return const ScanReassignPlan(status: ScanReassignStatus.sameStudent);
    }

    Student? target;
    for (final student in students) {
      if (student.omrId == normalized) {
        target = student;
        break;
      }
    }
    if (target == null) {
      return const ScanReassignPlan(status: ScanReassignStatus.targetNotFound);
    }

    final existing = findExistingForStudentSubject(
      studentOmrId: normalized,
      template: scan,
      scans: scans,
    );
    if (existing != null) {
      return ScanReassignPlan(
        status: ScanReassignStatus.targetHasExistingScore,
        target: target,
        existingOnTarget: existing,
      );
    }

    return ScanReassignPlan(
      status: ScanReassignStatus.ready,
      target: target,
    );
  }
}
