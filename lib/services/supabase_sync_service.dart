import 'dart:convert';

import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/cloud_snapshot.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/services/sync_preferences_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncSummary {
  const SyncSummary({
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

  int get total => sections + students + subjects + scanResults + deadlines;
}

class PullSummary {
  const PullSummary({
    required this.downloaded,
    required this.merged,
  });

  final int downloaded;
  final CloudMergeSummary merged;

  int get applied => merged.total;
}

class FullSyncSummary {
  const FullSyncSummary({
    required this.pull,
    required this.push,
  });

  final PullSummary pull;
  final SyncSummary push;
}

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseSyncService {
  SupabaseSyncService._();

  static final SupabaseSyncService instance = SupabaseSyncService._();

  Future<PullSummary> pullFromCloud() async {
    final client = SupabaseService.client;
    final ownerTeacherId = SupabaseService.currentUserId;
    if (client == null || ownerTeacherId == null) {
      throw const SyncException('Sign in before downloading cloud data.');
    }

    final cloud = await _fetchCloudSnapshot(client, ownerTeacherId);
    final merged = await LocalDataStore.instance.applyCloudSnapshot(cloud);
    await SyncPreferencesService.setLastPullAt(DateTime.now());

    return PullSummary(downloaded: cloud.total, merged: merged);
  }

  Future<FullSyncSummary> syncAll() async {
    final pull = await pullFromCloud();
    final push = await syncPending();
    await SyncPreferencesService.setLastSyncAt(DateTime.now());
    return FullSyncSummary(pull: pull, push: push);
  }

  Future<SyncSummary> syncPending() async {
    final client = SupabaseService.client;
    final ownerTeacherId = SupabaseService.currentUserId;
    if (client == null || ownerTeacherId == null) {
      throw const SyncException('Sign in before syncing.');
    }

    await LocalDataStore.instance.processPendingDeletions(client);
    final pending = await LocalDataStore.instance.fetchPendingSync();
    if (pending.total == 0) {
      return const SyncSummary(
        sections: 0,
        students: 0,
        subjects: 0,
        scanResults: 0,
        deadlines: 0,
      );
    }

    var sections = 0;
    var students = 0;
    var subjects = 0;
    var scanResults = 0;
    var deadlines = 0;

    for (final section in pending.sections) {
      if (section.ownerTeacherId != null &&
          section.ownerTeacherId != ownerTeacherId) {
        continue;
      }
      final cloudId = await _upsertSection(client, ownerTeacherId, section);
      await LocalDataStore.instance.markSectionSynced(
        name: section.name,
        cloudId: cloudId,
      );
      sections++;
    }

    for (final student in pending.students) {
      if (student.ownerTeacherId != null &&
          student.ownerTeacherId != ownerTeacherId) {
        continue;
      }
      final cloudId = await _upsertStudent(client, ownerTeacherId, student);
      await LocalDataStore.instance.markStudentSynced(
        omrId: student.omrId,
        cloudId: cloudId,
      );
      students++;
    }

    final subjectCloudIds = <String, String>{};
    for (final subject in pending.subjects) {
      if (subject.ownerTeacherId != null &&
          subject.ownerTeacherId != ownerTeacherId) {
        continue;
      }
      final cloudId = await _upsertSubject(client, ownerTeacherId, subject);
      subjectCloudIds[subject.id] = cloudId;
      await LocalDataStore.instance.markSubjectSynced(
        localId: subject.id,
        cloudId: cloudId,
      );
      subjects++;
    }

    for (final result in pending.scanResults) {
      if (result.ownerTeacherId != null &&
          result.ownerTeacherId != ownerTeacherId) {
        continue;
      }
      final cloudSubjectId = result.subjectId == null
          ? null
          : subjectCloudIds[result.subjectId!] ??
              _findSubjectCloudId(result.subjectId!);
      final cloudId = await _insertOrUpdateScanResult(
        client,
        ownerTeacherId,
        result,
        cloudSubjectId,
      );
      await LocalDataStore.instance.markScanResultSynced(
        result: result,
        cloudId: cloudId,
      );
      scanResults++;
    }

    for (final deadline in pending.deadlines) {
      if (deadline.ownerTeacherId != null &&
          deadline.ownerTeacherId != ownerTeacherId) {
        continue;
      }
      final cloudSubjectId = deadline.subjectId == null
          ? null
          : subjectCloudIds[deadline.subjectId!] ??
              _findSubjectCloudId(deadline.subjectId!);
      final cloudId = await _upsertDeadline(
        client,
        ownerTeacherId,
        deadline,
        cloudSubjectId,
      );
      await LocalDataStore.instance.markDeadlineSynced(
        localId: deadline.id,
        cloudId: cloudId,
      );
      deadlines++;
    }

    await LocalDataStore.instance.reloadFromDatabase();
    await SyncPreferencesService.setLastSyncAt(DateTime.now());

    return SyncSummary(
      sections: sections,
      students: students,
      subjects: subjects,
      scanResults: scanResults,
      deadlines: deadlines,
    );
  }

  Future<CloudPullSnapshot> _fetchCloudSnapshot(
    SupabaseClient client,
    String ownerTeacherId,
  ) async {
    final sectionsResponse = await client
        .from('sections')
        .select()
        .eq('owner_teacher_id', ownerTeacherId);
    final studentsResponse = await client
        .from('students')
        .select()
        .eq('owner_teacher_id', ownerTeacherId);
    final subjectsResponse = await client
        .from('subjects')
        .select()
        .eq('owner_teacher_id', ownerTeacherId);
    final scanResultsResponse = await client
        .from('scan_results')
        .select()
        .eq('owner_teacher_id', ownerTeacherId);
    final deadlinesResponse = await client
        .from('deadlines')
        .select()
        .eq('owner_teacher_id', ownerTeacherId);

    return CloudPullSnapshot(
      sections: _mapRows(sectionsResponse, _sectionFromCloudRow),
      students: _mapRows(studentsResponse, _studentFromCloudRow),
      subjects: _mapRows(subjectsResponse, _subjectFromCloudRow),
      scanResults: _mapRows(scanResultsResponse, _scanResultFromCloudRow),
      deadlines: _mapRows(deadlinesResponse, _deadlineFromCloudRow),
    );
  }

  List<T> _mapRows<T>(
    dynamic response,
    T Function(Map<String, dynamic> row) mapper,
  ) {
    if (response is! List) {
      return <T>[];
    }

    return response
        .whereType<Map>()
        .map((row) => mapper(Map<String, dynamic>.from(row)))
        .toList();
  }

  Section _sectionFromCloudRow(Map<String, dynamic> row) {
    return Section(
      name: row['name']?.toString() ?? '',
      teacher: row['teacher']?.toString(),
      studentCount: row['student_count'] as int?,
      ownerTeacherId: row['owner_teacher_id']?.toString(),
      cloudId: row['id']?.toString(),
      syncStatus: SyncStatus.synced,
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  Student _studentFromCloudRow(Map<String, dynamic> row) {
    return Student(
      schoolId: row['school_id']?.toString() ?? '',
      omrId: row['omr_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      section: row['section_name']?.toString() ?? '',
      score: (row['score'] as num?)?.toDouble(),
      answers: _parseIntStringMap(row['answers']),
      scanDate: _parseDate(row['scan_date']),
      confidence: (row['confidence'] as num?)?.toDouble(),
      ownerTeacherId: row['owner_teacher_id']?.toString(),
      cloudId: row['id']?.toString(),
      syncStatus: SyncStatus.synced,
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  Subject _subjectFromCloudRow(Map<String, dynamic> row) {
    return Subject(
      id: row['local_id']?.toString(),
      name: row['name']?.toString() ?? '',
      answerKey: _parseAnswerKey(row['answer_key']),
      totalQuestions: row['total_questions'] as int? ?? 50,
      sectionNames: (row['section_names'] as List?)
          ?.map((entry) => entry.toString())
          .toList(),
      sectionQrData: _parseStringStringMap(row['section_qr_data']),
      examDate: _parseDate(row['exam_date']),
      passingScore: row['passing_score'] as int?,
      usePartialCredit: row['use_partial_credit'] == true,
      ownerTeacherId: row['owner_teacher_id']?.toString(),
      cloudId: row['id']?.toString(),
      syncStatus: SyncStatus.synced,
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  ScanResult _scanResultFromCloudRow(Map<String, dynamic> row) {
    return ScanResult(
      studentOmrId: row['student_omr_id']?.toString() ?? '',
      subjectId: row['subject_local_id']?.toString(),
      subjectName: row['subject_name']?.toString() ?? '',
      sheetId: row['sheet_id']?.toString(),
      detectedAnswers: _parseIntStringMap(row['detected_answers']) ?? {},
      correctnessMap: _parseIntDoubleMap(row['correctness_map']) ?? {},
      score: (row['score'] as num?)?.toDouble() ?? 0,
      totalQuestions: row['total_questions'] as int? ?? 0,
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
      scanTime: _parseDate(row['scan_time']) ?? DateTime.now(),
      scannedImagePath: null,
      reviewReasons: (row['review_reasons'] as List? ?? const <dynamic>[])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(),
      flaggedQuestions:
          (row['flagged_questions'] as List? ?? const <dynamic>[])
              .map((entry) => entry is int ? entry : int.tryParse('$entry'))
              .whereType<int>()
              .toList(),
      manuallyConfirmed: row['manually_confirmed'] == true,
      needsReview: row['needs_review'] == true,
      ownerTeacherId: row['owner_teacher_id']?.toString(),
      cloudId: row['id']?.toString(),
      syncStatus: SyncStatus.synced,
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  Deadline _deadlineFromCloudRow(Map<String, dynamic> row) {
    return Deadline(
      id: row['local_id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      sectionName: row['section_name']?.toString(),
      subjectId: row['subject_local_id']?.toString(),
      dueDate: _parseDate(row['due_date']) ?? DateTime.now(),
      ownerTeacherId: row['owner_teacher_id']?.toString(),
      cloudId: row['id']?.toString(),
      syncStatus: SyncStatus.synced,
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
      isCompleted: row['is_completed'] == true,
    );
  }

  String? _findSubjectCloudId(String localSubjectId) {
    for (final subject in globalSubjects) {
      if (subject.id == localSubjectId) {
        return subject.cloudId;
      }
    }
    return null;
  }

  Future<String> _upsertSection(
    SupabaseClient client,
    String ownerTeacherId,
    Section section,
  ) async {
    final row = <String, Object?>{
      'owner_teacher_id': ownerTeacherId,
      'name': section.name,
      'teacher': section.teacher,
      'student_count': section.studentCount,
      'local_id': section.name,
      'sync_status': SyncStatus.synced,
      'updated_at': section.updatedAt.toIso8601String(),
    };
    final response = await client
        .from('sections')
        .upsert(row, onConflict: 'owner_teacher_id,name')
        .select('id')
        .single();
    return response['id'].toString();
  }

  Future<String> _upsertStudent(
    SupabaseClient client,
    String ownerTeacherId,
    Student student,
  ) async {
    final row = <String, Object?>{
      'owner_teacher_id': ownerTeacherId,
      'school_id': student.schoolId,
      'omr_id': student.omrId,
      'name': student.name,
      'section_name': student.section,
      'score': student.score,
      'answers': _jsonMapOrNull(student.answers),
      'scan_date': student.scanDate?.toIso8601String(),
      'confidence': student.confidence,
      'local_id': student.omrId,
      'sync_status': SyncStatus.synced,
      'updated_at': student.updatedAt.toIso8601String(),
    };
    final response = await client
        .from('students')
        .upsert(row, onConflict: 'owner_teacher_id,omr_id')
        .select('id')
        .single();
    return response['id'].toString();
  }

  Future<String> _upsertSubject(
    SupabaseClient client,
    String ownerTeacherId,
    Subject subject,
  ) async {
    final row = <String, Object?>{
      'owner_teacher_id': ownerTeacherId,
      'local_id': subject.id,
      'name': subject.name,
      'answer_key': _jsonMap(subject.answerKey),
      'total_questions': subject.totalQuestions,
      'section_names': subject.sectionNames,
      'section_qr_data': subject.sectionQrData,
      'exam_date': subject.examDate?.toIso8601String().split('T').first,
      'passing_score': subject.passingScore,
      'use_partial_credit': subject.usePartialCredit,
      'sync_status': SyncStatus.synced,
      'updated_at': subject.updatedAt.toIso8601String(),
    };
    final response = await client
        .from('subjects')
        .upsert(row, onConflict: 'owner_teacher_id,local_id')
        .select('id')
        .single();
    return response['id'].toString();
  }

  Future<String> _insertOrUpdateScanResult(
    SupabaseClient client,
    String ownerTeacherId,
    ScanResult result,
    String? cloudSubjectId,
  ) async {
    final row = <String, Object?>{
      'owner_teacher_id': ownerTeacherId,
      'student_omr_id': result.studentOmrId,
      'subject_id': cloudSubjectId,
      'subject_local_id': result.subjectId,
      'subject_name': result.subjectName,
      'sheet_id': result.sheetId,
      'detected_answers': _jsonMap(result.detectedAnswers),
      'correctness_map': _jsonMap(result.correctnessMap),
      'score': result.score,
      'total_questions': result.totalQuestions,
      'confidence': result.confidence,
      'scan_time': result.scanTime.toIso8601String(),
      'scanned_image_path': null,
      'review_reasons': result.reviewReasons,
      'flagged_questions': result.flaggedQuestions,
      'manually_confirmed': result.manuallyConfirmed,
      'needs_review': result.needsReview,
      'local_id': _scanLocalId(result),
      'sync_status': SyncStatus.synced,
      'updated_at': result.updatedAt.toIso8601String(),
    };

    if (result.cloudId != null && result.cloudId!.isNotEmpty) {
      final response = await client
          .from('scan_results')
          .update(row)
          .eq('id', result.cloudId!)
          .select('id')
          .single();
      return response['id'].toString();
    }

    final response =
        await client.from('scan_results').insert(row).select('id').single();
    return response['id'].toString();
  }

  Future<String> _upsertDeadline(
    SupabaseClient client,
    String ownerTeacherId,
    Deadline deadline,
    String? cloudSubjectId,
  ) async {
    final row = <String, Object?>{
      'owner_teacher_id': ownerTeacherId,
      'local_id': deadline.id,
      'title': deadline.title,
      'section_name': deadline.sectionName,
      'subject_id': cloudSubjectId,
      'subject_local_id': deadline.subjectId,
      'due_date': deadline.dueDate.toIso8601String(),
      'is_completed': deadline.isCompleted,
      'sync_status': SyncStatus.synced,
      'updated_at': deadline.updatedAt.toIso8601String(),
    };
    final response = await client
        .from('deadlines')
        .upsert(row, onConflict: 'owner_teacher_id,local_id')
        .select('id')
        .single();
    return response['id'].toString();
  }

  String _scanLocalId(ScanResult result) {
    final subject = result.subjectId ?? result.subjectName;
    return '${result.studentOmrId}|$subject|${result.scanTime.toIso8601String()}';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  Map<int, String>? _parseIntStringMap(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final parsed = <int, String>{};
    raw.forEach((key, value) {
      final question = int.tryParse(key.toString());
      if (question != null) {
        parsed[question] = value?.toString() ?? '';
      }
    });
    return parsed.isEmpty ? null : parsed;
  }

  Map<int, double>? _parseIntDoubleMap(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final parsed = <int, double>{};
    raw.forEach((key, value) {
      final question = int.tryParse(key.toString());
      if (question == null) {
        return;
      }
      if (value is num) {
        parsed[question] = value.toDouble();
      } else if (value == true) {
        parsed[question] = 1.0;
      } else if (value == false) {
        parsed[question] = 0.0;
      }
    });
    return parsed.isEmpty ? null : parsed;
  }

  Map<String, String> _parseStringStringMap(dynamic raw) {
    if (raw is! Map) {
      return <String, String>{};
    }

    return raw.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  Map<int, dynamic> _parseAnswerKey(dynamic raw) {
    if (raw is! Map) {
      return <int, dynamic>{};
    }

    final parsed = <int, dynamic>{};
    raw.forEach((key, value) {
      final question = int.tryParse(key.toString());
      if (question != null) {
        parsed[question] = value;
      }
    });
    return parsed;
  }

  Object _jsonMap(Map<dynamic, dynamic> value) {
    return jsonDecode(jsonEncode(value.map(
      (key, entry) => MapEntry(key.toString(), entry),
    )));
  }

  Object? _jsonMapOrNull(Map<dynamic, dynamic>? value) {
    if (value == null) {
      return null;
    }
    return _jsonMap(value);
  }
}
