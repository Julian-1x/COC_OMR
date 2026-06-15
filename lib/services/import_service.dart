import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/supabase_service.dart';

/// Progress callback for import operations
typedef ImportProgressCallback = void Function(
    int current, int total, String? currentItem);

class ImportSummary {
  const ImportSummary({
    required this.imported,
    required this.skipped,
    required this.duplicates,
    required this.fileName,
    this.wasCancelled = false,
    this.errors = const [],
    this.updated = 0,
    this.removed = 0,
    this.unchanged = 0,
  });

  const ImportSummary.cancelled()
      : imported = 0,
        skipped = 0,
        duplicates = 0,
        fileName = '',
        wasCancelled = true,
        errors = const [],
        updated = 0,
        removed = 0,
        unchanged = 0;

  final int imported;
  final int skipped;
  final int duplicates;
  final String fileName;
  final bool wasCancelled;
  final List<String> errors;
  final int updated;
  final int removed;
  final int unchanged;

  int get totalRows => imported + skipped + duplicates + updated + unchanged;
  bool get hasChanges =>
      imported > 0 ||
      skipped > 0 ||
      duplicates > 0 ||
      updated > 0 ||
      removed > 0 ||
      unchanged > 0;

  String get feedbackMessage {
    final parts = <String>[
      if (imported > 0) 'added $imported',
      if (updated > 0) 'updated $updated',
      if (unchanged > 0) 'unchanged $unchanged',
      if (skipped > 0) 'skipped $skipped',
      if (duplicates > 0) 'duplicate rows $duplicates',
      if (removed > 0) 'removed $removed',
    ];
    if (parts.isEmpty) {
      return 'No roster changes';
    }
    return parts.join(', ');
  }
}

/// A prepared-but-not-saved import, so the UI can confirm before committing.
class ImportPreview {
  ImportPreview._(this._batch);

  final _PreparedImportBatch _batch;

  ImportSummary get summary => _batch.summary;
  List<Student> get newStudents => _batch.students;
  List<Section> get newSections => _batch.sections;
  List<Student> get studentsToRemove => _batch.studentsToRemove;

  bool get hasNothingToImport =>
      _batch.students.isEmpty && _batch.studentsToRemove.isEmpty;

  ImportPreview replaceRosterPreview() => ImportService._replaceRosterPreview(this);
}

class ImportService {
  static String _buildOmrId(
    String schoolId, {
    required Set<String> reservedOmrIds,
  }) =>
      buildStudentOmrId(
        schoolId,
        reservedOmrIds: reservedOmrIds,
      );

