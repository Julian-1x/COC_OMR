import 'dart:convert';

import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/answer_key_io_service.dart';

/// How to apply a backup when the phone already has overlapping data.
enum BackupRestoreMode {
  /// Current teacher data becomes exactly the backup (other teachers untouched).
  replaceAll,

  /// Keep everything already on the phone; only add IDs that are missing.
  addMissingOnly,

  /// Keep phone-only rows; overlapping IDs take the backup version.
  mergePreferBackup,
}

class BackupBucketStats {
  const BackupBucketStats({
    required this.phoneOnly,
    required this.backupOnly,
    required this.same,
    required this.conflict,
  });

  final int phoneOnly;
  final int backupOnly;
  final int same;
  final int conflict;

  int get overlap => same + conflict;
  bool get hasConflicts => conflict > 0;
  bool get hasNewFromBackup => backupOnly > 0;
}

class BackupCompareReport {
  const BackupCompareReport({
    required this.students,
    required this.sections,
    required this.subjects,
    required this.scans,
    required this.layouts,
    required this.exportedAt,
  });

  final BackupBucketStats students;
  final BackupBucketStats sections;
  final BackupBucketStats subjects;
  final BackupBucketStats scans;
  final BackupBucketStats layouts;
  final String? exportedAt;

  bool get hasConflicts =>
      students.hasConflicts ||
      sections.hasConflicts ||
      subjects.hasConflicts ||
      scans.hasConflicts ||
      layouts.hasConflicts;

  bool get hasNewFromBackup =>
      students.hasNewFromBackup ||
      sections.hasNewFromBackup ||
      subjects.hasNewFromBackup ||
      scans.hasNewFromBackup ||
      layouts.hasNewFromBackup;

  int get totalConflicts =>
      students.conflict +
      sections.conflict +
      subjects.conflict +
      scans.conflict +
      layouts.conflict;
}

class BackupSnapshotData {
  const BackupSnapshotData({
    required this.students,
    required this.sections,
    required this.subjects,
    required this.scanResults,
    required this.deadlines,
    required this.exportRecords,
    required this.answerKeyTemplates,
    required this.customSheetLayouts,
    required this.omrCounter,
    required this.subjectCounter,
    required this.sheetCounter,
    this.exportedAt,
  });

  final List<Student> students;
  final List<Section> sections;
  final List<Subject> subjects;
  final List<ScanResult> scanResults;
  final List<Deadline> deadlines;
  final List<ExportRecord> exportRecords;
  final List<AnswerKeyTemplate> answerKeyTemplates;
  final List<CustomSheetLayout> customSheetLayouts;
  final int? omrCounter;
  final int? subjectCounter;
  final int? sheetCounter;
  final String? exportedAt;

  factory BackupSnapshotData.fromBackupMap(Map<String, dynamic> decoded) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    int? readCounter(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '');
    }

    return BackupSnapshotData(
      students: (decoded['students'] as List? ?? const <dynamic>[])
          .map((e) => Student.fromJson(asMap(e)))
          .toList(),
      sections: (decoded['sections'] as List? ?? const <dynamic>[])
          .map((e) => Section.fromJson(asMap(e)))
          .toList(),
      subjects: (decoded['subjects'] as List? ?? const <dynamic>[])
          .map((e) => Subject.fromJson(asMap(e)))
          .toList(),
      scanResults: (decoded['scanResults'] as List? ?? const <dynamic>[])
          .map((e) => ScanResult.fromJson(asMap(e)))
          .toList(),
      deadlines: (decoded['deadlines'] as List? ?? const <dynamic>[])
          .map((e) => Deadline.fromJson(asMap(e)))
          .toList(),
      exportRecords: (decoded['exportRecords'] as List? ?? const <dynamic>[])
          .map((e) => ExportRecord.fromJson(asMap(e)))
          .toList(),
      answerKeyTemplates:
          (decoded['answerKeyTemplates'] as List? ?? const <dynamic>[])
              .map((e) => AnswerKeyTemplate.fromJson(asMap(e)))
              .toList(),
      customSheetLayouts:
          (decoded['customSheetLayouts'] as List? ?? const <dynamic>[])
              .map((e) => CustomSheetLayout.fromJson(asMap(e)))
              .toList(),
      omrCounter: readCounter(decoded['omrCounter']),
      subjectCounter: readCounter(decoded['subjectCounter']),
      sheetCounter: readCounter(decoded['sheetCounter']),
      exportedAt: decoded['exportedAt']?.toString(),
    );
  }
}

