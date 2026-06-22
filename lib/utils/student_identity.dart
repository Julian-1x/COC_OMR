import 'package:omr_app/models/exam_data.dart';

/// Canonical form for roster matching (phone, web, cloud).
String normalizeSchoolId(String value) => value.trim().toUpperCase();

String _studentGroupKey(Student student) =>
    '${student.ownerTeacherId ?? ''}|${normalizeSchoolId(student.schoolId)}';

int _omrNumericValue(String omrId) => int.tryParse(omrId) ?? 999999;

int _scanCountForOmr(List<ScanResult> scanResults, String omrId) =>
    scanResults.where((result) => result.studentOmrId == omrId).length;

/// Result of collapsing duplicate students that share the same school ID.
class StudentDedupeResult {
  const StudentDedupeResult({
    required this.students,
    required this.scanResults,
    required this.removedOmrIds,
    required this.mergedCount,
  });

  final List<Student> students;
  final List<ScanResult> scanResults;
  final List<String> removedOmrIds;
  final int mergedCount;
}

/// Picks the canonical student when multiple rows share a school ID.
Student pickCanonicalStudent(
  List<Student> duplicates,
  List<ScanResult> scanResults,
) {
  assert(duplicates.isNotEmpty);
  if (duplicates.length == 1) {
    return duplicates.first;
  }

  duplicates.sort((a, b) {
    final scanDiff =
        _scanCountForOmr(scanResults, b.omrId) -
        _scanCountForOmr(scanResults, a.omrId);
    if (scanDiff != 0) {
      return scanDiff;
    }

    final omrDiff = _omrNumericValue(a.omrId) - _omrNumericValue(b.omrId);
    if (omrDiff != 0) {
      return omrDiff;
    }

    return b.updatedAt.compareTo(a.updatedAt);
  });

  final winner = duplicates.first;
  final newest = duplicates.reduce(
    (current, candidate) =>
        candidate.updatedAt.isAfter(current.updatedAt) ? candidate : current,
  );

  return winner.copyWith(
    name: newest.name,
    section: newest.section,
    schoolId: newest.schoolId,
    score: winner.score ?? newest.score,
    answers: winner.answers ?? newest.answers,
    scanDate: winner.scanDate ?? newest.scanDate,
    confidence: winner.confidence ?? newest.confidence,
    cloudId: winner.cloudId ?? newest.cloudId,
    ownerTeacherId: winner.ownerTeacherId ?? newest.ownerTeacherId,
    syncStatus: winner.syncStatus == SyncStatus.pending ||
            newest.syncStatus == SyncStatus.pending
        ? SyncStatus.pending
        : winner.syncStatus,
    updatedAt: newest.updatedAt,
  );
}

ScanResult _repointScan(ScanResult scan, String canonicalOmrId) {
  if (scan.studentOmrId == canonicalOmrId) {
    return scan;
  }

  return ScanResult.fromJson(<String, dynamic>{
    ...scan.toJson(),
    'studentOmrId': canonicalOmrId,
    'syncStatus': SyncStatus.pending,
    'updatedAt': DateTime.now().toIso8601String(),
  });
}

/// Collapse duplicate students (same owner + school ID) and re-point scans.
StudentDedupeResult dedupeStudentRoster({
  required List<Student> students,
  required List<ScanResult> scanResults,
}) {
  final groups = <String, List<Student>>{};
  for (final student in students) {
    if (normalizeSchoolId(student.schoolId).isEmpty) {
      continue;
    }
    groups.putIfAbsent(_studentGroupKey(student), () => []).add(student);
  }

  final removedOmrIds = <String>{};
  final omrRedirect = <String, String>{};
  final canonicalStudents = <Student>[];
  var mergedCount = 0;

  for (final group in groups.values) {
    if (group.length == 1) {
      canonicalStudents.add(group.first);
      continue;
    }

    mergedCount += group.length - 1;
    final winner = pickCanonicalStudent(group, scanResults);
    for (final duplicate in group) {
      if (duplicate.omrId == winner.omrId) {
        continue;
      }
      removedOmrIds.add(duplicate.omrId);
      omrRedirect[duplicate.omrId] = winner.omrId;
    }
    canonicalStudents.add(winner);
  }

  final studentsWithoutSchoolId = students
      .where((student) => normalizeSchoolId(student.schoolId).isEmpty)
      .toList();
  canonicalStudents.addAll(studentsWithoutSchoolId);

  canonicalStudents.sort((a, b) => a.omrId.compareTo(b.omrId));

  final updatedScans = scanResults
      .map(
        (scan) => omrRedirect.containsKey(scan.studentOmrId)
            ? _repointScan(scan, omrRedirect[scan.studentOmrId]!)
            : scan,
      )
      .toList();

  return StudentDedupeResult(
    students: canonicalStudents,
    scanResults: updatedScans,
    removedOmrIds: removedOmrIds.toList()..sort(),
    mergedCount: mergedCount,
  );
}

Student? findStudentBySchoolId(
  Iterable<Student> students,
  String schoolId,
) {
  final key = normalizeSchoolId(schoolId);
  if (key.isEmpty) {
    return null;
  }
  for (final student in students) {
    if (normalizeSchoolId(student.schoolId) == key) {
      return student;
    }
  }
  return null;
}