  static Future<ImportSummary> importStudentData({
    ImportProgressCallback? onProgress,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Student Roster (.xlsx or .csv)',
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return const ImportSummary.cancelled();
      }

      final file = result.files.first;
      final extension = file.extension?.toLowerCase();
      final bytes = file.bytes;

      if (bytes == null || extension == null) {
        return ImportSummary(
          imported: 0,
          skipped: 1,
          duplicates: 0,
          fileName: file.name,
        );
      }

      if (extension == 'csv') {
        return await _importCsv(bytes, file.name, onProgress: onProgress);
      }

      if (extension == 'xlsx') {
        return await _importExcel(bytes, file.name, onProgress: onProgress);
      }

      return ImportSummary(
        imported: 0,
        skipped: 1,
        duplicates: 0,
        fileName: file.name,
      );
    } catch (error) {
      debugPrint('Import error: $error');
      rethrow;
    }
  }

  /// Picks a file and prepares the import WITHOUT saving, so the caller can
  /// show a confirmation (new / duplicate / skipped) before committing.
  static Future<ImportPreview?> prepareImportFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Student Roster (.xlsx or .csv)',
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    final extension = file.extension?.toLowerCase();
    final bytes = file.bytes;

    if (bytes == null || extension == null) {
      throw const FormatException('Could not read the selected file.');
    }

    List<List<dynamic>> rows;
    if (extension == 'csv') {
      final csvString = utf8.decode(bytes);
      rows = const CsvToListConverter(shouldParseNumbers: false)
          .convert(csvString);
    } else if (extension == 'xlsx') {
      final excel = Excel.decodeBytes(bytes);
      rows = const <List<dynamic>>[];
      for (final tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet != null && sheet.rows.isNotEmpty) {
          rows = sheet.rows;
          break;
        }
      }
    } else {
      throw const FormatException('Unsupported file type.');
    }

    final batch = _prepareImportRows(rows, fileName: file.name);
    return ImportPreview._(batch);
  }

  static ImportPreview _replaceRosterPreview(ImportPreview preview) {
    return ImportPreview._(
      _prepareImportRows(
        preview._batch.rows,
        fileName: preview._batch.summary.fileName,
        hasHeader: preview._batch.hasHeader,
        replaceRoster: true,
      ),
    );
  }

  /// Commits a previously prepared import to local storage and memory.
  static Future<ImportSummary> commitImport(
    ImportPreview preview, {
    bool replaceRoster = false,
  }) async {
    await LocalDataStore.instance.reloadForCurrentTeacher();
    final effective = replaceRoster ? preview.replaceRosterPreview() : preview;
    await LocalDataStore.instance.saveImportedStudents(
      students: effective._batch.students,
      sections: effective._batch.sections,
    );

    var removed = 0;
    if (replaceRoster && effective.studentsToRemove.isNotEmpty) {
      final summary = await LocalDataStore.instance.removeStudentsCascade(
        effective.studentsToRemove.map((student) => student.omrId).toList(),
      );
      removed = summary.removedStudents;
    }

    final base = effective.summary;
    debugPrint(
      'Import committed (${base.fileName}): ${base.feedbackMessage}',
    );
    return ImportSummary(
      imported: base.imported,
      skipped: base.skipped,
      duplicates: base.duplicates,
      fileName: base.fileName,
      errors: base.errors,
      updated: base.updated,
      removed: removed,
      unchanged: base.unchanged,
    );
  }

  /// Preview import without actually importing (returns row count)
  static Future<int?> previewImport() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select Student Roster (.xlsx or .csv)',
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      final extension = file.extension?.toLowerCase();
      final bytes = file.bytes;

      if (bytes == null) return null;

      if (extension == 'csv') {
        final csvString = utf8.decode(bytes);
        final rows = const CsvToListConverter(shouldParseNumbers: false)
            .convert(csvString);
        return rows.length - 1; // Subtract header
      }

      if (extension == 'xlsx') {
        final excel = Excel.decodeBytes(bytes);
        for (final tableName in excel.tables.keys) {
          final sheet = excel.tables[tableName];
          if (sheet != null) {
            return sheet.rows.length - 1;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Preview error: $e');
      return null;
    }
  }

  static ImportSummary importRows(
    Iterable<List<dynamic>> rows, {
    required String fileName,
    bool hasHeader = true,
    ImportProgressCallback? onProgress,
  }) {
    final batch = _prepareImportRows(
      rows,
      fileName: fileName,
      hasHeader: hasHeader,
      onProgress: onProgress,
    );
    _applyPreparedImportToMemory(batch);
    debugPrint(
      'Import complete (${batch.summary.fileName}): ${batch.summary.feedbackMessage}',
    );
    return batch.summary;
  }

  static _PreparedImportBatch _prepareImportRows(
    Iterable<List<dynamic>> rows, {
    required String fileName,
    bool hasHeader = true,
    bool replaceRoster = false,
    ImportProgressCallback? onProgress,
  }) {
    int imported = 0;
    int updated = 0;
    int unchanged = 0;
    int skipped = 0;
    int duplicates = 0;
    final errors = <String>[];
    final importedStudents = <Student>[];
    final sectionsByName = <String, Section>{};
    final ownerTeacherId = SupabaseService.currentUserId;

    final existingStudentIds = globalStudentDatabase
        .map((student) => _normalizeStudentId(student.schoolId))
        .where((value) => value.isNotEmpty)
        .toSet();
    final assignedOmrIds = globalStudentDatabase
        .map((student) => student.omrId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final importedInBatch = <String>{};
    final fileSchoolIds = <String>{};

    final rowList = rows.toList();
    final totalRows = rowList.length;

    int schoolIdIndex = 0;
    int nameIndex = 1;
    int sectionIndex = 2;
    int firstNameIndex = -1;
    int lastNameIndex = -1;

    int startIndex = hasHeader ? 1 : 0;
    int headerRowIndex = -1;
    List<String> header = const [];

    if (hasHeader && rowList.isNotEmpty) {
      headerRowIndex = _detectHeaderRow(rowList);
      if (headerRowIndex != -1) {
        header = rowList[headerRowIndex]
            .map((cell) => _normalizeHeader(_readCell(cell)))
            .toList();
        startIndex = headerRowIndex + 1;
      }
    }

    if (header.isNotEmpty) {
      int findIndex(List<String> keys) {
        for (final key in keys) {
          final idx = header.indexOf(key);
          if (idx != -1) {
            return idx;
          }
        }
        return -1;
      }

      final idIdx = findIndex(const [
        'student id',
        'studentid',
        'school id',
        'schoolid',
        'id',
        'student number',
        'studentno',
        'student no',
      ]);
      final nameIdx = findIndex(const [
        'name',
        'student name',
        'fullname',
        'full name',
      ]);
      final sectionIdx = findIndex(const [
        'section',
        'section name',
        'class',
        'class section',
        'year & section',
        'year and section',
        'yr & section',
        'yr and section',
        'course',
        'block',
        'group',
      ]);
      firstNameIndex = findIndex(const [
        'first name',
        'firstname',
        'given name',
        'given',
      ]);
      lastNameIndex = findIndex(const [
        'last name',
        'lastname',
        'surname',
        'family name',
      ]);

      if (idIdx != -1) {
        schoolIdIndex = idIdx;
      }
      if (nameIdx != -1) {
        nameIndex = nameIdx;
      }
      if (sectionIdx != -1) {
        sectionIndex = sectionIdx;
      }
    }

    for (int index = startIndex; index < rowList.length; index++) {
      final row = rowList[index];

      // Report progress every 50 rows
      if (onProgress != null && (index - startIndex) % 50 == 0) {
        onProgress(index - startIndex, totalRows - startIndex, null);
      }

      if (row.length < 3 ||
          schoolIdIndex >= row.length ||
          sectionIndex >= row.length ||
          (nameIndex >= row.length &&
              (firstNameIndex == -1 || lastNameIndex == -1))) {
        skipped++;
        if (errors.length < 10) {
          errors.add('Row ${index + 1}: Missing required columns');
        }
        continue;
      }

      final schoolId = _readCell(row[schoolIdIndex]);
      final name = nameIndex < row.length
          ? _readCell(row[nameIndex])
          : '${_readCell(row[firstNameIndex])} ${_readCell(row[lastNameIndex])}'
              .trim();
      final section = _normalizeSectionName(_readCell(row[sectionIndex]));

      if (schoolId.isEmpty || name.isEmpty) {
        skipped++;
        if (errors.length < 10) {
          errors.add('Row ${index + 1}: Empty ID or name');
        }
        continue;
      }

      final resolvedSection = section.isEmpty ? 'UNASSIGNED' : section;

      final studentKey = _normalizeStudentId(schoolId);
      fileSchoolIds.add(studentKey);

      // Match roster rows by Student ID (school ID). OMR IDs are app-assigned
      // and never used as the import identity — they stay with the same student.
      if (importedInBatch.contains(studentKey)) {
        duplicates++;
        continue;
      }

      final existingMatches = globalStudentDatabase
          .where(
            (student) => _normalizeStudentId(student.schoolId) == studentKey,
          )
          .toList();
      final existingStudent =
          existingMatches.isEmpty ? null : existingMatches.first;

      if (existingStudent != null) {
        sectionsByName.putIfAbsent(
          resolvedSection,
          () => Section(name: resolvedSection, ownerTeacherId: ownerTeacherId),
        );

        final sameName = existingStudent.name.trim() == name.trim();
        final sameSection =
            normalizeSectionName(existingStudent.section) == resolvedSection;

        final needsOwnerStamp = ownerTeacherId != null &&
            (existingStudent.ownerTeacherId == null ||
                existingStudent.ownerTeacherId!.isEmpty);

        if (replaceRoster || !sameName || !sameSection || needsOwnerStamp) {
          importedStudents.add(
            existingStudent.copyWith(
              schoolId: schoolId,
              name: name,
              section: resolvedSection,
              ownerTeacherId: ownerTeacherId ?? existingStudent.ownerTeacherId,
              syncStatus: SyncStatus.pending,
              updatedAt: DateTime.now(),
            ),
          );
          updated++;
        } else {
          unchanged++;
        }
        importedInBatch.add(studentKey);
        continue;
      }

      final newStudent = Student(
        schoolId: schoolId,
        name: name,
        section: resolvedSection,
        omrId: _buildOmrId(
          schoolId,
          reservedOmrIds: assignedOmrIds,
        ),
        ownerTeacherId: ownerTeacherId,
      );

      importedStudents.add(newStudent);
      sectionsByName.putIfAbsent(
        resolvedSection,
        () => Section(name: resolvedSection, ownerTeacherId: ownerTeacherId),
      );
      existingStudentIds.add(studentKey);
      assignedOmrIds.add(newStudent.omrId);
      importedInBatch.add(studentKey);
      imported++;
    }

    // Final progress update
    onProgress?.call(
        totalRows - startIndex, totalRows - startIndex, 'Complete');

    final studentsToRemove = replaceRoster
        ? globalStudentDatabase
            .where(
              (student) =>
                  !fileSchoolIds.contains(_normalizeStudentId(student.schoolId)),
            )
            .toList()
        : const <Student>[];

    final summary = ImportSummary(
      imported: imported,
      skipped: skipped,
      duplicates: duplicates,
      fileName: fileName,
      errors: errors,
      updated: updated,
      removed: studentsToRemove.length,
      unchanged: unchanged,
    );

    return _PreparedImportBatch(
      summary: summary,
      students: importedStudents,
      sections: sectionsByName.values.toList(),
      studentsToRemove: studentsToRemove,
      rows: rowList,
      hasHeader: hasHeader,
    );
  }

  static Future<ImportSummary> _importCsv(
    Uint8List bytes,
    String fileName, {
    ImportProgressCallback? onProgress,
  }) async {
    final csvString = utf8.decode(bytes);
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(csvString);

    if (rows.isEmpty) {
      return ImportSummary(
        imported: 0,
        skipped: 0,
        duplicates: 0,
        fileName: fileName,
      );
    }

    final batch = _prepareImportRows(
      rows,
      fileName: fileName,
      onProgress: onProgress,
    );
    await LocalDataStore.instance.saveImportedStudents(
      students: batch.students,
      sections: batch.sections,
    );
    debugPrint(
      'Import complete (${batch.summary.fileName}): ${batch.summary.feedbackMessage}',
    );
    return batch.summary;
  }

  static Future<ImportSummary> _importExcel(
    Uint8List bytes,
    String fileName, {
    ImportProgressCallback? onProgress,
  }) async {
    try {
      final excel = Excel.decodeBytes(bytes);

      for (final tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet == null) {
          continue;
        }

        final batch = _prepareImportRows(
          sheet.rows,
          fileName: fileName,
          onProgress: onProgress,
        );
        await LocalDataStore.instance.saveImportedStudents(
          students: batch.students,
          sections: batch.sections,
        );
        debugPrint(
          'Import complete (${batch.summary.fileName}): ${batch.summary.feedbackMessage}',
        );
        return batch.summary;
      }

      return ImportSummary(
        imported: 0,
        skipped: 0,
        duplicates: 0,
        fileName: fileName,
      );
    } catch (error) {
      debugPrint('Excel parsing error: $error');
      rethrow;
    }
  }

  static String _readCell(dynamic value) {
    if (value is Data) {
      value = value.value;
    }
    return value?.toString().trim().replaceAll('\n', ' ') ?? '';
  }

  static String _normalizeStudentId(String value) => value.trim().toUpperCase();

  static String _normalizeSectionName(String value) => normalizeSectionName(value);

  static String _normalizeHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');

  static int _detectHeaderRow(List<List<dynamic>> rows) {
    final maxRows = rows.length < 5 ? rows.length : 5;
    int bestIndex = -1;
    int bestScore = 0;

    for (var i = 0; i < maxRows; i++) {
      final normalized =
          rows[i].map((cell) => _normalizeHeader(_readCell(cell))).toList();
      int score = 0;
      if (normalized.any((cell) => cell.contains('id'))) {
        score++;
      }
      if (normalized.any((cell) => cell.contains('name'))) {
        score++;
      }
      if (normalized
          .any((cell) => cell.contains('section') || cell.contains('class'))) {
        score++;
      }

      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestScore >= 2 ? bestIndex : -1;
  }

  static void _applyPreparedImportToMemory(_PreparedImportBatch batch) {
    for (final section in batch.sections) {
      final alreadyExists = globalSections.any(
        (entry) => _normalizeSectionName(entry.name) == section.name,
      );
      if (!alreadyExists) {
        globalSections.add(section);
      }
    }
    for (final student in batch.students) {
      addStudent(student);
    }
    if (batch.students.isNotEmpty) {
      rebuildStudentIndex();
    }
  }

  static Future<void> exportResults(String subjectName) async {
    debugPrint('Export results for $subjectName');
  }
}

class _PreparedImportBatch {
  const _PreparedImportBatch({
    required this.summary,
    required this.students,
    required this.sections,
    this.studentsToRemove = const <Student>[],
    required this.rows,
    required this.hasHeader,
  });

  final ImportSummary summary;
  final List<Student> students;
  final List<Section> sections;
  final List<Student> studentsToRemove;
  final List<List<dynamic>> rows;
  final bool hasHeader;
}