String backupStudentKey(Student s) => s.omrId.trim().toLowerCase();

String backupSectionKey(Section s) => s.name.trim().toLowerCase();

String backupSubjectKey(Subject s) => s.id.trim().toLowerCase();

String backupScanKey(ScanResult s) {
  final subject = (s.subjectId?.trim().isNotEmpty ?? false)
      ? s.subjectId!.trim().toLowerCase()
      : s.subjectName.trim().toLowerCase();
  return '${s.studentOmrId.trim().toLowerCase()}|$subject';
}

String backupLayoutKey(CustomSheetLayout layout) => layout.id.trim().toLowerCase();

String _fingerprint(Map<String, dynamic> json) {
  final cleaned = Map<String, dynamic>.from(json)
    ..remove('updatedAt')
    ..remove('syncStatus')
    ..remove('cloudId')
    ..remove('ownerTeacherId');
  return jsonEncode(cleaned);
}

BackupBucketStats compareKeyedMaps<T>({
  required Map<String, T> phone,
  required Map<String, T> backup,
  required String Function(T value) fingerprint,
}) {
  var phoneOnly = 0;
  var backupOnly = 0;
  var same = 0;
  var conflict = 0;

  for (final key in phone.keys) {
    if (!backup.containsKey(key)) {
      phoneOnly++;
    }
  }
  for (final entry in backup.entries) {
    final phoneValue = phone[entry.key];
    if (phoneValue == null) {
      backupOnly++;
      continue;
    }
    if (fingerprint(phoneValue) == fingerprint(entry.value)) {
      same++;
    } else {
      conflict++;
    }
  }

  return BackupBucketStats(
    phoneOnly: phoneOnly,
    backupOnly: backupOnly,
    same: same,
    conflict: conflict,
  );
}

BackupCompareReport compareBackupToPhone({
  required BackupSnapshotData phone,
  required BackupSnapshotData backup,
}) {
  final phoneStudents = {
    for (final s in phone.students) backupStudentKey(s): s,
  };
  final backupStudents = {
    for (final s in backup.students) backupStudentKey(s): s,
  };
  final phoneSections = {
    for (final s in phone.sections) backupSectionKey(s): s,
  };
  final backupSections = {
    for (final s in backup.sections) backupSectionKey(s): s,
  };
  final phoneSubjects = {
    for (final s in phone.subjects) backupSubjectKey(s): s,
  };
  final backupSubjects = {
    for (final s in backup.subjects) backupSubjectKey(s): s,
  };
  final phoneScans = {
    for (final s in phone.scanResults) backupScanKey(s): s,
  };
  final backupScans = {
    for (final s in backup.scanResults) backupScanKey(s): s,
  };
  final phoneLayouts = {
    for (final s in phone.customSheetLayouts) backupLayoutKey(s): s,
  };
  final backupLayouts = {
    for (final s in backup.customSheetLayouts) backupLayoutKey(s): s,
  };

  return BackupCompareReport(
    students: compareKeyedMaps(
      phone: phoneStudents,
      backup: backupStudents,
      fingerprint: (s) => _fingerprint(s.toJson()),
    ),
    sections: compareKeyedMaps(
      phone: phoneSections,
      backup: backupSections,
      fingerprint: (s) => _fingerprint(s.toJson()),
    ),
    subjects: compareKeyedMaps(
      phone: phoneSubjects,
      backup: backupSubjects,
      fingerprint: (s) => _fingerprint(s.toJson()),
    ),
    scans: compareKeyedMaps(
      phone: phoneScans,
      backup: backupScans,
      fingerprint: (s) => _fingerprint(s.toJson()),
    ),
    layouts: compareKeyedMaps(
      phone: phoneLayouts,
      backup: backupLayouts,
      fingerprint: (s) => _fingerprint(s.toJson()),
    ),
    exportedAt: backup.exportedAt,
  );
}

