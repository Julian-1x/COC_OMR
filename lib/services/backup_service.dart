import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/answer_key_io_service.dart';
import 'package:omr_app/services/backup_compare.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Full offline backup (JSON) — same logical shape as legacy `omr_offline_store.json`.
class BackupService {
  BackupService._();

  static const int exportFormatVersion = 1;

  static Map<String, dynamic> buildPayload() {
    return {
      'exportFormatVersion': exportFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'students': globalStudentDatabase.map((e) => e.toJson()).toList(),
      'sections': globalSections.map((e) => e.toJson()).toList(),
      'subjects': globalSubjects.map((e) => e.toJson()).toList(),
      'scanResults': globalScanResults.map((e) => e.toJson()).toList(),
      'deadlines': globalDeadlines.map((e) => e.toJson()).toList(),
      'exportRecords': globalExportRecords.map((e) => e.toJson()).toList(),
      'answerKeyTemplates':
          globalAnswerKeyTemplates.map((e) => e.toJson()).toList(),
      'customSheetLayouts':
          globalCustomSheetLayouts.map((e) => e.toJson()).toList(),
      'omrCounter': nextOmrIdValue,
      'subjectCounter': nextSubjectCounterValue,
      'sheetCounter': nextSheetCounterValue,
    };
  }

  /// Writes a JSON backup and opens the platform share sheet (save to Files, Drive, etc.).
  static Future<bool> exportAndShare() async {
    final payload = buildPayload();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}${Platform.pathSeparator}omr_backup_$stamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'OMR app backup',
      text: 'Offline backup (students, subjects, scans). Keep this file private.',
    );
    return true;
  }

  /// Pick a `.json` backup. Returns null if cancelled or invalid.
  static Future<Map<String, dynamic>?> pickBackupMap(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
      dialogTitle: 'Select OMR backup (.json)',
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    String? raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      raw = await File(file.path!).readAsString();
    }

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  static BackupCompareReport comparePickedBackup(Map<String, dynamic> decoded) {
    return compareBackupToPhone(
      phone: phoneSnapshotFromGlobals(),
      backup: BackupSnapshotData.fromBackupMap(decoded),
    );
  }

  /// Apply a previously picked backup with the chosen conflict mode.
  static Future<bool> applyBackupMap(
    Map<String, dynamic> decoded, {
    BackupRestoreMode mode = BackupRestoreMode.replaceAll,
  }) {
    return LocalDataStore.instance.restoreFromBackupMap(decoded, mode: mode);
  }

  /// Pick a `.json` backup and replace local data. Caller should confirm with the user first.
  @Deprecated('Use pickBackupMap + compare + applyBackupMap')
  static Future<bool> importFromPick(BuildContext context) async {
    final decoded = await pickBackupMap(context);
    if (decoded == null) return false;
    return applyBackupMap(decoded);
  }
}
