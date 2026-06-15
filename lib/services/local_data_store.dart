import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/answer_key_io_service.dart';
import 'package:omr_app/services/cloud_snapshot.dart';
import 'package:omr_app/services/sqlite_init.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocalDataStore {
  LocalDataStore._();

  static final LocalDataStore instance = LocalDataStore._();

  static const String _databaseName = 'omr_app.db';
  static const int _databaseVersion = 4;
  static const String _legacyFileName = 'omr_offline_store.json';

  Timer? _saveDebounce;
  Future<void> _pendingSave = Future<void>.value();
  Database? _database;
  bool _loaded = false;

  Future<void> loadIntoMemory() async {
    if (_loaded) {
      return;
    }

    if (kIsWeb) {
      _loaded = true;
      rebuildStudentIndex();
      return;
    }

    try {
      final database = await _openDatabase();
      await _migrateLegacyJsonIfNeeded(database);
      final snapshot = await _readSnapshotFromDatabase(database);
      _applySnapshotToMemory(snapshot);
    } catch (error) {
      debugPrint('Local data load failed: $error');
    } finally {
      _loaded = true;
    }
  }

  Future<void> reloadForCurrentTeacher() async {
    await _reloadMemoryFromDatabase();
  }

  Future<void> clearMemoryOnAuthReset() async {
    _applySnapshotToMemory(
      _AppSnapshot(
        students: const <Student>[],
        sections: const <Section>[],
        subjects: const <Subject>[],
        scanResults: const <ScanResult>[],
        deadlines: const <Deadline>[],
        exportRecords: const <ExportRecord>[],
        answerKeyTemplates: List<AnswerKeyTemplate>.from(
          globalAnswerKeyTemplates,
        ),
        omrCounter: nextOmrIdValue,
        subjectCounter: nextSubjectCounterValue,
        sheetCounter: nextSheetCounterValue,
      ),
    );
  }

  Future<void> saveNow() {
    if (kIsWeb) {
      return Future<void>.value();
    }

    _pendingSave = _pendingSave.then<void>((_) async {
      try {
        await _saveCurrentSnapshot();
      } catch (error) {
        debugPrint('Local data save failed: $error');
      }
    });
    return _pendingSave;
  }

  void scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(saveNow());
    });
  }

  Future<bool> restoreFromBackupMap(Map<String, dynamic> decoded) async {
    try {
      final snapshot = _restampSnapshotOwner(_snapshotFromBackupMap(decoded));

      if (kIsWeb) {
        _applySnapshotToMemory(_snapshotForCurrentTeacher(snapshot));
        _loaded = true;
        return true;
      }

      final database = await _openDatabase();
      final allLocal = await _readSnapshotFromDatabase(
        database,
        scopeToCurrentTeacher: false,
      );
      final otherOwners = _snapshotForOtherTeachers(allLocal);
      final combined = _combineSnapshots(otherOwners, snapshot);
      final withCounters = _AppSnapshot(
        students: combined.students,
        sections: combined.sections,
        subjects: combined.subjects,
        scanResults: combined.scanResults,
        deadlines: combined.deadlines,
        exportRecords: combined.exportRecords,
        answerKeyTemplates: combined.answerKeyTemplates,
        omrCounter: _maxCounter(allLocal.omrCounter, snapshot.omrCounter),
        subjectCounter:
            _maxCounter(allLocal.subjectCounter, snapshot.subjectCounter),
        sheetCounter: _maxCounter(allLocal.sheetCounter, snapshot.sheetCounter),
      );

      await database.transaction((txn) async {
        await _replaceDatabaseContents(txn, withCounters);
      });

      _applySnapshotToMemory(_snapshotForCurrentTeacher(withCounters));
      _loaded = true;
      return true;
    } catch (error) {
      debugPrint('Backup restore failed: $error');
      return false;
    }
  }

  /// Persists OMR/subject/sheet counters after in-memory ID generation.
  Future<void> persistCountersNow() async {
    if (kIsWeb) {
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await _persistCounters(database);
    });
  }

  Future<void> saveAcceptedScan({
    required Student updatedStudent,
    required ScanResult result,
  }) async {
    if (kIsWeb) {
      _replaceStudentInMemory(updatedStudent);
      addScanResult(result);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        await txn.insert(
          'students',
          _studentRow(updatedStudent),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert('scan_results', _scanResultRow(result));
      });
    });

    _replaceStudentInMemory(updatedStudent);
    addScanResult(result);
  }

  Future<void> replaceAcceptedScan({
    required Student updatedStudent,
    required ScanResult previousResult,
    required ScanResult replacementResult,
  }) async {
    if (kIsWeb) {
      _replaceStudentInMemory(updatedStudent);
      globalScanResults.removeWhere(
        (entry) => _matchesScanIdentity(entry, previousResult),
      );
      globalScanResults.add(replacementResult);
      rebuildStudentIndex();
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        await txn.insert(
          'students',
          _studentRow(updatedStudent),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _deleteStoredScanResult(txn, previousResult);
        await txn.insert('scan_results', _scanResultRow(replacementResult));
      });
    });

    _replaceStudentInMemory(updatedStudent);
    globalScanResults.removeWhere(
      (entry) => _matchesScanIdentity(entry, previousResult),
    );
    globalScanResults.add(replacementResult);
    rebuildStudentIndex();
  }

  Future<void> upsertSection(Section section) async {
    if (kIsWeb) {
      _upsertSectionInMemory(section);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.insert(
        'sections',
        _sectionRow(section),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _upsertSectionInMemory(section);
  }

  String? _resolveStoredSectionName(String sectionName) {
    final target = normalizeSectionName(sectionName);
    for (final section in globalSections) {
      if (normalizeSectionName(section.name) == target) {
        return section.name;
      }
    }
    for (final student in globalStudentDatabase) {
      if (normalizeSectionName(student.section) == target) {
        return student.section;
      }
    }
    return null;
  }

  Section? _sectionByName(String sectionName) {
    final stored = _resolveStoredSectionName(sectionName);
    if (stored == null) {
      return null;
    }
    for (final section in globalSections) {
      if (normalizeSectionName(section.name) == normalizeSectionName(stored)) {
        return section;
      }
    }
    return null;
  }

  Future<void> _queueSectionCloudDeletion(String sectionName) async {
    final section = _sectionByName(sectionName);
    await _queueCloudDeletion(
      entityTable: 'sections',
      cloudId: section?.cloudId,
      ownerTeacherId: section?.ownerTeacherId,
    );
  }

  void _removeSectionFromMemory(String sectionName) {
    final target = normalizeSectionName(sectionName);
    globalSections.removeWhere(
      (section) => normalizeSectionName(section.name) == target,
    );
  }

  List<Student> _studentsInSection(String sectionName) {
    final target = normalizeSectionName(sectionName);
    return globalStudentDatabase
        .where((student) => normalizeSectionName(student.section) == target)
        .toList();
  }

  Subject _subjectWithUpdatedSections(
    Subject subject,
    String Function(String sectionName) transform,
  ) {
    final sectionNames = subject.sectionNames;
    if (sectionNames == null || sectionNames.isEmpty) {
      return subject;
    }

    final updated = <String>[];
    final seen = <String>{};
    for (final section in sectionNames) {
      final next = transform(section);
      final key = normalizeSectionName(next);
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      updated.add(next);
    }

    return subject.copyWith(
      sectionNames: updated,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
  }

  Future<SectionRenameSummary> renameSection({
    required String oldName,
    required String newName,
  }) async {
    final oldStored = _resolveStoredSectionName(oldName);
    final newCanonical = normalizeSectionName(newName);
    if (newCanonical.isEmpty) {
      throw ArgumentError('Section name cannot be empty.');
    }
    if (oldStored == null) {
      throw StateError('Section "$oldName" was not found.');
    }
    if (normalizeSectionName(oldStored) == newCanonical) {
      return const SectionRenameSummary(
        updatedStudents: 0,
        updatedSubjects: 0,
        updatedDeadlines: 0,
      );
    }
    if (_resolveStoredSectionName(newCanonical) != null) {
      throw StateError('Section "$newCanonical" already exists.');
    }

    final students = _studentsInSection(oldStored);
    final subjects = globalSubjects
        .where((subject) {
          final names = subject.sectionNames ?? const <String>[];
          return names.any(
            (name) =>
                normalizeSectionName(name) == normalizeSectionName(oldStored),
          );
        })
        .map(
          (subject) => _subjectWithUpdatedSections(
            subject,
            (name) =>
                normalizeSectionName(name) == normalizeSectionName(oldStored)
                    ? newCanonical
                    : name,
          ),
        )
        .toList();
    final deadlines = globalDeadlines
        .where(
          (deadline) =>
              normalizeSectionName(deadline.sectionName ?? '') ==
              normalizeSectionName(oldStored),
        )
        .toList();

    if (kIsWeb) {
      for (final student in students) {
        _replaceStudentInMemory(
          student.copyWith(
            section: newCanonical,
            syncStatus: SyncStatus.pending,
            updatedAt: DateTime.now(),
          ),
        );
      }
      for (final subject in subjects) {
        _upsertSubjectInMemory(subject);
      }
      for (final deadline in deadlines) {
        final index =
            globalDeadlines.indexWhere((entry) => entry.id == deadline.id);
        if (index != -1) {
          globalDeadlines[index] = deadline.copyWith(
            sectionName: newCanonical,
            syncStatus: SyncStatus.pending,
            updatedAt: DateTime.now(),
          );
        }
      }
      globalSections.removeWhere(
        (section) =>
            normalizeSectionName(section.name) ==
            normalizeSectionName(oldStored),
      );
      _upsertSectionInMemory(
        Section(
          name: newCanonical,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime.now(),
        ),
      );
      rebuildStudentIndex();
      return SectionRenameSummary(
        updatedStudents: students.length,
        updatedSubjects: subjects.length,
        updatedDeadlines: deadlines.length,
      );
    }

    await _queueSectionCloudDeletion(oldStored);

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final student in students) {
          await txn.update(
            'students',
            <String, Object?>{
              'section_name': newCanonical,
              'sync_status': SyncStatus.pending,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'omr_id = ?',
            whereArgs: <Object?>[student.omrId],
          );
        }
        for (final subject in subjects) {
          await txn.insert(
            'subjects',
            _subjectRow(subject),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final deadline in deadlines) {
          await txn.update(
            'deadlines',
            <String, Object?>{
              'section_name': newCanonical,
              'sync_status': SyncStatus.pending,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: <Object?>[deadline.id],
          );
        }
        await txn.delete(
          'sections',
          where: 'name = ?',
          whereArgs: <Object?>[oldStored],
        );
        await txn.insert(
          'sections',
          _sectionRow(
            Section(
              name: newCanonical,
              syncStatus: SyncStatus.pending,
              updatedAt: DateTime.now(),
            ),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    });

    await _reloadMemoryFromDatabase();
    return SectionRenameSummary(
      updatedStudents: students.length,
      updatedSubjects: subjects.length,
      updatedDeadlines: deadlines.length,
    );
  }

  Future<SectionDeletionSummary> deleteEmptySection(String sectionName) async {
    final stored = _resolveStoredSectionName(sectionName);
    if (stored == null) {
      throw StateError('Section "$sectionName" was not found.');
    }
    if (_studentsInSection(stored).isNotEmpty) {
      throw StateError('Cannot delete a section that still has students.');
    }

    if (kIsWeb) {
      globalSections.removeWhere(
        (section) =>
            normalizeSectionName(section.name) == normalizeSectionName(stored),
      );
      return const SectionDeletionSummary(
        removedStudents: 0,
        removedScans: 0,
        removedDeadlines: 0,
        removedSection: true,
      );
    }

    await _queueSectionCloudDeletion(stored);

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.delete(
        'sections',
        where: 'name = ?',
        whereArgs: <Object?>[stored],
      );
    });

    _removeSectionFromMemory(stored);

    return const SectionDeletionSummary(
      removedStudents: 0,
      removedScans: 0,
      removedDeadlines: 0,
      removedSection: true,
    );
  }

  Future<SectionDeletionSummary> deleteSectionCascade(String sectionName) async {
    final stored = _resolveStoredSectionName(sectionName);
    if (stored == null) {
      throw StateError('Section "$sectionName" was not found.');
    }

    final students = _studentsInSection(stored);
    final omrIds = students.map((student) => student.omrId).toList();
    final removal = await removeStudentsCascade(omrIds);

    final subjects = globalSubjects
        .where((subject) {
          final names = subject.sectionNames ?? const <String>[];
          return names.any(
            (name) =>
                normalizeSectionName(name) == normalizeSectionName(stored),
          );
        })
        .map(
          (subject) => _subjectWithUpdatedSections(
            subject,
            (name) =>
                normalizeSectionName(name) == normalizeSectionName(stored)
                    ? ''
                    : name,
          ),
        )
        .toList();
    final deadlines = globalDeadlines
        .where(
          (deadline) =>
              normalizeSectionName(deadline.sectionName ?? '') ==
              normalizeSectionName(stored),
        )
        .toList();

    if (kIsWeb) {
      for (final subject in subjects) {
        _upsertSubjectInMemory(subject);
      }
      globalDeadlines.removeWhere(
        (deadline) =>
            normalizeSectionName(deadline.sectionName ?? '') ==
            normalizeSectionName(stored),
      );
      globalSections.removeWhere(
        (section) =>
            normalizeSectionName(section.name) == normalizeSectionName(stored),
      );
      return SectionDeletionSummary(
        removedStudents: removal.removedStudents,
        removedScans: removal.removedScans,
        removedDeadlines: deadlines.length,
        removedSection: true,
      );
    }

    await _queueSectionCloudDeletion(stored);

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final subject in subjects) {
          await txn.insert(
            'subjects',
            _subjectRow(subject),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final deadline in deadlines) {
          await txn.delete(
            'deadlines',
            where: 'id = ?',
            whereArgs: <Object?>[deadline.id],
          );
        }
        await txn.delete(
          'sections',
          where: 'name = ?',
          whereArgs: <Object?>[stored],
        );
      });
    });

    for (final subject in subjects) {
      _upsertSubjectInMemory(subject);
    }
    globalDeadlines.removeWhere(
      (deadline) =>
          normalizeSectionName(deadline.sectionName ?? '') ==
          normalizeSectionName(stored),
    );
    _removeSectionFromMemory(stored);

    return SectionDeletionSummary(
      removedStudents: removal.removedStudents,
      removedScans: removal.removedScans,
      removedDeadlines: deadlines.length,
      removedSection: true,
    );
  }

  Future<SectionMergeSummary> mergeSections({
    required String sourceName,
    required String targetName,
  }) async {
    final sourceStored = _resolveStoredSectionName(sourceName);
    final targetCanonical = normalizeSectionName(targetName);

    if (targetCanonical.isEmpty) {
      throw ArgumentError('Target section name cannot be empty.');
    }
    if (sourceStored == null) {
      throw StateError('Source section "$sourceName" was not found.');
    }
    if (normalizeSectionName(sourceStored) == targetCanonical) {
      throw StateError('Source and target section must be different.');
    }

    if (_resolveStoredSectionName(targetCanonical) == null) {
      await upsertSection(Section(name: targetCanonical));
    }

    final students = _studentsInSection(sourceStored);
    final subjects = globalSubjects
        .where((subject) {
          final names = subject.sectionNames ?? const <String>[];
          return names.any(
            (name) =>
                normalizeSectionName(name) ==
                    normalizeSectionName(sourceStored) ||
                normalizeSectionName(name) == targetCanonical,
          );
        })
        .map(
          (subject) => _subjectWithUpdatedSections(
            subject,
            (name) {
              final normalized = normalizeSectionName(name);
              if (normalized == normalizeSectionName(sourceStored)) {
                return targetCanonical;
              }
              return name;
            },
          ),
        )
        .toList();
    final deadlines = globalDeadlines
        .where(
          (deadline) =>
              normalizeSectionName(deadline.sectionName ?? '') ==
              normalizeSectionName(sourceStored),
        )
        .toList();

    if (kIsWeb) {
      for (final student in students) {
        _replaceStudentInMemory(
          student.copyWith(
            section: targetCanonical,
            syncStatus: SyncStatus.pending,
            updatedAt: DateTime.now(),
          ),
        );
      }
      for (final subject in subjects) {
        _upsertSubjectInMemory(subject);
      }
      for (final deadline in deadlines) {
        final index =
            globalDeadlines.indexWhere((entry) => entry.id == deadline.id);
        if (index != -1) {
          globalDeadlines[index] = deadline.copyWith(
            sectionName: targetCanonical,
            syncStatus: SyncStatus.pending,
            updatedAt: DateTime.now(),
          );
        }
      }
      globalSections.removeWhere(
        (section) =>
            normalizeSectionName(section.name) ==
            normalizeSectionName(sourceStored),
      );
      rebuildStudentIndex();
      return SectionMergeSummary(
        movedStudents: students.length,
        updatedSubjects: subjects.length,
        updatedDeadlines: deadlines.length,
      );
    }

    await _queueSectionCloudDeletion(sourceStored);

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final student in students) {
          await txn.update(
            'students',
            <String, Object?>{
              'section_name': targetCanonical,
              'sync_status': SyncStatus.pending,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'omr_id = ?',
            whereArgs: <Object?>[student.omrId],
          );
        }
        for (final subject in subjects) {
          await txn.insert(
            'subjects',
            _subjectRow(subject),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final deadline in deadlines) {
          await txn.update(
            'deadlines',
            <String, Object?>{
              'section_name': targetCanonical,
              'sync_status': SyncStatus.pending,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: <Object?>[deadline.id],
          );
        }
        await txn.delete(
          'sections',
          where: 'name = ?',
          whereArgs: <Object?>[sourceStored],
        );
      });
    });

    await _reloadMemoryFromDatabase();
    return SectionMergeSummary(
      movedStudents: students.length,
      updatedSubjects: subjects.length,
      updatedDeadlines: deadlines.length,
    );
  }

  Future<StudentRemovalSummary> removeStudentCascade(String omrId) async {
    final summary = await removeStudentsCascade(<String>[omrId]);
    return StudentRemovalSummary(removedScans: summary.removedScans);
  }

  Future<SectionDeletionSummary> removeStudentsCascade(
    List<String> omrIds,
  ) async {
    if (omrIds.isEmpty) {
      return const SectionDeletionSummary(
        removedStudents: 0,
        removedScans: 0,
        removedDeadlines: 0,
        removedSection: false,
      );
    }

    final uniqueIds = omrIds.toSet().toList();
    final removedScans = globalScanResults
        .where((result) => uniqueIds.contains(result.studentOmrId))
        .toList();

    if (kIsWeb) {
      globalStudentDatabase
          .removeWhere((student) => uniqueIds.contains(student.omrId));
      globalScanResults.removeWhere(
        (result) => uniqueIds.contains(result.studentOmrId),
      );
      rebuildStudentIndex();
      return SectionDeletionSummary(
        removedStudents: uniqueIds.length,
        removedScans: removedScans.length,
        removedDeadlines: 0,
        removedSection: false,
      );
    }

    for (final result in removedScans) {
      await _queueCloudDeletion(
        entityTable: 'scan_results',
        cloudId: result.cloudId,
        ownerTeacherId: result.ownerTeacherId,
      );
    }
    for (final omrId in uniqueIds) {
      final student = globalStudentIndex[omrId];
      await _queueCloudDeletion(
        entityTable: 'students',
        cloudId: student?.cloudId,
        ownerTeacherId: student?.ownerTeacherId,
      );
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final omrId in uniqueIds) {
          await txn.delete(
            'scan_results',
            where: 'student_omr_id = ?',
            whereArgs: <Object?>[omrId],
          );
          await txn.delete(
            'students',
            where: 'omr_id = ?',
            whereArgs: <Object?>[omrId],
          );
        }
      });
    });

    globalStudentDatabase
        .removeWhere((student) => uniqueIds.contains(student.omrId));
    globalScanResults.removeWhere(
      (result) => uniqueIds.contains(result.studentOmrId),
    );
    rebuildStudentIndex();

    return SectionDeletionSummary(
      removedStudents: uniqueIds.length,
      removedScans: removedScans.length,
      removedDeadlines: 0,
      removedSection: false,
    );
  }

  Future<void> saveImportedStudents({
    required List<Student> students,
    required List<Section> sections,
  }) async {
    if (students.isEmpty && sections.isEmpty) {
      return;
    }

    if (kIsWeb) {
      for (final section in sections) {
        _upsertSectionInMemory(section);
      }
      for (final student in students) {
        _replaceStudentInMemory(student);
      }
      rebuildStudentIndex();
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final section in sections) {
          await txn.insert(
            'sections',
            _sectionRow(section),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final student in students) {
          await txn.insert(
            'students',
            _studentRow(student),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await _persistCounters(txn);
      });
    });

    for (final section in sections) {
      _upsertSectionInMemory(section);
    }
    for (final student in students) {
      _replaceStudentInMemory(student);
    }
    rebuildStudentIndex();
  }

  Future<void> upsertSubject(Subject subject) async {
    if (kIsWeb) {
      for (final sectionName in subject.sectionNames ?? const <String>[]) {
        _upsertSectionInMemory(Section(name: sectionName));
      }
      _upsertSubjectInMemory(subject);
      _renameSubjectResultsInMemory(subject.id, subject.name);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final sectionName in subject.sectionNames ?? const <String>[]) {
          await txn.insert(
            'sections',
            _sectionRow(Section(name: sectionName)),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await txn.insert(
          'subjects',
          _subjectRow(subject),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.update(
          'scan_results',
          <String, Object?>{'subject_name': subject.name},
          where: 'subject_id = ?',
          whereArgs: <Object?>[subject.id],
        );
        await _persistCounters(txn);
      });
    });

    for (final sectionName in subject.sectionNames ?? const <String>[]) {
      _upsertSectionInMemory(Section(name: sectionName));
    }
    _upsertSubjectInMemory(subject);
    _renameSubjectResultsInMemory(subject.id, subject.name);
  }

  Future<SubjectDeletionSummary> deleteSubjectCascade(Subject subject) async {
    if (kIsWeb) {
      return deleteSubjectAndRelatedData(subject);
    }

    final removedScans = globalScanResults
        .where((result) => result.subjectId == subject.id)
        .toList();
    final removedDeadlines = globalDeadlines
        .where((deadline) => deadline.subjectId == subject.id)
        .toList();
    final removedSubjects =
        globalSubjects.where((entry) => entry.id == subject.id).length;
    final affectedStudents =
        removedScans.map((result) => result.studentOmrId).toSet();

    await _queueCloudDeletion(
      entityTable: 'subjects',
      cloudId: subject.cloudId,
      ownerTeacherId: subject.ownerTeacherId,
    );
    for (final result in removedScans) {
      await _queueCloudDeletion(
        entityTable: 'scan_results',
        cloudId: result.cloudId,
        ownerTeacherId: result.ownerTeacherId,
      );
    }
    for (final deadline in removedDeadlines) {
      await _queueCloudDeletion(
        entityTable: 'deadlines',
        cloudId: deadline.cloudId,
        ownerTeacherId: deadline.ownerTeacherId,
      );
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        await txn.delete(
          'scan_results',
          where: 'subject_id = ?',
          whereArgs: <Object?>[subject.id],
        );
        await txn.delete(
          'deadlines',
          where: 'subject_id = ?',
          whereArgs: <Object?>[subject.id],
        );
        await txn.delete(
          'subjects',
          where: 'id = ?',
          whereArgs: <Object?>[subject.id],
        );

        for (final omrId in affectedStudents) {
          final latestRows = await txn.query(
            'scan_results',
            columns: const <String>[
              'detected_answers_json',
              'score',
              'confidence',
              'scan_time',
            ],
            where: 'student_omr_id = ?',
            whereArgs: <Object?>[omrId],
            orderBy: 'scan_time DESC, id DESC',
            limit: 1,
          );
          final latestRow = latestRows.isEmpty ? null : latestRows.first;
          await txn.update(
            'students',
            <String, Object?>{
              'answers_json': latestRow?['detected_answers_json'],
              'score': latestRow?['score'],
              'confidence': latestRow?['confidence'],
              'scan_date': latestRow?['scan_time'],
            },
            where: 'omr_id = ?',
            whereArgs: <Object?>[omrId],
          );
        }
      });
    });

    await _reloadMemoryFromDatabase();

    return SubjectDeletionSummary(
      removedSubjects: removedSubjects,
      removedScans: removedScans.length,
      removedDeadlines: removedDeadlines.length,
      affectedStudents: affectedStudents.length,
    );
  }

  Future<void> upsertAnswerKeyTemplate(AnswerKeyTemplate template) async {
    if (kIsWeb) {
      _upsertTemplateInMemory(template);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.insert(
        'answer_key_templates',
        _answerKeyTemplateRow(template),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _upsertTemplateInMemory(template);
  }

  Future<void> deleteAnswerKeyTemplate(String templateId) async {
    if (kIsWeb) {
      globalAnswerKeyTemplates.removeWhere((entry) => entry.id == templateId);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.delete(
        'answer_key_templates',
        where: 'id = ?',
        whereArgs: <Object?>[templateId],
      );
    });

    globalAnswerKeyTemplates.removeWhere((entry) => entry.id == templateId);
  }

  Future<void> markAnswerKeyTemplateUsed({
    required String templateId,
    required DateTime usedAt,
  }) async {
    final index = globalAnswerKeyTemplates.indexWhere(
      (entry) => entry.id == templateId,
    );
    if (index == -1) {
      return;
    }

    final updatedTemplate = globalAnswerKeyTemplates[index].copyWith(
      lastUsedAt: usedAt,
    );

    if (kIsWeb) {
      globalAnswerKeyTemplates[index] = updatedTemplate;
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.update(
        'answer_key_templates',
        <String, Object?>{'last_used_at': usedAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: <Object?>[templateId],
      );
    });

    globalAnswerKeyTemplates[index] = updatedTemplate;
  }

  Future<void> upsertDeadline(Deadline deadline) async {
    if (kIsWeb) {
      _upsertDeadlineInMemory(deadline);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.insert(
        'deadlines',
        _deadlineRow(deadline),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _upsertDeadlineInMemory(deadline);
  }

  Future<void> deleteDeadline(String deadlineId) async {
    final deadlineIndex =
        globalDeadlines.indexWhere((entry) => entry.id == deadlineId);
    if (deadlineIndex >= 0) {
      final deadline = globalDeadlines[deadlineIndex];
      await _queueCloudDeletion(
        entityTable: 'deadlines',
        cloudId: deadline.cloudId,
        ownerTeacherId: deadline.ownerTeacherId,
      );
    }

    if (kIsWeb) {
      globalDeadlines.removeWhere((entry) => entry.id == deadlineId);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.delete(
        'deadlines',
        where: 'id = ?',
        whereArgs: <Object?>[deadlineId],
      );
    });

    globalDeadlines.removeWhere((entry) => entry.id == deadlineId);
  }

  Future<void> setDeadlineCompletion({
    required Deadline deadline,
    required bool isCompleted,
  }) async {
    if (kIsWeb) {
      deadline.isCompleted = isCompleted;
      _upsertDeadlineInMemory(deadline);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.update(
        'deadlines',
        <String, Object?>{'is_completed': isCompleted ? 1 : 0},
        where: 'id = ?',
        whereArgs: <Object?>[deadline.id],
      );
    });

    deadline.isCompleted = isCompleted;
    _upsertDeadlineInMemory(deadline);
  }

  Future<void> setScanReviewStatus({
    required ScanResult result,
    required bool needsReview,
  }) async {
    if (kIsWeb) {
      _setScanReviewStatusInMemory(result, needsReview);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await _updateStoredScanResultReviewStatus(database, result, needsReview);
    });

    _setScanReviewStatusInMemory(result, needsReview);
  }

  Future<void> clearScanReviewFlags(Iterable<ScanResult> results) async {
    final flagged = results.where((entry) => entry.requiresReview).toList();
    if (flagged.isEmpty) {
      return;
    }

    if (kIsWeb) {
      for (final result in flagged) {
        _setScanReviewStatusInMemory(result, false);
      }
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final result in flagged) {
          await _updateStoredScanResultReviewStatus(txn, result, false);
        }
      });
    });

    for (final result in flagged) {
      _setScanReviewStatusInMemory(result, false);
    }
  }

  Future<int> countScanResults() async {
    if (kIsWeb) {
      return globalScanResults.length;
    }

    final database = await _openDatabase();
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM scan_results',
    );
    final value = rows.first['count'];
    return value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<Student>> fetchStudents({String? sectionName}) async {
    if (kIsWeb) {
      var students = _filterStudentsByOwner(globalStudentDatabase);
      if (sectionName != null) {
        final normalized = sectionName.trim().toUpperCase();
        students = students
            .where((entry) => entry.section.trim().toUpperCase() == normalized)
            .toList();
      }
      students.sort((a, b) => a.name.compareTo(b.name));
      return students.map((entry) => Student.fromJson(entry.toJson())).toList();
    }

    final database = await _openDatabase();
    final (ownerWhere, ownerArgs) = _sqlOwnerScope();
    final whereParts = <String>[ownerWhere];
    final args = List<Object?>.from(ownerArgs);
    if (sectionName != null) {
      whereParts.add('section_name = ?');
      args.add(sectionName);
    }
    final rows = await database.query(
      'students',
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE ASC, omr_id ASC',
    );
    return rows.map(_studentFromRow).toList();
  }

  Future<List<Section>> fetchSections() async {
    if (kIsWeb) {
      final sections = _filterSectionsByOwner(globalSections)
          .map((entry) => Section.fromJson(entry.toJson()))
          .toList();
      sections.sort((a, b) => a.name.compareTo(b.name));
      return sections;
    }

    final database = await _openDatabase();
    final (ownerWhere, ownerArgs) = _sqlOwnerScope();
    final rows = await database.query(
      'sections',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(_sectionFromRow).toList();
  }

  Future<List<Subject>> fetchSubjects() async {
    if (kIsWeb) {
      final subjects = _filterSubjectsByOwner(globalSubjects)
          .map((entry) => Subject.fromJson(entry.toJson()))
          .toList();
      subjects.sort((a, b) => a.displayName.compareTo(b.displayName));
      return subjects;
    }

    final database = await _openDatabase();
    final (ownerWhere, ownerArgs) = _sqlOwnerScope();
    final rows = await database.query(
      'subjects',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_subjectFromRow).toList();
  }

  Future<List<ScanResult>> fetchScanResults({
    String? subjectId,
    String? sectionName,
    bool? needsReview,
  }) async {
    if (kIsWeb) {
      var results = _filterScanResultsByOwner(globalScanResults);
      if (subjectId != null) {
        results =
            results.where((entry) => entry.subjectId == subjectId).toList();
      }
      if (needsReview != null) {
        results =
            results.where((entry) => entry.needsReview == needsReview).toList();
      }
      if (sectionName != null) {
        final normalized = sectionName.trim().toUpperCase();
        results = results.where((entry) {
          final student = globalStudentIndex[entry.studentOmrId];
          return student?.section.trim().toUpperCase() == normalized;
        }).toList();
      }
      results.sort((a, b) => a.scanTime.compareTo(b.scanTime));
      return results
          .map((entry) => ScanResult.fromJson(entry.toJson()))
          .toList();
    }

    final database = await _openDatabase();
    final (ownerWhere, ownerArgs) = _sqlOwnerScope('r.owner_teacher_id');
    List<Map<String, Object?>> rows;
    if (sectionName != null) {
      final where = <String>['s.section_name = ?', ownerWhere];
      final args = <Object?>[sectionName, ...ownerArgs];
      if (subjectId != null) {
        where.add('r.subject_id = ?');
        args.add(subjectId);
      }
      if (needsReview != null) {
        where.add('r.needs_review = ?');
        args.add(needsReview ? 1 : 0);
      }

      rows = await database.rawQuery(
        '''
        SELECT r.*
        FROM scan_results r
        INNER JOIN students s ON s.omr_id = r.student_omr_id
        WHERE ${where.join(' AND ')}
        ORDER BY r.scan_time ASC, r.id ASC
        ''',
        args,
      );
    } else {
      final where = <String>[ownerWhere];
      final args = List<Object?>.from(ownerArgs);
      if (subjectId != null) {
        where.add('subject_id = ?');
        args.add(subjectId);
      }
      if (needsReview != null) {
        where.add('needs_review = ?');
        args.add(needsReview ? 1 : 0);
      }
      rows = await database.query(
        'scan_results',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'scan_time ASC, id ASC',
      );
    }
    return rows.map(_scanResultFromRow).toList();
  }

  Future<List<Deadline>> fetchDeadlines() async {
    if (kIsWeb) {
      final deadlines = _filterDeadlinesByOwner(globalDeadlines)
          .map((entry) => Deadline.fromJson(entry.toJson()))
          .toList();
      deadlines.sort((a, b) => a.dueDate.compareTo(b.dueDate));
      return deadlines;
    }

    final database = await _openDatabase();
    final (ownerWhere, ownerArgs) = _sqlOwnerScope();
    final rows = await database.query(
      'deadlines',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'due_date ASC, id ASC',
    );
    return rows.map(_deadlineFromRow).toList();
  }

  Future<List<ExportRecord>> fetchExportRecords() async {
    if (kIsWeb) {
      return globalExportRecords
          .map((entry) => ExportRecord.fromJson(entry.toJson()))
          .toList();
    }

    final database = await _openDatabase();
    final rows = await database.query(
      'export_records',
      orderBy: 'exported_at ASC',
    );
    return rows.map(_exportRecordFromRow).toList();
  }

  Future<void> recordExport(String sectionName) async {
    final record = ExportRecord(
      sectionName: sectionName,
      exportedAt: DateTime.now(),
    );

    if (kIsWeb) {
      globalExportRecords.add(record);
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.insert(
        'export_records',
        _exportRecordRow(record),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    globalExportRecords.add(record);
  }

  Future<void> claimUnownedDataForCurrentTeacher() async {
    final ownerTeacherId = _currentOwnerTeacherId;
    if (ownerTeacherId == null || kIsWeb) {
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.transaction((txn) async {
        for (final table in const <String>[
          'students',
          'sections',
          'subjects',
          'scan_results',
          'deadlines',
        ]) {
          await txn.update(
            table,
            <String, Object?>{
              'owner_teacher_id': ownerTeacherId,
              'sync_status': SyncStatus.pending,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'owner_teacher_id IS NULL',
          );
        }
      });
    });

    await _reloadMemoryFromDatabase();
  }

  Future<PendingSyncSnapshot> fetchPendingSync() async {
    if (kIsWeb) {
      return PendingSyncSnapshot(
        sections: _filterSectionsByOwner(globalSections)
            .where((entry) => entry.syncStatus == SyncStatus.pending)
            .map((entry) => Section.fromJson(entry.toJson()))
            .toList(),
        students: _filterStudentsByOwner(globalStudentDatabase)
            .where((entry) => entry.syncStatus == SyncStatus.pending)
            .map((entry) => Student.fromJson(entry.toJson()))
            .toList(),
        subjects: _filterSubjectsByOwner(globalSubjects)
            .where((entry) => entry.syncStatus == SyncStatus.pending)
            .map((entry) => Subject.fromJson(entry.toJson()))
            .toList(),
        scanResults: _filterScanResultsByOwner(globalScanResults)
            .where((entry) => entry.syncStatus == SyncStatus.pending)
            .map((entry) => ScanResult.fromJson(entry.toJson()))
            .toList(),
        deadlines: _filterDeadlinesByOwner(globalDeadlines)
            .where((entry) => entry.syncStatus == SyncStatus.pending)
            .map((entry) => Deadline.fromJson(entry.toJson()))
            .toList(),
      );
    }

    final database = await _openDatabase();
    final (ownerWhere, ownerArgs) = _sqlOwnerScope();
    final pendingWhere = 'sync_status = ? AND $ownerWhere';
    final pendingArgs = <Object?>[SyncStatus.pending, ...ownerArgs];
    final sections = await database.query(
      'sections',
      where: pendingWhere,
      whereArgs: pendingArgs,
    );
    final students = await database.query(
      'students',
      where: pendingWhere,
      whereArgs: pendingArgs,
    );
    final subjects = await database.query(
      'subjects',
      where: pendingWhere,
      whereArgs: pendingArgs,
    );
    final scanResults = await database.query(
      'scan_results',
      where: pendingWhere,
      whereArgs: pendingArgs,
      orderBy: 'scan_time ASC, id ASC',
    );
    final deadlines = await database.query(
      'deadlines',
      where: pendingWhere,
      whereArgs: pendingArgs,
    );

    return PendingSyncSnapshot(
      sections: sections.map(_sectionFromRow).toList(),
      students: students.map(_studentFromRow).toList(),
      subjects: subjects.map(_subjectFromRow).toList(),
      scanResults: scanResults.map(_scanResultFromRow).toList(),
      deadlines: deadlines.map(_deadlineFromRow).toList(),
    );
  }

  Future<int> countPendingSync() async {
    final snapshot = await fetchPendingSync();
    return snapshot.total;
  }

  Future<CloudMergeSummary> applyCloudSnapshot(CloudPullSnapshot cloud) async {
    if (kIsWeb) {
      final local = _snapshotFromCurrentMemory();
      final excluded = await _fetchPendingDeletionCloudIds();
      final filteredCloud = _filterCloudByDeletions(cloud, excluded);
      final merged = CloudSnapshotMerger.merge(
        localSections: local.sections,
        localStudents: local.students,
        localSubjects: local.subjects,
        localScanResults: local.scanResults,
        localDeadlines: local.deadlines,
        cloud: filteredCloud,
      );
      _applySnapshotToMemory(
        _AppSnapshot(
          students: merged.students,
          sections: merged.sections,
          subjects: merged.subjects,
          scanResults: merged.scanResults,
          deadlines: merged.deadlines,
          exportRecords: local.exportRecords,
          answerKeyTemplates: local.answerKeyTemplates,
          omrCounter: local.omrCounter,
          subjectCounter: local.subjectCounter,
          sheetCounter: local.sheetCounter,
        ),
      );
      return merged.summary;
    }

    final database = await _openDatabase();
    final allLocal = await _readSnapshotFromDatabase(
      database,
      scopeToCurrentTeacher: false,
    );
    final otherOwners = _snapshotForOtherTeachers(allLocal);
    final localForMerge = _snapshotForCurrentTeacher(allLocal);
    final excluded = await _fetchPendingDeletionCloudIds();
    final filteredCloud = _filterCloudByDeletions(cloud, excluded);

    final merged = CloudSnapshotMerger.merge(
      localSections: localForMerge.sections,
      localStudents: localForMerge.students,
      localSubjects: localForMerge.subjects,
      localScanResults: localForMerge.scanResults,
      localDeadlines: localForMerge.deadlines,
      cloud: filteredCloud,
    );

    final combined = _combineSnapshots(
      otherOwners,
      _AppSnapshot(
        students: merged.students,
        sections: merged.sections,
        subjects: merged.subjects,
        scanResults: merged.scanResults,
        deadlines: merged.deadlines,
        exportRecords: allLocal.exportRecords,
        answerKeyTemplates: allLocal.answerKeyTemplates,
        omrCounter: allLocal.omrCounter,
        subjectCounter: allLocal.subjectCounter,
        sheetCounter: allLocal.sheetCounter,
      ),
    );

    await database.transaction((txn) async {
      await _replaceDatabaseContents(txn, combined);
    });
    _applySnapshotToMemory(_snapshotForCurrentTeacher(combined));
    return merged.summary;
  }

  Future<void> markSectionSynced({
    required String name,
    required String cloudId,
  }) async {
    await _markRowsSynced(
      table: 'sections',
      cloudId: cloudId,
      where: 'name = ?',
      whereArgs: <Object?>[name],
    );
  }

  Future<void> markStudentSynced({
    required String omrId,
    required String cloudId,
  }) async {
    await _markRowsSynced(
      table: 'students',
      cloudId: cloudId,
      where: 'omr_id = ?',
      whereArgs: <Object?>[omrId],
    );
  }

  Future<void> markSubjectSynced({
    required String localId,
    required String cloudId,
  }) async {
    await _markRowsSynced(
      table: 'subjects',
      cloudId: cloudId,
      where: 'id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> markScanResultSynced({
    required ScanResult result,
    required String cloudId,
  }) async {
    final scanTimeIso = result.scanTime.toIso8601String();
    final where = result.subjectId == null
        ? 'student_omr_id = ? AND subject_id IS NULL AND subject_name = ? AND scan_time = ?'
        : 'student_omr_id = ? AND subject_id = ? AND scan_time = ?';
    final whereArgs = result.subjectId == null
        ? <Object?>[result.studentOmrId, result.subjectName, scanTimeIso]
        : <Object?>[result.studentOmrId, result.subjectId, scanTimeIso];

    await _markRowsSynced(
      table: 'scan_results',
      cloudId: cloudId,
      where: where,
      whereArgs: whereArgs,
    );
  }

  Future<void> markDeadlineSynced({
    required String localId,
    required String cloudId,
  }) async {
    await _markRowsSynced(
      table: 'deadlines',
      cloudId: cloudId,
      where: 'id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  Future<void> reloadFromDatabase() => _reloadMemoryFromDatabase();

  Future<Database> _openDatabase() async {
    if (_database != null) {
      return _database!;
    }

    ensureSqliteForPlatform();
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, _databaseName);

    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _upgradeToV2(db);
        }
        if (oldVersion < 3) {
          await _upgradeToV3(db);
        }
        if (oldVersion < 4) {
          await _upgradeToV4(db);
        }
      },
    );

    return _database!;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE students (
        omr_id TEXT PRIMARY KEY,
        school_id TEXT NOT NULL,
        name TEXT NOT NULL,
        section_name TEXT NOT NULL,
        score REAL,
        answers_json TEXT,
        scan_date TEXT,
        confidence REAL,
        owner_teacher_id TEXT,
        cloud_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_students_section ON students(section_name)',
    );

    await db.execute('''
      CREATE TABLE sections (
        name TEXT PRIMARY KEY,
        teacher TEXT,
        student_count INTEGER,
        owner_teacher_id TEXT,
        cloud_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        answer_key_json TEXT NOT NULL,
        total_questions INTEGER NOT NULL,
        section_names_json TEXT,
        section_qr_data_json TEXT NOT NULL,
        exam_date TEXT,
        passing_score INTEGER NOT NULL,
        use_partial_credit INTEGER NOT NULL DEFAULT 0,
        owner_teacher_id TEXT,
        cloud_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_subjects_name ON subjects(name)');

    await db.execute('''
      CREATE TABLE scan_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_omr_id TEXT NOT NULL,
        subject_id TEXT,
        subject_name TEXT NOT NULL,
        sheet_id TEXT,
        detected_answers_json TEXT NOT NULL,
        correctness_map_json TEXT NOT NULL,
        score REAL NOT NULL,
        total_questions INTEGER NOT NULL,
        confidence REAL NOT NULL,
        scan_time TEXT NOT NULL,
        scanned_image_path TEXT,
        review_reasons_json TEXT,
        flagged_questions_json TEXT,
        manually_confirmed INTEGER NOT NULL DEFAULT 0,
        needs_review INTEGER NOT NULL DEFAULT 0,
        owner_teacher_id TEXT,
        cloud_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_scan_results_student ON scan_results(student_omr_id)',
    );
    await db.execute(
      'CREATE INDEX idx_scan_results_subject ON scan_results(subject_id)',
    );
    await db.execute(
      'CREATE INDEX idx_scan_results_sheet_id ON scan_results(sheet_id)',
    );
    await db.execute(
      'CREATE INDEX idx_scan_results_time ON scan_results(scan_time)',
    );

    await db.execute('''
      CREATE TABLE deadlines (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        section_name TEXT,
        subject_id TEXT,
        due_date TEXT NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0,
        owner_teacher_id TEXT,
        cloud_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_deadlines_due_date ON deadlines(due_date)',
    );

    await db.execute('''
      CREATE TABLE export_records (
        section_name TEXT NOT NULL,
        exported_at TEXT NOT NULL,
        PRIMARY KEY(section_name, exported_at)
      )
    ''');

    await db.execute('''
      CREATE TABLE answer_key_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        answer_key_json TEXT NOT NULL,
        total_questions INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        last_used_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createPendingDeletionsTable(db);
  }

  Future<void> _createPendingDeletionsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_deletions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_table TEXT NOT NULL,
        cloud_id TEXT NOT NULL,
        owner_teacher_id TEXT,
        deleted_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_deletions_cloud ON pending_deletions(entity_table, cloud_id)',
    );
  }

  Future<void> _upgradeToV2(Database db) async {
    await db.execute(
      'ALTER TABLE scan_results ADD COLUMN review_reasons_json TEXT',
    );
    await db.execute(
      'ALTER TABLE scan_results ADD COLUMN flagged_questions_json TEXT',
    );
    await db.execute(
      'ALTER TABLE scan_results ADD COLUMN manually_confirmed INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _upgradeToV3(Database db) async {
    final now = DateTime.now().toIso8601String();
    await _addColumnIfMissing(
      db,
      'scan_results',
      'needs_review INTEGER NOT NULL DEFAULT 0',
    );
    for (final table in const <String>[
      'students',
      'sections',
      'subjects',
      'scan_results',
      'deadlines',
    ]) {
      await _addColumnIfMissing(db, table, 'owner_teacher_id TEXT');
      await _addColumnIfMissing(db, table, 'cloud_id TEXT');
      await _addColumnIfMissing(
        db,
        table,
        "sync_status TEXT NOT NULL DEFAULT 'pending'",
      );
      await _addColumnIfMissing(
        db,
        table,
        "updated_at TEXT NOT NULL DEFAULT '$now'",
      );
    }
  }

  Future<void> _upgradeToV4(Database db) async {
    await _createPendingDeletionsTable(db);
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor executor,
    String table,
    String columnDefinition,
  ) async {
    try {
      await executor.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    } catch (error) {
      if (!error.toString().toLowerCase().contains('duplicate column')) {
        rethrow;
      }
    }
  }

  Future<void> _saveCurrentSnapshot() async {
    final database = await _openDatabase();
    final snapshot = _snapshotFromCurrentMemory();

    await database.transaction((txn) async {
      await _replaceDatabaseContents(txn, snapshot);
    });
  }

  Future<void> _enqueueDbWrite(Future<void> Function() action) {
    final next = _pendingSave.then<void>((_) => action());
    _pendingSave = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Local data write failed: $error');
    });
    return next;
  }

  Future<void> _markRowsSynced({
    required String table,
    required String cloudId,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    if (kIsWeb) {
      return;
    }

    await _enqueueDbWrite(() async {
      final database = await _openDatabase();
      await database.update(
        table,
        <String, Object?>{
          'cloud_id': cloudId,
          'sync_status': SyncStatus.synced,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: where,
        whereArgs: whereArgs,
      );
    });
  }

  Future<void> _replaceDatabaseContents(
    DatabaseExecutor executor,
    _AppSnapshot snapshot,
  ) async {
    await executor.delete('scan_results');
    await executor.delete('deadlines');
    await executor.delete('export_records');
    await executor.delete('answer_key_templates');
    await executor.delete('subjects');
    await executor.delete('students');
    await executor.delete('sections');
    await executor.delete('app_meta');

    final sectionsBatch = executor.batch();
    for (final section in snapshot.sections) {
      sectionsBatch.insert(
        'sections',
        _sectionRow(section),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await sectionsBatch.commit(noResult: true);

    final studentsBatch = executor.batch();
    for (final student in snapshot.students) {
      studentsBatch.insert(
        'students',
        _studentRow(student),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await studentsBatch.commit(noResult: true);

    final subjectsBatch = executor.batch();
    for (final subject in snapshot.subjects) {
      subjectsBatch.insert(
        'subjects',
        _subjectRow(subject),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await subjectsBatch.commit(noResult: true);

    final scanResultsBatch = executor.batch();
    for (final result in snapshot.scanResults) {
      scanResultsBatch.insert(
        'scan_results',
        _scanResultRow(result),
      );
    }
    await scanResultsBatch.commit(noResult: true);

    final deadlinesBatch = executor.batch();
    for (final deadline in snapshot.deadlines) {
      deadlinesBatch.insert(
        'deadlines',
        _deadlineRow(deadline),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await deadlinesBatch.commit(noResult: true);

    final exportRecordsBatch = executor.batch();
    for (final record in snapshot.exportRecords) {
      exportRecordsBatch.insert(
        'export_records',
        <String, Object?>{
          'section_name': record.sectionName,
          'exported_at': record.exportedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await exportRecordsBatch.commit(noResult: true);

    final templatesBatch = executor.batch();
    for (final template in snapshot.answerKeyTemplates) {
      final json = template.toJson();
      templatesBatch.insert(
        'answer_key_templates',
        <String, Object?>{
          'id': template.id,
          'name': template.name,
          'description': template.description,
          'answer_key_json': jsonEncode(json['answerKey']),
          'total_questions': template.totalQuestions,
          'created_at': template.createdAt.toIso8601String(),
          'last_used_at': template.lastUsedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await templatesBatch.commit(noResult: true);

    final metaBatch = executor.batch();
    metaBatch.insert(
      'app_meta',
      <String, Object?>{
        'key': 'omrCounter',
        'value': snapshot.omrCounter.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    metaBatch.insert(
      'app_meta',
      <String, Object?>{
        'key': 'subjectCounter',
        'value': snapshot.subjectCounter.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    metaBatch.insert(
      'app_meta',
      <String, Object?>{
        'key': 'sheetCounter',
        'value': snapshot.sheetCounter.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    metaBatch.insert(
      'app_meta',
      <String, Object?>{
        'key': 'savedAt',
        'value': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await metaBatch.commit(noResult: true);
  }

  Future<_AppSnapshot> _readSnapshotFromDatabase(
    Database database, {
    bool scopeToCurrentTeacher = true,
  }) async {
    final (ownerWhere, ownerArgs) =
        scopeToCurrentTeacher ? _sqlOwnerScope() : ('1=1', const <Object?>[]);
    final studentsRows = await database.query(
      'students',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'omr_id ASC',
    );
    final sectionsRows = await database.query(
      'sections',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'name ASC',
    );
    final subjectsRows = await database.query(
      'subjects',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'name ASC, id ASC',
    );
    final scanResultsRows = await database.query(
      'scan_results',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'scan_time ASC, id ASC',
    );
    final deadlinesRows = await database.query(
      'deadlines',
      where: ownerWhere,
      whereArgs: ownerArgs,
      orderBy: 'due_date ASC, id ASC',
    );
    final exportRecordsRows = await database.query(
      'export_records',
      orderBy: 'exported_at ASC',
    );
    final templatesRows = await database.query(
      'answer_key_templates',
      orderBy: 'created_at ASC, id ASC',
    );
    final metaRows = await database.query('app_meta');

    final meta = <String, String>{
      for (final row in metaRows)
        row['key']?.toString() ?? '': row['value']?.toString() ?? '',
    };

    return _AppSnapshot(
      students: _safeMapRows(
        studentsRows,
        _studentFromRow,
        label: 'student',
      ),
      sections: _safeMapRows(
        sectionsRows,
        _sectionFromRow,
        label: 'section',
      ),
      subjects: _safeMapRows(
        subjectsRows,
        _subjectFromRow,
        label: 'subject',
      ),
      scanResults: _safeMapRows(
        scanResultsRows,
        _scanResultFromRow,
        label: 'scan result',
      ),
      deadlines: _safeMapRows(
        deadlinesRows,
        _deadlineFromRow,
        label: 'deadline',
      ),
      exportRecords: _safeMapRows(
        exportRecordsRows,
        _exportRecordFromRow,
        label: 'export record',
      ),
      answerKeyTemplates: _safeMapRows(
        templatesRows,
        _answerKeyTemplateFromRow,
        label: 'answer key template',
      ),
      omrCounter: int.tryParse(meta['omrCounter'] ?? '') ?? 1,
      subjectCounter: int.tryParse(meta['subjectCounter'] ?? '') ?? 1,
      sheetCounter: int.tryParse(meta['sheetCounter'] ?? '') ?? 1,
    );
  }

  Future<void> _migrateLegacyJsonIfNeeded(Database database) async {
    final hasData = await _databaseHasAnyRows(database);
    if (hasData) {
      return;
    }

    final legacyFile = await _resolveLegacyFile();
    if (!await legacyFile.exists()) {
      return;
    }

    try {
      final raw = await legacyFile.readAsString();
      if (raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final snapshot = _snapshotFromBackupMap(decoded);
      await database.transaction((txn) async {
        await _replaceDatabaseContents(txn, snapshot);
      });
    } catch (error) {
      debugPrint('Legacy JSON migration failed: $error');
    }
  }

  Future<bool> _databaseHasAnyRows(Database database) async {
    final tables = <String>[
      'students',
      'sections',
      'subjects',
      'scan_results',
      'deadlines',
      'answer_key_templates',
      'export_records',
    ];

    for (final table in tables) {
      final result = await database.rawQuery(
        'SELECT EXISTS(SELECT 1 FROM $table LIMIT 1) AS has_rows',
      );
      final value = result.first['has_rows'];
      if (value is int && value == 1) {
        return true;
      }
    }

    return false;
  }

  Future<void> _reloadMemoryFromDatabase() async {
    final database = await _openDatabase();
    final snapshot = await _readSnapshotFromDatabase(database);
    _applySnapshotToMemory(snapshot);
  }

  Future<File> _resolveLegacyFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, _legacyFileName));
  }

  Student _studentFromRow(Map<String, Object?> row) {
    return Student.fromJson(
      <String, dynamic>{
        'schoolId': row['school_id'],
        'omrId': row['omr_id'],
        'name': row['name'],
        'section': row['section_name'],
        'score': row['score'],
        'answers': _decodeJsonMap(row['answers_json'] as String?),
        'scanDate': row['scan_date'],
        'confidence': row['confidence'],
        'ownerTeacherId': row['owner_teacher_id'],
        'cloudId': row['cloud_id'],
        'syncStatus': row['sync_status'],
        'updatedAt': row['updated_at'],
      },
    );
  }

  Section _sectionFromRow(Map<String, Object?> row) {
    return Section.fromJson(
      <String, dynamic>{
        'name': row['name'],
        'teacher': row['teacher'],
        'studentCount': row['student_count'],
        'ownerTeacherId': row['owner_teacher_id'],
        'cloudId': row['cloud_id'],
        'syncStatus': row['sync_status'],
        'updatedAt': row['updated_at'],
      },
    );
  }

  Subject _subjectFromRow(Map<String, Object?> row) {
    return Subject.fromJson(
      <String, dynamic>{
        'id': row['id'],
        'name': row['name'],
        'answerKey': _decodeJsonMap(row['answer_key_json'] as String?),
        'totalQuestions': _readInt(row['total_questions'], fallback: 50),
        'sectionNames': _decodeJsonList(row['section_names_json'] as String?),
        'sectionQrData': _decodeJsonMap(row['section_qr_data_json'] as String?),
        'examDate': row['exam_date'],
        'passingScore': _readInt(row['passing_score']),
        'usePartialCredit': row['use_partial_credit'] == 1,
        'ownerTeacherId': row['owner_teacher_id'],
        'cloudId': row['cloud_id'],
        'syncStatus': row['sync_status'],
        'updatedAt': row['updated_at'],
      },
    );
  }

  Deadline _deadlineFromRow(Map<String, Object?> row) {
    return Deadline.fromJson(
      <String, dynamic>{
        'id': row['id'],
        'title': row['title'],
        'sectionName': row['section_name'],
        'subjectId': row['subject_id'],
        'dueDate': row['due_date'],
        'isCompleted': row['is_completed'] == 1,
        'ownerTeacherId': row['owner_teacher_id'],
        'cloudId': row['cloud_id'],
        'syncStatus': row['sync_status'],
        'updatedAt': row['updated_at'],
      },
    );
  }

  ScanResult _scanResultFromRow(Map<String, Object?> row) {
    return ScanResult.fromJson(
      <String, dynamic>{
        'studentOmrId': row['student_omr_id'],
        'subjectId': row['subject_id'],
        'subjectName': row['subject_name'],
        'sheetId': row['sheet_id'],
        'detectedAnswers':
            _decodeJsonMap(row['detected_answers_json'] as String?),
        'correctnessMap':
            _decodeJsonMap(row['correctness_map_json'] as String?),
        'score': row['score'],
        'totalQuestions': row['total_questions'],
        'confidence': row['confidence'],
        'scanTime': row['scan_time'],
        'scannedImagePath': row['scanned_image_path'],
        'reviewReasons': _decodeJsonList(row['review_reasons_json'] as String?),
        'flaggedQuestions':
            _decodeJsonList(row['flagged_questions_json'] as String?),
        'manuallyConfirmed': row['manually_confirmed'] == 1,
        'needsReview': row['needs_review'] == 1,
        'ownerTeacherId': row['owner_teacher_id'],
        'cloudId': row['cloud_id'],
        'syncStatus': row['sync_status'],
        'updatedAt': row['updated_at'],
      },
    );
  }

  ExportRecord _exportRecordFromRow(Map<String, Object?> row) {
    return ExportRecord.fromJson(
      <String, dynamic>{
        'sectionName': row['section_name'],
        'exportedAt': row['exported_at'],
      },
    );
  }

  AnswerKeyTemplate _answerKeyTemplateFromRow(Map<String, Object?> row) {
    return AnswerKeyTemplate.fromJson(
      <String, dynamic>{
        'id': row['id'],
        'name': row['name'],
        'description': row['description'],
        'answerKey': _decodeJsonMap(row['answer_key_json'] as String?),
        'totalQuestions': _readInt(row['total_questions'], fallback: 50),
        'createdAt': row['created_at'],
        'lastUsedAt': row['last_used_at'],
      },
    );
  }

  String? get _currentOwnerTeacherId {
    return SupabaseService.currentUserId;
  }

  bool _rowBelongsToCurrentTeacher(String? ownerTeacherId) {
    final current = _currentOwnerTeacherId;
    if (current == null || current.isEmpty) {
      return ownerTeacherId == null || ownerTeacherId.isEmpty;
    }
    return ownerTeacherId == null ||
        ownerTeacherId.isEmpty ||
        ownerTeacherId == current;
  }

  bool _rowBelongsToOtherTeacher(String? ownerTeacherId) {
    final current = _currentOwnerTeacherId;
    if (current == null || current.isEmpty) {
      return false;
    }
    return ownerTeacherId != null &&
        ownerTeacherId.isNotEmpty &&
        ownerTeacherId != current;
  }

  (String where, List<Object?> args) _sqlOwnerScope([String column = 'owner_teacher_id']) {
    final current = _currentOwnerTeacherId;
    if (current == null || current.isEmpty) {
      return ('$column IS NULL', const <Object?>[]);
    }
    return ('($column IS NULL OR $column = ?)', <Object?>[current]);
  }

  List<Student> _filterStudentsByOwner(List<Student> students) {
    return students
        .where((entry) => _rowBelongsToCurrentTeacher(entry.ownerTeacherId))
        .toList();
  }

  List<Section> _filterSectionsByOwner(List<Section> sections) {
    return sections
        .where((entry) => _rowBelongsToCurrentTeacher(entry.ownerTeacherId))
        .toList();
  }

  List<Subject> _filterSubjectsByOwner(List<Subject> subjects) {
    return subjects
        .where((entry) => _rowBelongsToCurrentTeacher(entry.ownerTeacherId))
        .toList();
  }

  List<ScanResult> _filterScanResultsByOwner(List<ScanResult> results) {
    return results
        .where((entry) => _rowBelongsToCurrentTeacher(entry.ownerTeacherId))
        .toList();
  }

  List<Deadline> _filterDeadlinesByOwner(List<Deadline> deadlines) {
    return deadlines
        .where((entry) => _rowBelongsToCurrentTeacher(entry.ownerTeacherId))
        .toList();
  }

  _AppSnapshot _snapshotForCurrentTeacher(_AppSnapshot snapshot) {
    return _AppSnapshot(
      students: _filterStudentsByOwner(snapshot.students),
      sections: _filterSectionsByOwner(snapshot.sections),
      subjects: _filterSubjectsByOwner(snapshot.subjects),
      scanResults: _filterScanResultsByOwner(snapshot.scanResults),
      deadlines: _filterDeadlinesByOwner(snapshot.deadlines),
      exportRecords: snapshot.exportRecords,
      answerKeyTemplates: snapshot.answerKeyTemplates,
      omrCounter: snapshot.omrCounter,
      subjectCounter: snapshot.subjectCounter,
      sheetCounter: snapshot.sheetCounter,
    );
  }

  _AppSnapshot _snapshotForOtherTeachers(_AppSnapshot snapshot) {
    return _AppSnapshot(
      students: snapshot.students
          .where((entry) => _rowBelongsToOtherTeacher(entry.ownerTeacherId))
          .toList(),
      sections: snapshot.sections
          .where((entry) => _rowBelongsToOtherTeacher(entry.ownerTeacherId))
          .toList(),
      subjects: snapshot.subjects
          .where((entry) => _rowBelongsToOtherTeacher(entry.ownerTeacherId))
          .toList(),
      scanResults: snapshot.scanResults
          .where((entry) => _rowBelongsToOtherTeacher(entry.ownerTeacherId))
          .toList(),
      deadlines: snapshot.deadlines
          .where((entry) => _rowBelongsToOtherTeacher(entry.ownerTeacherId))
          .toList(),
      exportRecords: const <ExportRecord>[],
      answerKeyTemplates: const <AnswerKeyTemplate>[],
      omrCounter: snapshot.omrCounter,
      subjectCounter: snapshot.subjectCounter,
      sheetCounter: snapshot.sheetCounter,
    );
  }

  int _maxCounter(int left, int right) => left > right ? left : right;

  _AppSnapshot _combineSnapshots(_AppSnapshot primary, _AppSnapshot secondary) {
    return _AppSnapshot(
      students: [...primary.students, ...secondary.students],
      sections: [...primary.sections, ...secondary.sections],
      subjects: [...primary.subjects, ...secondary.subjects],
      scanResults: [...primary.scanResults, ...secondary.scanResults],
      deadlines: [...primary.deadlines, ...secondary.deadlines],
      exportRecords: primary.exportRecords.isEmpty
          ? secondary.exportRecords
          : primary.exportRecords,
      answerKeyTemplates: primary.answerKeyTemplates.isEmpty
          ? secondary.answerKeyTemplates
          : primary.answerKeyTemplates,
      omrCounter: primary.omrCounter,
      subjectCounter: primary.subjectCounter,
      sheetCounter: primary.sheetCounter,
    );
  }

  _AppSnapshot _restampSnapshotOwner(_AppSnapshot snapshot) {
    final ownerId = _currentOwnerTeacherId;
    if (ownerId == null || ownerId.isEmpty) {
      return snapshot;
    }

    Student restampStudent(Student student) => student.copyWith(
          ownerTeacherId: ownerId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime.now(),
        );
    Section restampSection(Section section) => Section(
          name: section.name,
          teacher: section.teacher,
          studentCount: section.studentCount,
          ownerTeacherId: ownerId,
          cloudId: section.cloudId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime.now(),
        );
    Subject restampSubject(Subject subject) => subject.copyWith(
          ownerTeacherId: ownerId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime.now(),
        );
    ScanResult restampScan(ScanResult result) => ScanResult(
          studentOmrId: result.studentOmrId,
          subjectId: result.subjectId,
          subjectName: result.subjectName,
          sheetId: result.sheetId,
          detectedAnswers: result.detectedAnswers,
          correctnessMap: result.correctnessMap,
          score: result.score,
          totalQuestions: result.totalQuestions,
          confidence: result.confidence,
          scanTime: result.scanTime,
          scannedImagePath: result.scannedImagePath,
          reviewReasons: result.reviewReasons,
          flaggedQuestions: result.flaggedQuestions,
          manuallyConfirmed: result.manuallyConfirmed,
          needsReview: result.needsReview,
          ownerTeacherId: ownerId,
          cloudId: result.cloudId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime.now(),
        );
    Deadline restampDeadline(Deadline deadline) => deadline.copyWith(
          ownerTeacherId: ownerId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime.now(),
        );

    return _AppSnapshot(
      students: snapshot.students.map(restampStudent).toList(),
      sections: snapshot.sections.map(restampSection).toList(),
      subjects: snapshot.subjects.map(restampSubject).toList(),
      scanResults: snapshot.scanResults.map(restampScan).toList(),
      deadlines: snapshot.deadlines.map(restampDeadline).toList(),
      exportRecords: snapshot.exportRecords,
      answerKeyTemplates: snapshot.answerKeyTemplates,
      omrCounter: snapshot.omrCounter,
      subjectCounter: snapshot.subjectCounter,
      sheetCounter: snapshot.sheetCounter,
    );
  }

  Future<void> _queueCloudDeletion({
    required String entityTable,
    required String? cloudId,
    String? ownerTeacherId,
  }) async {
    if (kIsWeb || cloudId == null || cloudId.isEmpty) {
      return;
    }

    final database = await _openDatabase();
    final existing = await database.query(
      'pending_deletions',
      columns: const <String>['id'],
      where: 'entity_table = ? AND cloud_id = ?',
      whereArgs: <Object?>[entityTable, cloudId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }

    await database.insert(
      'pending_deletions',
      <String, Object?>{
        'entity_table': entityTable,
        'cloud_id': cloudId,
        'owner_teacher_id': ownerTeacherId ?? _currentOwnerTeacherId,
        'deleted_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, Set<String>>> _fetchPendingDeletionCloudIds() async {
    if (kIsWeb) {
      return const <String, Set<String>>{};
    }

    final database = await _openDatabase();
    final rows = await database.query('pending_deletions');
    final grouped = <String, Set<String>>{};
    for (final row in rows) {
      final table = row['entity_table']?.toString();
      final cloudId = row['cloud_id']?.toString();
      if (table == null || cloudId == null || cloudId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(table, () => <String>{}).add(cloudId);
    }
    return grouped;
  }

  CloudPullSnapshot _filterCloudByDeletions(
    CloudPullSnapshot cloud,
    Map<String, Set<String>> excluded,
  ) {
    bool keep(String table, String? cloudId) {
      if (cloudId == null || cloudId.isEmpty) {
        return true;
      }
      return !(excluded[table]?.contains(cloudId) ?? false);
    }

    return CloudPullSnapshot(
      sections: cloud.sections
          .where((entry) => keep('sections', entry.cloudId))
          .toList(),
      students: cloud.students
          .where((entry) => keep('students', entry.cloudId))
          .toList(),
      subjects: cloud.subjects
          .where((entry) => keep('subjects', entry.cloudId))
          .toList(),
      scanResults: cloud.scanResults
          .where((entry) => keep('scan_results', entry.cloudId))
          .toList(),
      deadlines: cloud.deadlines
          .where((entry) => keep('deadlines', entry.cloudId))
          .toList(),
    );
  }

  Future<int> processPendingDeletions(SupabaseClient client) async {
    if (kIsWeb) {
      return 0;
    }

    final ownerTeacherId = _currentOwnerTeacherId;
    if (ownerTeacherId == null || ownerTeacherId.isEmpty) {
      return 0;
    }

    final database = await _openDatabase();
    final rows = await database.query(
      'pending_deletions',
      where: 'owner_teacher_id IS NULL OR owner_teacher_id = ?',
      whereArgs: <Object?>[ownerTeacherId],
      orderBy: 'id ASC',
    );

    var processed = 0;
    for (final row in rows) {
      final table = row['entity_table']?.toString();
      final cloudId = row['cloud_id']?.toString();
      final rowId = row['id'];
      if (table == null || cloudId == null || cloudId.isEmpty || rowId == null) {
        continue;
      }

      try {
        await client.from(table).delete().eq('id', cloudId);
        await database.delete(
          'pending_deletions',
          where: 'id = ?',
          whereArgs: <Object?>[rowId],
        );
        processed++;
      } catch (error) {
        debugPrint('Cloud deletion failed for $table/$cloudId: $error');
      }
    }

    return processed;
  }

  Map<String, Object?> _syncColumns({
    required String? ownerTeacherId,
    required String? cloudId,
    required String syncStatus,
    required DateTime updatedAt,
  }) {
    return <String, Object?>{
      'owner_teacher_id': ownerTeacherId ?? _currentOwnerTeacherId,
      'cloud_id': cloudId,
      'sync_status': syncStatus,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, Object?> _studentRow(Student student) {
    final json = student.toJson();
    return <String, Object?>{
      'omr_id': student.omrId,
      'school_id': student.schoolId,
      'name': student.name,
      'section_name': student.section,
      'score': student.score,
      'answers_json':
          json['answers'] == null ? null : jsonEncode(json['answers']),
      'scan_date': student.scanDate?.toIso8601String(),
      'confidence': student.confidence,
      ..._syncColumns(
        ownerTeacherId: student.ownerTeacherId,
        cloudId: student.cloudId,
        syncStatus: student.syncStatus,
        updatedAt: student.updatedAt,
      ),
    };
  }

  Map<String, Object?> _sectionRow(Section section) {
    return <String, Object?>{
      'name': section.name,
      'teacher': section.teacher,
      'student_count': section.studentCount,
      ..._syncColumns(
        ownerTeacherId: section.ownerTeacherId,
        cloudId: section.cloudId,
        syncStatus: section.syncStatus,
        updatedAt: section.updatedAt,
      ),
    };
  }

  Map<String, Object?> _subjectRow(Subject subject) {
    final json = subject.toJson();
    return <String, Object?>{
      'id': subject.id,
      'name': subject.name,
      'answer_key_json': jsonEncode(json['answerKey']),
      'total_questions': subject.totalQuestions,
      'section_names_json': json['sectionNames'] == null
          ? null
          : jsonEncode(json['sectionNames']),
      'section_qr_data_json': jsonEncode(subject.sectionQrData),
      'exam_date': subject.examDate?.toIso8601String(),
      'passing_score': subject.passingScore,
      'use_partial_credit': subject.usePartialCredit ? 1 : 0,
      ..._syncColumns(
        ownerTeacherId: subject.ownerTeacherId,
        cloudId: subject.cloudId,
        syncStatus: subject.syncStatus,
        updatedAt: subject.updatedAt,
      ),
    };
  }

  Map<String, Object?> _scanResultRow(ScanResult result) {
    final json = result.toJson();
    return <String, Object?>{
      'student_omr_id': result.studentOmrId,
      'subject_id': result.subjectId,
      'subject_name': result.subjectName,
      'sheet_id': result.sheetId,
      'detected_answers_json': jsonEncode(json['detectedAnswers']),
      'correctness_map_json': jsonEncode(json['correctnessMap']),
      'score': result.score,
      'total_questions': result.totalQuestions,
      'confidence': result.confidence,
      'scan_time': result.scanTime.toIso8601String(),
      'scanned_image_path': result.scannedImagePath,
      'review_reasons_json': jsonEncode(result.reviewReasons),
      'flagged_questions_json': jsonEncode(result.flaggedQuestions),
      'manually_confirmed': result.manuallyConfirmed ? 1 : 0,
      'needs_review': result.needsReview ? 1 : 0,
      ..._syncColumns(
        ownerTeacherId: result.ownerTeacherId,
        cloudId: result.cloudId,
        syncStatus: result.syncStatus,
        updatedAt: result.updatedAt,
      ),
    };
  }

  Map<String, Object?> _deadlineRow(Deadline deadline) {
    return <String, Object?>{
      'id': deadline.id,
      'title': deadline.title,
      'section_name': deadline.sectionName,
      'subject_id': deadline.subjectId,
      'due_date': deadline.dueDate.toIso8601String(),
      'is_completed': deadline.isCompleted ? 1 : 0,
      ..._syncColumns(
        ownerTeacherId: deadline.ownerTeacherId,
        cloudId: deadline.cloudId,
        syncStatus: deadline.syncStatus,
        updatedAt: deadline.updatedAt,
      ),
    };
  }

  Map<String, Object?> _answerKeyTemplateRow(AnswerKeyTemplate template) {
    final json = template.toJson();
    return <String, Object?>{
      'id': template.id,
      'name': template.name,
      'description': template.description,
      'answer_key_json': jsonEncode(json['answerKey']),
      'total_questions': template.totalQuestions,
      'created_at': template.createdAt.toIso8601String(),
      'last_used_at': template.lastUsedAt?.toIso8601String(),
    };
  }

  Map<String, Object?> _exportRecordRow(ExportRecord record) {
    return <String, Object?>{
      'section_name': record.sectionName,
      'exported_at': record.exportedAt.toIso8601String(),
    };
  }

  Future<void> _persistCounters(DatabaseExecutor executor) async {
    await executor.insert(
      'app_meta',
      <String, Object?>{
        'key': 'omrCounter',
        'value': nextOmrIdValue.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await executor.insert(
      'app_meta',
      <String, Object?>{
        'key': 'subjectCounter',
        'value': nextSubjectCounterValue.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await executor.insert(
      'app_meta',
      <String, Object?>{
        'key': 'sheetCounter',
        'value': nextSheetCounterValue.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await executor.insert(
      'app_meta',
      <String, Object?>{
        'key': 'savedAt',
        'value': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _deleteStoredScanResult(
    DatabaseExecutor executor,
    ScanResult result,
  ) async {
    final scanTimeIso = result.scanTime.toIso8601String();
    if (result.subjectId == null) {
      await executor.delete(
        'scan_results',
        where:
            'student_omr_id = ? AND subject_id IS NULL AND subject_name = ? AND scan_time = ?',
        whereArgs: <Object?>[
          result.studentOmrId,
          result.subjectName,
          scanTimeIso,
        ],
      );
      return;
    }

    await executor.delete(
      'scan_results',
      where: 'student_omr_id = ? AND subject_id = ? AND scan_time = ?',
      whereArgs: <Object?>[
        result.studentOmrId,
        result.subjectId,
        scanTimeIso,
      ],
    );
  }

  Future<void> _updateStoredScanResultReviewStatus(
    DatabaseExecutor executor,
    ScanResult result,
    bool needsReview,
  ) async {
    if (!needsReview) {
      await _promoteReviewedScanToStudent(executor, result);
      await _deleteOtherStoredSubjectScans(executor, result);
    }

    final values = <String, Object?>{
      'needs_review': needsReview ? 1 : 0,
      if (!needsReview) 'manually_confirmed': 1,
      'sync_status': SyncStatus.pending,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final scanTimeIso = result.scanTime.toIso8601String();
    if (result.subjectId == null) {
      await executor.update(
        'scan_results',
        values,
        where:
            'student_omr_id = ? AND subject_id IS NULL AND subject_name = ? AND scan_time = ?',
        whereArgs: <Object?>[
          result.studentOmrId,
          result.subjectName,
          scanTimeIso,
        ],
      );
      return;
    }

    await executor.update(
      'scan_results',
      values,
      where: 'student_omr_id = ? AND subject_id = ? AND scan_time = ?',
      whereArgs: <Object?>[
        result.studentOmrId,
        result.subjectId,
        scanTimeIso,
      ],
    );
  }

  void _replaceStudentInMemory(Student updatedStudent) {
    final index = globalStudentDatabase.indexWhere(
      (entry) => entry.omrId == updatedStudent.omrId,
    );
    if (index == -1) {
      globalStudentDatabase.add(updatedStudent);
    } else {
      globalStudentDatabase[index] = updatedStudent;
    }
    globalStudentIndex[updatedStudent.omrId] = updatedStudent;
  }

  void _upsertSectionInMemory(Section section) {
    final index =
        globalSections.indexWhere((entry) => entry.name == section.name);
    if (index == -1) {
      globalSections.add(section);
    } else {
      globalSections[index] = section;
    }
  }

  void _upsertSubjectInMemory(Subject subject) {
    final index = globalSubjects.indexWhere((entry) => entry.id == subject.id);
    if (index == -1) {
      globalSubjects.add(subject);
    } else {
      globalSubjects[index] = subject;
    }
  }

  void _renameSubjectResultsInMemory(String subjectId, String subjectName) {
    globalScanResults = globalScanResults.map((entry) {
      if (entry.subjectId != subjectId) {
        return entry;
      }
      return ScanResult(
        studentOmrId: entry.studentOmrId,
        subjectId: entry.subjectId,
        subjectName: subjectName,
        sheetId: entry.sheetId,
        detectedAnswers: entry.detectedAnswers,
        correctnessMap: entry.correctnessMap,
        score: entry.score,
        totalQuestions: entry.totalQuestions,
        confidence: entry.confidence,
        scanTime: entry.scanTime,
        scannedImagePath: entry.scannedImagePath,
        reviewReasons: entry.reviewReasons,
        flaggedQuestions: entry.flaggedQuestions,
        manuallyConfirmed: entry.manuallyConfirmed,
        needsReview: entry.needsReview,
        ownerTeacherId: entry.ownerTeacherId,
        cloudId: entry.cloudId,
        syncStatus: SyncStatus.pending,
        updatedAt: DateTime.now(),
      );
    }).toList();
    rebuildStudentIndex();
  }

  void _upsertTemplateInMemory(AnswerKeyTemplate template) {
    final index = globalAnswerKeyTemplates.indexWhere(
      (entry) => entry.id == template.id,
    );
    if (index == -1) {
      globalAnswerKeyTemplates.add(template);
    } else {
      globalAnswerKeyTemplates[index] = template;
    }
  }

  void _upsertDeadlineInMemory(Deadline deadline) {
    final index =
        globalDeadlines.indexWhere((entry) => entry.id == deadline.id);
    if (index == -1) {
      globalDeadlines.add(deadline);
    } else {
      globalDeadlines[index] = deadline;
    }
  }

  void _setScanReviewStatusInMemory(ScanResult result, bool needsReview) {
    result.needsReview = needsReview;
    if (!needsReview) {
      result.manuallyConfirmed = true;
      _promoteReviewedScanToStudentInMemory(result);
      globalScanResults.removeWhere(
        (entry) =>
            _matchesStudentSubject(entry, result) &&
            entry.scanTime != result.scanTime,
      );
    }
    for (final entry in globalScanResults) {
      if (_matchesScanIdentity(entry, result)) {
        entry.needsReview = needsReview;
        if (!needsReview) {
          entry.manuallyConfirmed = true;
        }
      }
    }
    rebuildStudentIndex();
  }

  Future<void> _promoteReviewedScanToStudent(
    DatabaseExecutor executor,
    ScanResult result,
  ) async {
    await executor.update(
      'students',
      <String, Object?>{
        'answers_json': jsonEncode(
          result.detectedAnswers.map((key, value) => MapEntry('$key', value)),
        ),
        'score': result.score,
        'confidence': result.confidence,
        'scan_date': result.scanTime.toIso8601String(),
        'sync_status': SyncStatus.pending,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'omr_id = ?',
      whereArgs: <Object?>[result.studentOmrId],
    );
  }

  void _promoteReviewedScanToStudentInMemory(ScanResult result) {
    final student = globalStudentIndex[result.studentOmrId];
    if (student == null) {
      return;
    }

    _replaceStudentInMemory(
      student.copyWith(
        score: result.score,
        answers: result.detectedAnswers,
        scanDate: result.scanTime,
        confidence: result.confidence,
      ),
    );
  }

  Future<void> _deleteOtherStoredSubjectScans(
    DatabaseExecutor executor,
    ScanResult result,
  ) async {
    final scanTimeIso = result.scanTime.toIso8601String();
    if (result.subjectId == null) {
      await executor.delete(
        'scan_results',
        where:
            'student_omr_id = ? AND subject_id IS NULL AND subject_name = ? AND scan_time != ?',
        whereArgs: <Object?>[
          result.studentOmrId,
          result.subjectName,
          scanTimeIso,
        ],
      );
      return;
    }

    await executor.delete(
      'scan_results',
      where: 'student_omr_id = ? AND subject_id = ? AND scan_time != ?',
      whereArgs: <Object?>[
        result.studentOmrId,
        result.subjectId,
        scanTimeIso,
      ],
    );
  }

  bool _matchesStudentSubject(ScanResult entry, ScanResult other) {
    return entry.studentOmrId == other.studentOmrId &&
        (entry.subjectId == other.subjectId ||
            (entry.subjectId == null &&
                other.subjectId == null &&
                entry.subjectName == other.subjectName));
  }

  bool _matchesScanIdentity(ScanResult entry, ScanResult other) {
    return entry.studentOmrId == other.studentOmrId &&
        entry.subjectId == other.subjectId &&
        entry.subjectName == other.subjectName &&
        entry.scanTime == other.scanTime;
  }

  _AppSnapshot _snapshotFromCurrentMemory() {
    final snapshot = _AppSnapshot(
      students: globalStudentDatabase
          .map((entry) => Student.fromJson(entry.toJson()))
          .toList(),
      sections: globalSections
          .map((entry) => Section.fromJson(entry.toJson()))
          .toList(),
      subjects: globalSubjects
          .map((entry) => Subject.fromJson(entry.toJson()))
          .toList(),
      scanResults: globalScanResults
          .map((entry) => ScanResult.fromJson(entry.toJson()))
          .toList(),
      deadlines: globalDeadlines
          .map((entry) => Deadline.fromJson(entry.toJson()))
          .toList(),
      exportRecords: globalExportRecords
          .map((entry) => ExportRecord.fromJson(entry.toJson()))
          .toList(),
      answerKeyTemplates: globalAnswerKeyTemplates
          .map((entry) => AnswerKeyTemplate.fromJson(entry.toJson()))
          .toList(),
      omrCounter: nextOmrIdValue,
      subjectCounter: nextSubjectCounterValue,
      sheetCounter: nextSheetCounterValue,
    );
    return _snapshotForCurrentTeacher(snapshot);
  }

  _AppSnapshot _snapshotFromBackupMap(Map<String, dynamic> decoded) {
    return _AppSnapshot(
      students: (decoded['students'] as List? ?? const <dynamic>[])
          .map((entry) => Student.fromJson(_asStringDynamicMap(entry)))
          .toList(),
      sections: (decoded['sections'] as List? ?? const <dynamic>[])
          .map((entry) => Section.fromJson(_asStringDynamicMap(entry)))
          .toList(),
      subjects: (decoded['subjects'] as List? ?? const <dynamic>[])
          .map((entry) => Subject.fromJson(_asStringDynamicMap(entry)))
          .toList(),
      scanResults: (decoded['scanResults'] as List? ?? const <dynamic>[])
          .map((entry) => ScanResult.fromJson(_asStringDynamicMap(entry)))
          .toList(),
      deadlines: (decoded['deadlines'] as List? ?? const <dynamic>[])
          .map((entry) => Deadline.fromJson(_asStringDynamicMap(entry)))
          .toList(),
      exportRecords: (decoded['exportRecords'] as List? ?? const <dynamic>[])
          .map((entry) => ExportRecord.fromJson(_asStringDynamicMap(entry)))
          .toList(),
      answerKeyTemplates:
          (decoded['answerKeyTemplates'] as List? ?? const <dynamic>[])
              .map(
                (entry) =>
                    AnswerKeyTemplate.fromJson(_asStringDynamicMap(entry)),
              )
              .toList(),
      omrCounter: _readCounter(decoded['omrCounter']),
      subjectCounter: _readCounter(decoded['subjectCounter']),
      sheetCounter: _readCounter(decoded['sheetCounter']),
    );
  }

  void _applySnapshotToMemory(_AppSnapshot snapshot) {
    globalStudentDatabase = snapshot.students;
    globalSections = snapshot.sections;
    globalSubjects = snapshot.subjects;
    globalScanResults = snapshot.scanResults;
    globalDeadlines = snapshot.deadlines;
    globalExportRecords = snapshot.exportRecords;
    globalAnswerKeyTemplates = snapshot.answerKeyTemplates;

    restoreCounters(
      omrCounter: snapshot.omrCounter,
      subjectCounter: snapshot.subjectCounter,
      sheetCounter: snapshot.sheetCounter,
    );

    rebuildStudentIndex();
  }

  static Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<T> _safeMapRows<T>(
    List<Map<String, Object?>> rows,
    T Function(Map<String, Object?> row) mapper, {
    required String label,
  }) {
    final mapped = <T>[];
    for (final row in rows) {
      try {
        mapped.add(mapper(row));
      } catch (error) {
        debugPrint('Skipping corrupt $label row: $error');
      }
    }
    return mapped;
  }

  static Map<String, dynamic>? _decodeJsonMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  static List<dynamic>? _decodeJsonList(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded;
    }
    return null;
  }

  static int _readCounter(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 1;
  }
}

class _AppSnapshot {
  const _AppSnapshot({
    required this.students,
    required this.sections,
    required this.subjects,
    required this.scanResults,
    required this.deadlines,
    required this.exportRecords,
    required this.answerKeyTemplates,
    required this.omrCounter,
    required this.subjectCounter,
    required this.sheetCounter,
  });

  final List<Student> students;
  final List<Section> sections;
  final List<Subject> subjects;
  final List<ScanResult> scanResults;
  final List<Deadline> deadlines;
  final List<ExportRecord> exportRecords;
  final List<AnswerKeyTemplate> answerKeyTemplates;
  final int omrCounter;
  final int subjectCounter;
  final int sheetCounter;
}

class PendingSyncSnapshot {
  const PendingSyncSnapshot({
    required this.sections,
    required this.students,
    required this.subjects,
    required this.scanResults,
    required this.deadlines,
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
}
