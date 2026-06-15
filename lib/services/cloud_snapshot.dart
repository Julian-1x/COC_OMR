import 'package:omr_app/models/exam_data.dart';

/// Rows downloaded from Supabase before merging into local SQLite.
class CloudPullSnapshot {
  const CloudPullSnapshot({
    this.sections = const <Section>[],
    this.students = const <Student>[],
    this.subjects = const <Subject>[],
    this.scanResults = const <ScanResult>[],
    this.deadlines = const <Deadline>[],
  });

  final List<Section> sections;
  final List<Student> students;
  final List<Subject> subjects;
  final List<ScanResult> scanResults;
  final List<Deadline> deadlines;

  int get total =>
      sections.length +
      students.length +
      subjects.length +
      scanResults.length +
      deadlines.length;

  bool get isEmpty => total == 0;
}

class CloudMergeSummary {
  const CloudMergeSummary({
    required this.sections,
    required this.students,
    required this.subjects,
    required this.scanResults,
    required this.deadlines,
  });

  final int sections;
  final int students;
  final int subjects;
  final int scanResults;
  final int deadlines;

  int get total =>
      sections + students + subjects + scanResults + deadlines;
}

/// Merges a cloud snapshot into local lists using last-write-wins with
/// pending-local protection.
class CloudSnapshotMerger {
  const CloudSnapshotMerger._();

  static ({
    List<Section> sections,
    List<Student> students,
    List<Subject> subjects,
    List<ScanResult> scanResults,
    List<Deadline> deadlines,
    CloudMergeSummary summary,
  }) merge({
    required List<Section> localSections,
    required List<Student> localStudents,
    required List<Subject> localSubjects,
    required List<ScanResult> localScanResults,
    required List<Deadline> localDeadlines,
    required CloudPullSnapshot cloud,
  }) {
    final sections = _mergeSections(localSections, cloud.sections);
    final students = _mergeStudents(localStudents, cloud.students);
    final subjects = _mergeSubjects(localSubjects, cloud.subjects);
    final scanResults =
        _mergeScanResults(localScanResults, cloud.scanResults);
    final deadlines = _mergeDeadlines(localDeadlines, cloud.deadlines);

    return (
      sections: sections.merged,
      students: students.merged,
      subjects: subjects.merged,
      scanResults: scanResults.merged,
      deadlines: deadlines.merged,
      summary: CloudMergeSummary(
        sections: sections.applied,
        students: students.applied,
        subjects: subjects.applied,
        scanResults: scanResults.applied,
        deadlines: deadlines.applied,
      ),
    );
  }

  static _MergeResult<Section> _mergeSections(
    List<Section> local,
    List<Section> cloud,
  ) {
    final byName = <String, Section>{
      for (final entry in local) entry.name: entry,
    };
    var applied = 0;

    for (final cloudRow in cloud) {
      final existing = byName[cloudRow.name] ??
          _findByCloudId(local, cloudRow.cloudId, (entry) => entry.cloudId);
      final merged = _pickSection(existing, cloudRow);
      if (existing == null || !identical(existing, merged)) {
        applied++;
      }
      byName[cloudRow.name] = merged;
    }

    return _MergeResult(
      merged: byName.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      applied: applied,
    );
  }

  static _MergeResult<Student> _mergeStudents(
    List<Student> local,
    List<Student> cloud,
  ) {
    final byOmrId = <String, Student>{
      for (final entry in local) entry.omrId: entry,
    };
    var applied = 0;

    for (final cloudRow in cloud) {
      final existing = byOmrId[cloudRow.omrId] ??
          _findByCloudId(local, cloudRow.cloudId, (entry) => entry.cloudId);
      final merged = _pickStudent(existing, cloudRow);
      if (existing == null || existing.updatedAt != merged.updatedAt) {
        applied++;
      }
      byOmrId[cloudRow.omrId] = merged;
    }

    return _MergeResult(
      merged: byOmrId.values.toList()
        ..sort((a, b) => a.omrId.compareTo(b.omrId)),
      applied: applied,
    );
  }

  static _MergeResult<Subject> _mergeSubjects(
    List<Subject> local,
    List<Subject> cloud,
  ) {
    final byId = <String, Subject>{
      for (final entry in local) entry.id: entry,
    };
    var applied = 0;

    for (final cloudRow in cloud) {
      final existing = byId[cloudRow.id] ??
          _findByCloudId(local, cloudRow.cloudId, (entry) => entry.cloudId);
      final merged = _pickSubject(existing, cloudRow);
      if (existing == null || existing.updatedAt != merged.updatedAt) {
        applied++;
      }
      byId[cloudRow.id] = merged;
    }

    return _MergeResult(
      merged: byId.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      applied: applied,
    );
  }

