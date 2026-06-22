import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/utils/academic_term.dart';
import 'package:omr_app/utils/roster_columns.dart';
import 'package:omr_app/utils/roster_spreadsheet.dart';
import 'package:omr_app/utils/student_identity.dart';

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

Section _importSection(String name, {String? ownerTeacherId}) {
  return Section(
    name: name,
    ownerTeacherId: ownerTeacherId,
    schoolYear: AcademicTerm.schoolYearForDate(),
    termLabel: AcademicTerm.defaultTermLabel(),
  );
}

class ImportService {
  static String _extensionFromName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot >= fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  static Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes;
    }

    if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
      return File(file.path!).readAsBytes();
    }

    return null;
  }

  static Future<List<List<dynamic>>> _rowsFromPickedFile(PlatformFile file) async {
    final bytes = await _readPickedFileBytes(file);
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException(
        'Could not read the selected file. Try saving as .xlsx or .csv and pick it again.',
      );
    }

    try {
      return RosterSpreadsheetDecoder.decode(
        bytes: bytes,
        extension: file.extension?.toLowerCase() ?? _extensionFromName(file.name),
        fileName: file.name,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      debugPrint('Roster file decode failed: $error');
      throw const FormatException(
        'Could not read that roster file. Save as .xlsx or .csv with Student ID, Name, and Section.',
      );
    }
  }

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
      await LocalDataStore.instance.reloadForCurrentTeacher();
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
      final bytes = await _readPickedFileBytes(file);

      if (bytes == null || bytes.isEmpty) {
        return ImportSummary(
          imported: 0,
          skipped: 1,
          duplicates: 0,
          fileName: file.name,
          errors: const [
            'Could not read the selected file. Try saving as .xlsx or .csv and pick it again.',
          ],
        );
      }

      return await _importFromBytes(
        bytes,
        fileName: file.name,
        extension: file.extension?.toLowerCase() ?? _extensionFromName(file.name),
        onProgress: onProgress,
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

    try {
      final rows = await _rowsFromPickedFile(file);
      final batch = _prepareImportRows(rows, fileName: file.name);
      return ImportPreview._(batch);
    } on FormatException catch (error) {
      throw FormatException(error.message);
    }
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

  static ImportPreview refreshPreview(ImportPreview preview) {
    return ImportPreview._(
      _prepareImportRows(
        preview._batch.rows,
        fileName: preview._batch.summary.fileName,
        hasHeader: preview._batch.hasHeader,
      ),
    );
  }

  /// Commits a previously prepared import to local storage and memory.
  static Future<ImportSummary> commitImport(
    ImportPreview preview, {
    bool replaceRoster = false,
  }) async {
    await LocalDataStore.instance.reloadForCurrentTeacher();
    final effective = replaceRoster
        ? preview.replaceRosterPreview()
        : refreshPreview(preview);
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
      final bytes = await _readPickedFileBytes(file);

      if (bytes == null || bytes.isEmpty) return null;

      final rows = RosterSpreadsheetDecoder.decode(
        bytes: bytes,
        extension: file.extension?.toLowerCase() ?? _extensionFromName(file.name),
        fileName: file.name,
      );
      final headerIndex = RosterColumnMap.detectHeaderRow(rows, _readCell);
      final dataRows = headerIndex == -1 ? rows.length : rows.length - headerIndex - 1;
      return dataRows > 0 ? dataRows : rows.length;
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
        .map((student) => normalizeSchoolId(student.schoolId))
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
    RosterColumnMap? columnMap;

    if (hasHeader && rowList.isNotEmpty) {
      headerRowIndex = RosterColumnMap.detectHeaderRow(rowList, _readCell);
      if (headerRowIndex != -1) {
        header = rowList[headerRowIndex]
            .map((cell) => RosterColumnMap.normalizeHeader(_readCell(cell)))
            .toList();
        startIndex = headerRowIndex + 1;
        columnMap = RosterColumnMap.fromHeader(header);
      }
    }

    columnMap ??= RosterColumnMap.inferFromRows(rowList, _readCell, startIndex: startIndex);

    if (columnMap != null) {
      schoolIdIndex = columnMap.schoolIdIndex;
      nameIndex = columnMap.nameIndex;
      sectionIndex = columnMap.sectionIndex;
      firstNameIndex = columnMap.firstNameIndex;
      lastNameIndex = columnMap.lastNameIndex;
    }

    for (int index = startIndex; index < rowList.length; index++) {
      final row = rowList[index];

      // Report progress every 50 rows
      if (onProgress != null && (index - startIndex) % 50 == 0) {
        onProgress(index - startIndex, totalRows - startIndex, null);
      }

      if (row.length < 2 ||
          schoolIdIndex >= row.length ||
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
      final section = sectionIndex < row.length
          ? _normalizeSectionName(_readCell(row[sectionIndex]))
          : '';

      if (schoolId.isEmpty || name.isEmpty) {
        skipped++;
        if (errors.length < 10) {
          errors.add('Row ${index + 1}: Empty ID or name');
        }
        continue;
      }

      final resolvedSection = section.isEmpty ? 'UNASSIGNED' : section;

      final studentKey = normalizeSchoolId(schoolId);
      fileSchoolIds.add(studentKey);

      // Match roster rows by Student ID (school ID). OMR IDs are app-assigned
      // and never used as the import identity — they stay with the same student.
      if (importedInBatch.contains(studentKey)) {
        duplicates++;
        continue;
      }

      final existingMatches = globalStudentDatabase
          .where(
            (student) => normalizeSchoolId(student.schoolId) == studentKey,
          )
          .toList();
      final existingStudent =
          existingMatches.isEmpty ? null : existingMatches.first;

      if (existingStudent != null) {
        sectionsByName.putIfAbsent(
          resolvedSection,
          () => _importSection(resolvedSection, ownerTeacherId: ownerTeacherId),
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
        () => _importSection(resolvedSection, ownerTeacherId: ownerTeacherId),
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
                  !fileSchoolIds.contains(normalizeSchoolId(student.schoolId)),
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

  static Future<ImportSummary> _importFromBytes(
    Uint8List bytes, {
    required String fileName,
    required String extension,
    ImportProgressCallback? onProgress,
  }) async {
    try {
      final rows = RosterSpreadsheetDecoder.decode(
        bytes: bytes,
        extension: extension,
        fileName: fileName,
      );

      if (rows.isEmpty) {
        return ImportSummary(
          imported: 0,
          skipped: 0,
          duplicates: 0,
          fileName: fileName,
          errors: const ['The file has no student rows.'],
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
    } on FormatException {
      rethrow;
    } catch (error) {
      debugPrint('Roster import failed: $error');
      throw const FormatException(
        'Could not read that roster file. Save as .xlsx or .csv with Student ID, Name, and Section.',
      );
    }
  }

  static String _readCell(dynamic value) {
    if (value is Data) {
      value = value.value;
    }
    return value?.toString().trim().replaceAll('\n', ' ') ?? '';
  }

  static String _normalizeSectionName(String value) => normalizeSectionName(value);

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
