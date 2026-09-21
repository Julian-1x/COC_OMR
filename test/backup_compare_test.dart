import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/backup_compare.dart';

Student _student({
  required String omrId,
  required String name,
  String section = 'A',
}) {
  return Student(
    schoolId: omrId,
    omrId: omrId,
    name: name,
    section: section,
  );
}

Subject _subject({
  required String id,
  required String name,
  int total = 50,
}) {
  return Subject(
    id: id,
    name: name,
    answerKey: {1: 'A'},
    totalQuestions: total,
  );
}

ScanResult _scan({
  required String omrId,
  required String subjectId,
  required int score,
}) {
  return ScanResult(
    studentOmrId: omrId,
    subjectId: subjectId,
    subjectName: 'Math',
    detectedAnswers: const {1: 'A'},
    correctnessMap: const {1: 1.0},
    score: score,
    totalQuestions: 50,
    confidence: 0.9,
    scanTime: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}

BackupSnapshotData _snap({
  List<Student> students = const [],
  List<Section> sections = const [],
  List<Subject> subjects = const [],
  List<ScanResult> scans = const [],
}) {
  return BackupSnapshotData(
    students: students,
    sections: sections,
    subjects: subjects,
    scanResults: scans,
    deadlines: const [],
    exportRecords: const [],
    answerKeyTemplates: const [],
    customSheetLayouts: const [],
    omrCounter: 10,
    subjectCounter: 2,
    sheetCounter: 2,
  );
}

void main() {
  test('compareBackupToPhone reports same, conflict, and only-sides', () {
    final phone = _snap(
      students: [
        _student(omrId: '0001', name: 'Ann'),
        _student(omrId: '0002', name: 'Ben'),
      ],
      subjects: [_subject(id: 'math', name: 'Math')],
      scans: [_scan(omrId: '0001', subjectId: 'math', score: 40)],
    );
    final backup = _snap(
      students: [
        _student(omrId: '0001', name: 'Ann'),
        _student(omrId: '0002', name: 'Benjamin'),
        _student(omrId: '0003', name: 'Cara'),
      ],
      subjects: [_subject(id: 'math', name: 'Math')],
      scans: [_scan(omrId: '0001', subjectId: 'math', score: 45)],
    );

    final report = compareBackupToPhone(phone: phone, backup: backup);
    expect(report.students.same, 1);
    expect(report.students.conflict, 1);
    expect(report.students.backupOnly, 1);
    expect(report.students.phoneOnly, 0);
    expect(report.scans.conflict, 1);
    expect(report.hasConflicts, isTrue);
  });

  test('addMissingOnly keeps phone overlaps and adds new', () {
    final phone = _snap(
      students: [_student(omrId: '0001', name: 'Ann')],
    );
    final backup = _snap(
      students: [
        _student(omrId: '0001', name: 'Ann Changed'),
        _student(omrId: '0002', name: 'Ben'),
      ],
    );

    final merged = mergeBackupSnapshots(
      phone: phone,
      backup: backup,
      mode: BackupRestoreMode.addMissingOnly,
    );
    expect(merged.students.length, 2);
    expect(
      merged.students.firstWhere((s) => s.omrId == '0001').name,
      'Ann',
    );
    expect(merged.students.any((s) => s.omrId == '0002'), isTrue);
  });

  test('mergePreferBackup overwrites overlaps and keeps phone-only', () {
    final phone = _snap(
      students: [
        _student(omrId: '0001', name: 'Ann'),
        _student(omrId: '0009', name: 'OnlyPhone'),
      ],
    );
    final backup = _snap(
      students: [
        _student(omrId: '0001', name: 'Ann Backup'),
        _student(omrId: '0002', name: 'Ben'),
      ],
    );

    final merged = mergeBackupSnapshots(
      phone: phone,
      backup: backup,
      mode: BackupRestoreMode.mergePreferBackup,
    );
    expect(merged.students.length, 3);
    expect(
      merged.students.firstWhere((s) => s.omrId == '0001').name,
      'Ann Backup',
    );
    expect(merged.students.any((s) => s.omrId == '0009'), isTrue);
  });
}