  static _MergeResult<ScanResult> _mergeScanResults(
    List<ScanResult> local,
    List<ScanResult> cloud,
  ) {
    final merged = <ScanResult>[...local];
    var applied = 0;

    for (final cloudRow in cloud) {
      final index = merged.indexWhere(
        (entry) =>
            (cloudRow.cloudId != null &&
                entry.cloudId == cloudRow.cloudId) ||
            _sameScanIdentity(entry, cloudRow),
      );

      if (index < 0) {
        merged.add(cloudRow);
        applied++;
        continue;
      }

      final existing = merged[index];
      final picked = _pickScanResult(existing, cloudRow);
      if (picked.updatedAt != existing.updatedAt ||
          picked.cloudId != existing.cloudId) {
        applied++;
      }
      merged[index] = picked;
    }

    merged.sort((a, b) => a.scanTime.compareTo(b.scanTime));
    return _MergeResult(merged: merged, applied: applied);
  }

  static _MergeResult<Deadline> _mergeDeadlines(
    List<Deadline> local,
    List<Deadline> cloud,
  ) {
    final byId = <String, Deadline>{
      for (final entry in local) entry.id: entry,
    };
    var applied = 0;

    for (final cloudRow in cloud) {
      final existing = byId[cloudRow.id] ??
          _findByCloudId(local, cloudRow.cloudId, (entry) => entry.cloudId);
      final merged = _pickDeadline(existing, cloudRow);
      if (existing == null || existing.updatedAt != merged.updatedAt) {
        applied++;
      }
      byId[cloudRow.id] = merged;
    }

    return _MergeResult(
      merged: byId.values.toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
      applied: applied,
    );
  }

  static Section _pickSection(Section? local, Section cloud) {
    if (local == null) {
      return cloud;
    }
    if (_shouldKeepLocal(local.syncStatus, local.updatedAt, cloud.updatedAt) &&
        local.cloudId != null) {
      return local;
    }
    if (local.cloudId == null || !cloud.updatedAt.isBefore(local.updatedAt)) {
      return cloud;
    }
    return local;
  }

  static Student _pickStudent(Student? local, Student cloud) {
    if (local == null) {
      return cloud;
    }
    if (_shouldKeepLocal(local.syncStatus, local.updatedAt, cloud.updatedAt) &&
        local.cloudId != null) {
      return local;
    }
    if (local.cloudId == null || !cloud.updatedAt.isBefore(local.updatedAt)) {
      return cloud;
    }
    return local;
  }

  static Subject _pickSubject(Subject? local, Subject cloud) {
    if (local == null) {
      return cloud;
    }
    if (_shouldKeepLocal(local.syncStatus, local.updatedAt, cloud.updatedAt) &&
        local.cloudId != null) {
      return local;
    }
    if (local.cloudId == null || !cloud.updatedAt.isBefore(local.updatedAt)) {
      return cloud;
    }
    return local;
  }

  static ScanResult _pickScanResult(ScanResult local, ScanResult cloud) {
    if (_shouldKeepLocal(local.syncStatus, local.updatedAt, cloud.updatedAt) &&
        local.cloudId != null) {
      return local;
    }
    if (local.cloudId == null || !cloud.updatedAt.isBefore(local.updatedAt)) {
      return cloud;
    }
    return local;
  }

  static Deadline _pickDeadline(Deadline? local, Deadline cloud) {
    if (local == null) {
      return cloud;
    }
    if (_shouldKeepLocal(local.syncStatus, local.updatedAt, cloud.updatedAt) &&
        local.cloudId != null) {
      return local;
    }
    if (local.cloudId == null || !cloud.updatedAt.isBefore(local.updatedAt)) {
      return cloud;
    }
    return local;
  }

  static bool _shouldKeepLocal(
    String syncStatus,
    DateTime localUpdatedAt,
    DateTime cloudUpdatedAt,
  ) {
    return syncStatus == SyncStatus.pending &&
        !localUpdatedAt.isBefore(cloudUpdatedAt);
  }

  static bool _sameScanIdentity(ScanResult a, ScanResult b) {
    return a.studentOmrId == b.studentOmrId &&
        a.subjectId == b.subjectId &&
        a.subjectName == b.subjectName &&
        a.scanTime == b.scanTime;
  }

  static T? _findByCloudId<T>(
    List<T> entries,
    String? cloudId,
    String? Function(T entry) readCloudId,
  ) {
    if (cloudId == null || cloudId.isEmpty) {
      return null;
    }
    for (final entry in entries) {
      if (readCloudId(entry) == cloudId) {
        return entry;
      }
    }
    return null;
  }
}

class _MergeResult<T> {
  const _MergeResult({required this.merged, required this.applied});

  final List<T> merged;
  final int applied;
}