List<T> mergeByKey<T>({
  required List<T> phone,
  required List<T> backup,
  required String Function(T value) keyOf,
  required BackupRestoreMode mode,
}) {
  if (mode == BackupRestoreMode.replaceAll) {
    return List<T>.from(backup);
  }

  final map = <String, T>{
    for (final item in phone) keyOf(item): item,
  };

  for (final item in backup) {
    final key = keyOf(item);
    if (!map.containsKey(key)) {
      map[key] = item;
      continue;
    }
    if (mode == BackupRestoreMode.mergePreferBackup) {
      map[key] = item;
    }
    // addMissingOnly: leave phone value
  }

  return map.values.toList();
}

BackupSnapshotData mergeBackupSnapshots({
  required BackupSnapshotData phone,
  required BackupSnapshotData backup,
  required BackupRestoreMode mode,
}) {
  if (mode == BackupRestoreMode.replaceAll) {
    return backup;
  }

  int? maxCounter(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  return BackupSnapshotData(
    students: mergeByKey(
      phone: phone.students,
      backup: backup.students,
      keyOf: backupStudentKey,
      mode: mode,
    ),
    sections: mergeByKey(
      phone: phone.sections,
      backup: backup.sections,
      keyOf: backupSectionKey,
      mode: mode,
    ),
    subjects: mergeByKey(
      phone: phone.subjects,
      backup: backup.subjects,
      keyOf: backupSubjectKey,
      mode: mode,
    ),
    scanResults: mergeByKey(
      phone: phone.scanResults,
      backup: backup.scanResults,
      keyOf: backupScanKey,
      mode: mode,
    ),
    deadlines: mergeByKey(
      phone: phone.deadlines,
      backup: backup.deadlines,
      keyOf: (d) => d.id.trim().toLowerCase(),
      mode: mode,
    ),
    exportRecords: mergeByKey(
      phone: phone.exportRecords,
      backup: backup.exportRecords,
      keyOf: (e) =>
          '${e.sectionName.trim().toLowerCase()}|${e.exportedAt.toIso8601String()}',
      mode: mode,
    ),
    answerKeyTemplates: mergeByKey(
      phone: phone.answerKeyTemplates,
      backup: backup.answerKeyTemplates,
      keyOf: (t) => t.id.trim().toLowerCase(),
      mode: mode,
    ),
    customSheetLayouts: mergeByKey(
      phone: phone.customSheetLayouts,
      backup: backup.customSheetLayouts,
      keyOf: backupLayoutKey,
      mode: mode,
    ),
    omrCounter: maxCounter(phone.omrCounter, backup.omrCounter),
    subjectCounter: maxCounter(phone.subjectCounter, backup.subjectCounter),
    sheetCounter: maxCounter(phone.sheetCounter, backup.sheetCounter),
    exportedAt: backup.exportedAt,
  );
}

BackupSnapshotData phoneSnapshotFromGlobals() {
  return BackupSnapshotData(
    students: List<Student>.from(globalStudentDatabase),
    sections: List<Section>.from(globalSections),
    subjects: List<Subject>.from(globalSubjects),
    scanResults: List<ScanResult>.from(globalScanResults),
    deadlines: List<Deadline>.from(globalDeadlines),
    exportRecords: List<ExportRecord>.from(globalExportRecords),
    answerKeyTemplates: List<AnswerKeyTemplate>.from(globalAnswerKeyTemplates),
    customSheetLayouts: List<CustomSheetLayout>.from(globalCustomSheetLayouts),
    omrCounter: nextOmrIdValue,
    subjectCounter: nextSubjectCounterValue,
    sheetCounter: nextSheetCounterValue,
  );
}
