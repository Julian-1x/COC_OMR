final RegExp _storedAnswerPattern = RegExp(r'[A-E]');

String formatScoreValue(num? score) {
  if (score == null) {
    return '';
  }

  final value = score.toDouble();
  if (value == value.floorToDouble()) {
    return value.toInt().toString();
  }

  return value.toStringAsFixed(1);
}

List<String> parseStoredAnswerSelections(String? rawAnswer) {
  if (rawAnswer == null || rawAnswer.trim().isEmpty) {
    return const <String>[];
  }

  final selections = <String>[];
  for (final match
      in _storedAnswerPattern.allMatches(rawAnswer.toUpperCase())) {
    final token = match.group(0);
    if (token != null && !selections.contains(token)) {
      selections.add(token);
    }
  }

  return selections;
}

String serializeStoredAnswerSelections(Iterable<String> answers) {
  final normalized = answers
      .map((answer) => answer.trim().toUpperCase())
      .where((answer) => answer.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  return normalized.join(',');
}

class SyncStatus {
  static const String pending = 'pending';
  static const String synced = 'synced';
  static const String conflict = 'conflict';
  static const String deleted = 'deleted';
}

class Student {
  String schoolId;
  String omrId;
  String name;
  String section;
  double? score;
  Map<int, String>? answers; // Store which answers student selected
  DateTime? scanDate;
  double? confidence; // How confident the scan was
  String? ownerTeacherId;
  String? cloudId;
  String syncStatus;
  DateTime updatedAt;

  Student({
    required this.schoolId,
    required this.omrId,
    required this.name,
    required this.section,
    this.score,
    this.answers,
    this.scanDate,
    this.confidence,
    this.ownerTeacherId,
    this.cloudId,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now() {
    // Validation
    assert(omrId.length == 4, 'OMR ID must be 4 digits');
    assert(schoolId.isNotEmpty, 'School ID required');
    assert(name.isNotEmpty, 'Name required');
    assert(section.isNotEmpty, 'Section required');
  }

  // Copy with method for updates
  Student copyWith({
    String? schoolId,
    String? omrId,
    String? name,
    String? section,
    double? score,
    Map<int, String>? answers,
    DateTime? scanDate,
    double? confidence,
    String? ownerTeacherId,
    String? cloudId,
    String? syncStatus,
    DateTime? updatedAt,
  }) {
    return Student(
      schoolId: schoolId ?? this.schoolId,
      omrId: omrId ?? this.omrId,
      name: name ?? this.name,
      section: section ?? this.section,
      score: score ?? this.score,
      answers: answers ?? this.answers,
      scanDate: scanDate ?? this.scanDate,
      confidence: confidence ?? this.confidence,
      ownerTeacherId: ownerTeacherId ?? this.ownerTeacherId,
      cloudId: cloudId ?? this.cloudId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasScore => score != null;
  String get scoreDisplay => formatScoreValue(score);

  Map<String, dynamic> toJson() {
    return {
      'schoolId': schoolId,
      'omrId': omrId,
      'name': name,
      'section': section,
      'score': score,
      'answers': answers?.map((key, value) => MapEntry('$key', value)),
      'scanDate': scanDate?.toIso8601String(),
      'confidence': confidence,
      'ownerTeacherId': ownerTeacherId,
      'cloudId': cloudId,
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Student.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'];
    final parsedAnswers = rawAnswers is Map
        ? rawAnswers.map<int, String>(
            (key, value) => MapEntry(
              int.tryParse(key.toString()) ?? 0,
              value?.toString() ?? '',
            ),
          )
        : null;
    parsedAnswers?.remove(0);

    return Student(
      schoolId: json['schoolId']?.toString() ?? '',
      omrId: json['omrId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      section: json['section']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble(),
      answers: parsedAnswers,
      scanDate: json['scanDate'] == null
          ? null
          : DateTime.tryParse(json['scanDate'].toString()),
      confidence: (json['confidence'] as num?)?.toDouble(),
      ownerTeacherId: json['ownerTeacherId']?.toString(),
      cloudId: json['cloudId']?.toString(),
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class Section {
  String name;
  String? teacher;
  int? studentCount;
  String? ownerTeacherId;
  String? cloudId;
  String syncStatus;
  DateTime updatedAt;

  Section({
    required this.name,
    this.teacher,
    this.studentCount,
    this.ownerTeacherId,
    this.cloudId,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'teacher': teacher,
      'studentCount': studentCount,
      'ownerTeacherId': ownerTeacherId,
      'cloudId': cloudId,
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      name: json['name']?.toString() ?? '',
      teacher: json['teacher']?.toString(),
      studentCount: json['studentCount'] as int?,
      ownerTeacherId: json['ownerTeacherId']?.toString(),
      cloudId: json['cloudId']?.toString(),
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class Subject {
  final String id;
  String name;
  Map<int, List<String>> answerKey;
  int totalQuestions;
  List<String>? sectionNames;
  Map<String, String> sectionQrData;
  DateTime? examDate;
  int passingScore;
  bool usePartialCredit; // Enable partial credit for multi-answer questions
  String? ownerTeacherId;
  String? cloudId;
  String syncStatus;
  DateTime updatedAt;

  Subject({
    String? id,
    required this.name,
    required Map<int, dynamic> answerKey,
    this.totalQuestions = 50,
    this.sectionNames,
    Map<String, String>? sectionQrData,
    this.examDate,
    int? passingScore,
    this.usePartialCredit = false,
    this.ownerTeacherId,
    this.cloudId,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  })  : id = id ?? generateUniqueSubjectId(),
        answerKey = _normalizeAnswerKey(answerKey),
        sectionQrData = sectionQrData ?? <String, String>{},
        passingScore = passingScore ?? (totalQuestions * 0.6).round(),
        updatedAt = updatedAt ?? DateTime.now();

  String get normalizedName => name.trim().toUpperCase();
  String get displayName => name;

  Subject copyWith({
    String? name,
    Map<int, List<String>>? answerKey,
    int? totalQuestions,
    List<String>? sectionNames,
    Map<String, String>? sectionQrData,
    DateTime? examDate,
    int? passingScore,
    bool? usePartialCredit,
    String? ownerTeacherId,
    String? cloudId,
    String? syncStatus,
    DateTime? updatedAt,
  }) {
    return Subject(
      id: id,
      name: name ?? this.name,
      answerKey: answerKey ?? this.answerKey,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      sectionNames: sectionNames ?? this.sectionNames,
      sectionQrData: sectionQrData ?? this.sectionQrData,
      examDate: examDate ?? this.examDate,
      passingScore: passingScore ?? this.passingScore,
      usePartialCredit: usePartialCredit ?? this.usePartialCredit,
      ownerTeacherId: ownerTeacherId ?? this.ownerTeacherId,
      cloudId: cloudId ?? this.cloudId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  int calculateScore(Map<int, String> studentAnswers) {
    double correct = 0;
    studentAnswers.forEach((question, answer) {
      correct += calculateQuestionScore(question, answer);
    });
    return correct.round();
  }

  bool allowsMultipleAnswers(int question) =>
      (answerKey[question]?.length ?? 0) > 1;

  double calculateQuestionScore(int question, String? storedAnswer) {
    return calculateQuestionScoreFromSelections(
      question,
      parseStoredAnswerSelections(storedAnswer),
    );
  }

  double calculateQuestionScoreFromSelections(
    int question,
    Iterable<String> selectedAnswers,
  ) {
    final correctAnswers = answerKey[question] ?? const <String>[];
    if (correctAnswers.isEmpty) {
      return 0.0;
    }

    final normalizedSelected = selectedAnswers
        .map((answer) => answer.trim().toUpperCase())
        .where((answer) => answer.isNotEmpty)
        .toSet();
    if (normalizedSelected.isEmpty) {
      return 0.0;
    }

    final normalizedCorrect = correctAnswers.toSet();
    final correctSelections =
        normalizedSelected.intersection(normalizedCorrect).length;
    final incorrectSelections =
        normalizedSelected.difference(normalizedCorrect).length;

    if (!usePartialCredit || correctAnswers.length == 1) {
      return correctSelections == normalizedCorrect.length &&
              incorrectSelections == 0
          ? 1.0
          : 0.0;
    }

    final partialScore =
        (correctSelections - incorrectSelections) / correctAnswers.length;
    return partialScore.clamp(0.0, 1.0);
  }

  /// Calculate score with partial credit support
  /// Returns a double for partial credit (e.g., 0.5 for half credit)
  double calculateScoreWithPartialCredit(
      Map<int, List<String>> studentAnswers) {
    double score = 0.0;
    studentAnswers.forEach((question, selectedAnswers) {
      score += calculateQuestionScoreFromSelections(question, selectedAnswers);
    });

    return score;
  }

  /// Smart score calculation - uses partial credit if enabled
  /// Takes single-answer map (from scanner) and returns appropriate score
  double calculateSmartScore(Map<int, String> studentAnswers) {
    double score = 0.0;
    studentAnswers.forEach((question, answer) {
      score += calculateQuestionScore(question, answer);
    });
    return score;
  }

  bool isCorrect(int question, String answer) {
    return calculateQuestionScore(question, answer) == 1.0;
  }

  static Map<int, List<String>> _normalizeAnswerKey(Map<int, dynamic> raw) {
    final normalized = <int, List<String>>{};

    raw.forEach((question, value) {
      final answers = <String>[];

      if (value is Iterable) {
        for (final entry in value) {
          final normalizedEntry = entry?.toString().trim().toUpperCase() ?? '';
          if (normalizedEntry.isNotEmpty &&
              !answers.contains(normalizedEntry)) {
            answers.add(normalizedEntry);
          }
        }
      } else {
        final normalizedEntry = value?.toString().trim().toUpperCase() ?? '';
        if (normalizedEntry.isNotEmpty) {
          answers.add(normalizedEntry);
        }
      }

      if (answers.isNotEmpty) {
        normalized[question] = answers;
      }
    });

    return normalized;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'answerKey': answerKey.map((key, value) => MapEntry('$key', value)),
      'totalQuestions': totalQuestions,
      'sectionNames': sectionNames,
      'sectionQrData': sectionQrData,
      'examDate': examDate?.toIso8601String(),
      'passingScore': passingScore,
      'usePartialCredit': usePartialCredit,
      'ownerTeacherId': ownerTeacherId,
      'cloudId': cloudId,
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Subject.fromJson(Map<String, dynamic> json) {
    final rawAnswerKey = json['answerKey'];
    final mappedAnswerKey = <int, dynamic>{};

    if (rawAnswerKey is Map) {
      rawAnswerKey.forEach((key, value) {
        final parsedKey = int.tryParse(key.toString());
        if (parsedKey != null) {
          mappedAnswerKey[parsedKey] = value;
        }
      });
    }

    return Subject(
      id: json['id']?.toString(),
      name: json['name']?.toString() ?? '',
      answerKey: mappedAnswerKey,
      totalQuestions: json['totalQuestions'] as int? ?? 50,
      sectionNames: (json['sectionNames'] as List?)
          ?.map((entry) => entry.toString())
          .toList(),
      sectionQrData: (json['sectionQrData'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString())),
      examDate: json['examDate'] == null
          ? null
          : DateTime.tryParse(json['examDate'].toString()),
      passingScore: json['passingScore'] as int?,
      usePartialCredit: json['usePartialCredit'] as bool? ?? false,
      ownerTeacherId: json['ownerTeacherId']?.toString(),
      cloudId: json['cloudId']?.toString(),
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ScanResult {
  final String studentOmrId;
  final String? subjectId;
  final String subjectName;
  final String? sheetId;
  final Map<int, String> detectedAnswers;
  final Map<int, double> correctnessMap; // Earned credit per question (0.0-1.0)
  final double score; // Changed to double for partial credit support
  final int totalQuestions;
  final double confidence;
  final DateTime scanTime;
  final String? scannedImagePath;
  final List<String> reviewReasons;
  final List<int> flaggedQuestions;
  bool manuallyConfirmed;
  bool needsReview; // Mutable - can be flagged for review
  final String? ownerTeacherId;
  final String? cloudId;
  final String syncStatus;
  final DateTime updatedAt;

  ScanResult({
    required this.studentOmrId,
    this.subjectId,
    required this.subjectName,
    this.sheetId,
    required this.detectedAnswers,
    required this.correctnessMap,
    required num score, // Accept both int and double
    required this.totalQuestions,
    required this.confidence,
    required this.scanTime,
    this.scannedImagePath,
    List<String>? reviewReasons,
    List<int>? flaggedQuestions,
    this.manuallyConfirmed = false,
    this.needsReview = false,
    this.ownerTeacherId,
    this.cloudId,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
  })  : score = score.toDouble(),
        reviewReasons = List.unmodifiable(reviewReasons ?? const <String>[]),
        flaggedQuestions = List.unmodifiable(flaggedQuestions ?? const <int>[]),
        updatedAt = updatedAt ?? DateTime.now();

  // Low confidence threshold
  bool get isLowConfidence => confidence < 0.7;
  bool get requiresReview =>
      needsReview ||
      (!manuallyConfirmed && (reviewReasons.isNotEmpty || isLowConfidence));

  /// Returns the integer score (rounded down) for display
  int get scoreInt => score.floor();

  /// Returns true if score has decimal part (partial credit was applied)
  bool get hasPartialCredit => score != score.floorToDouble();

  /// Formatted score string (e.g., "42" or "42.5")
  String get scoreDisplay => formatScoreValue(score);

  double get percentage => (score / totalQuestions) * 100;
  bool get passed => percentage >= 60;

  Map<String, dynamic> toJson() {
    return {
      'studentOmrId': studentOmrId,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'sheetId': sheetId,
      'detectedAnswers':
          detectedAnswers.map((key, value) => MapEntry('$key', value)),
      'correctnessMap':
          correctnessMap.map((key, value) => MapEntry('$key', value)),
      'score': score,
      'totalQuestions': totalQuestions,
      'confidence': confidence,
      'scanTime': scanTime.toIso8601String(),
      'scannedImagePath': scannedImagePath,
      'reviewReasons': reviewReasons,
      'flaggedQuestions': flaggedQuestions,
      'manuallyConfirmed': manuallyConfirmed,
      'needsReview': needsReview,
      'ownerTeacherId': ownerTeacherId,
      'cloudId': cloudId,
      'syncStatus': syncStatus,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    final rawDetectedAnswers = json['detectedAnswers'];
    final rawCorrectnessMap = json['correctnessMap'];

    final detectedAnswers = rawDetectedAnswers is Map
        ? rawDetectedAnswers.map<int, String>(
            (key, value) => MapEntry(
              int.tryParse(key.toString()) ?? 0,
              value?.toString() ?? '',
            ),
          )
        : <int, String>{};
    detectedAnswers.remove(0);

    final correctnessMap = rawCorrectnessMap is Map
        ? rawCorrectnessMap.map<int, double>(
            (key, value) => MapEntry(
              int.tryParse(key.toString()) ?? 0,
              value is num
                  ? value.toDouble()
                  : value == true
                      ? 1.0
                      : 0.0,
            ),
          )
        : <int, double>{};
    correctnessMap.remove(0);

    return ScanResult(
      studentOmrId: json['studentOmrId']?.toString() ?? '',
      subjectId: json['subjectId']?.toString(),
      subjectName: json['subjectName']?.toString() ?? '',
      sheetId: json['sheetId']?.toString(),
      detectedAnswers: detectedAnswers,
      correctnessMap: correctnessMap,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      totalQuestions: json['totalQuestions'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      scanTime: DateTime.tryParse(json['scanTime']?.toString() ?? '') ??
          DateTime.now(),
      scannedImagePath: json['scannedImagePath']?.toString(),
      reviewReasons: (json['reviewReasons'] as List? ?? const <dynamic>[])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(),
      flaggedQuestions: (json['flaggedQuestions'] as List? ?? const <dynamic>[])
          .map((entry) => entry is int ? entry : int.tryParse(entry.toString()))
          .whereType<int>()
          .toList(),
      manuallyConfirmed: json['manuallyConfirmed'] == true,
      needsReview: json['needsReview'] == true,
      ownerTeacherId: json['ownerTeacherId']?.toString(),
      cloudId: json['cloudId']?.toString(),
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Deadline for grading tasks
class Deadline {
  final String id;
  final String title;
  final String? sectionName;
  final String? subjectId;
  final DateTime dueDate;
  final String? ownerTeacherId;
  final String? cloudId;
  final String syncStatus;
  final DateTime updatedAt;
  bool isCompleted;

  Deadline({
    required this.id,
    required this.title,
    this.sectionName,
    this.subjectId,
    required this.dueDate,
    this.ownerTeacherId,
    this.cloudId,
    this.syncStatus = SyncStatus.pending,
    DateTime? updatedAt,
    this.isCompleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  int get daysRemaining {
    final now = DateTime.now();
    final diff = dueDate.difference(now);
    return diff.inDays;
  }

  bool get isOverdue => daysRemaining < 0 && !isCompleted;
  bool get isDueSoon =>
      daysRemaining <= 3 && daysRemaining >= 0 && !isCompleted;

  Deadline copyWith({
    String? title,
    String? sectionName,
    String? subjectId,
    DateTime? dueDate,
    String? ownerTeacherId,
    String? cloudId,
    String? syncStatus,
    DateTime? updatedAt,
    bool? isCompleted,
  }) {
    return Deadline(
      id: id,
      title: title ?? this.title,
      sectionName: sectionName ?? this.sectionName,
      subjectId: subjectId ?? this.subjectId,
      dueDate: dueDate ?? this.dueDate,
      ownerTeacherId: ownerTeacherId ?? this.ownerTeacherId,
      cloudId: cloudId ?? this.cloudId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sectionName': sectionName,
        'subjectId': subjectId,
        'dueDate': dueDate.toIso8601String(),
        'isCompleted': isCompleted,
        'ownerTeacherId': ownerTeacherId,
        'cloudId': cloudId,
        'syncStatus': syncStatus,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Deadline.fromJson(Map<String, dynamic> json) => Deadline(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        sectionName: json['sectionName']?.toString(),
        subjectId: json['subjectId']?.toString(),
        dueDate: DateTime.tryParse(json['dueDate']?.toString() ?? '') ??
            DateTime.now(),
        ownerTeacherId: json['ownerTeacherId']?.toString(),
        cloudId: json['cloudId']?.toString(),
        syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        isCompleted: json['isCompleted'] == true,
      );
}

/// Track export history per section
class ExportRecord {
  final String sectionName;
  final DateTime exportedAt;

  ExportRecord({required this.sectionName, required this.exportedAt});

  Map<String, dynamic> toJson() => {
        'sectionName': sectionName,
        'exportedAt': exportedAt.toIso8601String(),
      };

  factory ExportRecord.fromJson(Map<String, dynamic> json) => ExportRecord(
        sectionName: json['sectionName']?.toString() ?? '',
        exportedAt: DateTime.tryParse(json['exportedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

// GLOBAL DATABASES
List<Student> globalStudentDatabase = [];
List<Section> globalSections = [];
List<Subject> globalSubjects = [];
List<ScanResult> globalScanResults = [];
List<Deadline> globalDeadlines = [];
List<ExportRecord> globalExportRecords = [];

// INDEXED LOOKUPS for O(1) performance
Map<String, Student> globalStudentIndex = {};
Map<String, List<ScanResult>> globalScansByStudent = {};
Map<String, List<ScanResult>> globalScansBySubject = {};

/// Rebuild all indexes after data changes
void rebuildStudentIndex() {
  globalStudentIndex = {for (final s in globalStudentDatabase) s.omrId: s};
  globalScansByStudent = {};
  globalScansBySubject = {};

  for (final result in globalScanResults) {
    globalScansByStudent.putIfAbsent(result.studentOmrId, () => []).add(result);
    if (result.subjectId != null) {
      globalScansBySubject.putIfAbsent(result.subjectId!, () => []).add(result);
    }
  }
}

/// Add a student and update index
void addStudent(Student student) {
  globalStudentDatabase.add(student);
  globalStudentIndex[student.omrId] = student;
}

/// Add a scan result and update indexes
void addScanResult(ScanResult result) {
  globalScanResults.add(result);
  globalScansByStudent.putIfAbsent(result.studentOmrId, () => []).add(result);
  if (result.subjectId != null) {
    globalScansBySubject.putIfAbsent(result.subjectId!, () => []).add(result);
  }
}

/// Find student by OMR ID - O(1)
Student? findStudentByOmrId(String omrId) => globalStudentIndex[omrId];

/// Find scans for a student - O(1)
List<ScanResult> findScansByStudent(String omrId) =>
    globalScansByStudent[omrId] ?? [];

/// Find scans for a subject - O(1)
List<ScanResult> findScansBySubject(String subjectId) =>
    globalScansBySubject[subjectId] ?? [];

class SubjectDeletionSummary {
  const SubjectDeletionSummary({
    required this.removedSubjects,
    required this.removedScans,
    required this.removedDeadlines,
    required this.affectedStudents,
  });

  final int removedSubjects;
  final int removedScans;
  final int removedDeadlines;
  final int affectedStudents;
}

/// Canonical section name used across roster import and class management.
String normalizeSectionName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

class SectionDeletionSummary {
  const SectionDeletionSummary({
    required this.removedStudents,
    required this.removedScans,
    required this.removedDeadlines,
    required this.removedSection,
  });

  final int removedStudents;
  final int removedScans;
  final int removedDeadlines;
  final bool removedSection;
}

class SectionRenameSummary {
  const SectionRenameSummary({
    required this.updatedStudents,
    required this.updatedSubjects,
    required this.updatedDeadlines,
  });

  final int updatedStudents;
  final int updatedSubjects;
  final int updatedDeadlines;
}

class SectionMergeSummary {
  const SectionMergeSummary({
    required this.movedStudents,
    required this.updatedSubjects,
    required this.updatedDeadlines,
  });

  final int movedStudents;
  final int updatedSubjects;
  final int updatedDeadlines;
}

class StudentRemovalSummary {
  const StudentRemovalSummary({
    required this.removedScans,
  });

  final int removedScans;
}

void _refreshStudentSnapshotFromLatestScan(String omrId) {
  final studentIndex =
      globalStudentDatabase.indexWhere((student) => student.omrId == omrId);
  if (studentIndex == -1) {
    return;
  }

  final student = globalStudentDatabase[studentIndex];
  final remainingResults = globalScanResults
      .where((result) => result.studentOmrId == omrId)
      .toList()
    ..sort((a, b) => b.scanTime.compareTo(a.scanTime));

  final latestResult = remainingResults.isEmpty ? null : remainingResults.first;
  globalStudentDatabase[studentIndex] = Student(
    schoolId: student.schoolId,
    omrId: student.omrId,
    name: student.name,
    section: student.section,
    score: latestResult?.score,
    answers: latestResult?.detectedAnswers,
    scanDate: latestResult?.scanTime,
    confidence: latestResult?.confidence,
    ownerTeacherId: student.ownerTeacherId,
    cloudId: student.cloudId,
    syncStatus: SyncStatus.pending,
    updatedAt: DateTime.now(),
  );
}

SubjectDeletionSummary deleteSubjectAndRelatedData(Subject subject) {
  final removedScans = globalScanResults
      .where((result) => result.subjectId == subject.id)
      .toList();
  final affectedStudents =
      removedScans.map((result) => result.studentOmrId).toSet();
  final removedDeadlines = globalDeadlines
      .where((deadline) => deadline.subjectId == subject.id)
      .toList();

  final removedSubjectCount =
      globalSubjects.where((entry) => entry.id == subject.id).length;

  globalSubjects.removeWhere((entry) => entry.id == subject.id);
  globalScanResults.removeWhere((result) => result.subjectId == subject.id);
  globalDeadlines.removeWhere((deadline) => deadline.subjectId == subject.id);

  for (final omrId in affectedStudents) {
    _refreshStudentSnapshotFromLatestScan(omrId);
  }

  rebuildStudentIndex();

  return SubjectDeletionSummary(
    removedSubjects: removedSubjectCount,
    removedScans: removedScans.length,
    removedDeadlines: removedDeadlines.length,
    affectedStudents: affectedStudents.length,
  );
}

// GLOBAL OMR COUNTER with thread safety
int _globalOmrCounter = 1;
int _globalSubjectCounter = 1;
int _globalSheetCounter = 1;

/// Build sequential OMR ID (0001, 0002, 0003...)
String buildStudentOmrId(
  String schoolId, {
  Set<String> reservedOmrIds = const <String>{},
}) {
  // Generate sequential IDs starting from current counter
  for (var attempt = 0; attempt < 9999; attempt++) {
    final omrId = _globalOmrCounter.toString().padLeft(4, '0');
    _globalOmrCounter++;

    // Skip if already reserved
    if (!reservedOmrIds.contains(omrId)) {
      return omrId;
    }
  }

  throw StateError('No available OMR IDs remaining.');
}

// Legacy sequential OMR IDs remain available for older flows and tests.
String generateNextOmrId() {
  final id = _globalOmrCounter.toString().padLeft(4, '0');
  _globalOmrCounter++;
  return id;
}

String generateUniqueSubjectId() {
  final id = 'SUB-${_globalSubjectCounter.toString().padLeft(4, '0')}';
  _globalSubjectCounter++;
  return id;
}

String generateUniqueSheetId() {
  final id = 'SHEET-${_globalSheetCounter.toString().padLeft(6, '0')}';
  _globalSheetCounter++;
  return id;
}

// Keep this for backward compatibility if needed
int get nextOmrIdValue => _globalOmrCounter;
int get nextSubjectCounterValue => _globalSubjectCounter;
int get nextSheetCounterValue => _globalSheetCounter;

void resetOmrCounter() => _globalOmrCounter = 1;

void resetSubjectCounter() => _globalSubjectCounter = 1;

void resetSheetCounter() => _globalSheetCounter = 1;

void restoreCounters({
  required int omrCounter,
  required int subjectCounter,
  required int sheetCounter,
}) {
  _globalOmrCounter = omrCounter;
  _globalSubjectCounter = subjectCounter;
  _globalSheetCounter = sheetCounter;
}

class SubjectSheetQrPayload {
  const SubjectSheetQrPayload({
    required this.version,
    required this.sheetId,
    required this.subjectId,
    required this.subjectName,
    required this.totalQuestions,
    required this.passingScore,
    required this.sectionName,
    this.examDateIso,
    this.layout,
  });

  final int version;
  final String sheetId;
  final String subjectId;
  final String subjectName;
  final int totalQuestions;
  final int passingScore;
  final String? sectionName;
  final String? examDateIso;

  /// Layout metadata (v2+). Null for legacy v1 payloads.
  final QrLayoutMetadata? layout;

  /// Check if this is a v2 payload with explicit layout
  bool get hasExplicitLayout => layout != null && version >= 2;

  Map<String, dynamic> toJson() {
    return {
      'v': version,
      'sheetId': sheetId,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'questions': totalQuestions,
      'passingScore': passingScore,
      'section': sectionName,
      'examDate': examDateIso,
      if (layout != null) 'layout': layout!.toJson(),
    };
  }

  factory SubjectSheetQrPayload.fromJson(Map<String, dynamic> json) {
    final sectionsValue = json['sections'];
    String? fallbackSection;
    if (sectionsValue is List && sectionsValue.isNotEmpty) {
      fallbackSection = sectionsValue.first?.toString();
    }

    // Parse layout if present (v2+)
    QrLayoutMetadata? layout;
    final layoutJson = json['layout'];
    if (layoutJson is Map<String, dynamic>) {
      layout = QrLayoutMetadata.fromJson(layoutJson);
    }

    return SubjectSheetQrPayload(
      version: _readInt(json['v'], fallback: 1),
      sheetId: json['sheetId']?.toString() ?? '',
      subjectId: json['subjectId']?.toString() ?? '',
      subjectName: json['subjectName']?.toString() ?? '',
      totalQuestions: _readInt(json['questions']),
      passingScore: _readInt(json['passingScore']),
      sectionName: json['section']?.toString() ?? fallbackSection,
      examDateIso: json['examDate']?.toString(),
      layout: layout,
    );
  }

  Subject? resolveSubject() {
    for (final subject in globalSubjects) {
      if (subject.id == subjectId) {
        return subject;
      }
    }

    final normalizedName = subjectName.trim().toUpperCase();
    final nameMatches = globalSubjects
        .where((subject) => subject.normalizedName == normalizedName)
        .toList();
    if (nameMatches.isEmpty) {
      return null;
    }
    if (nameMatches.length == 1) {
      return nameMatches.first;
    }

    final qrSection = sectionName?.trim();
    if (qrSection != null && qrSection.isNotEmpty) {
      final normalizedQrSection = normalizeSectionName(qrSection);
      for (final subject in nameMatches) {
        final sections = subject.sectionNames ?? const <String>[];
        if (sections.any(
          (name) => normalizeSectionName(name) == normalizedQrSection,
        )) {
          return subject;
        }
      }
    }

    return null;
  }

  static int _readInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

/// Layout metadata embedded in QR payload (v2+)
/// This tells the scanner exactly where to find bubbles without calculation.
class QrLayoutMetadata {
  const QrLayoutMetadata({
    required this.templateId,
    required this.columns,
    required this.rows,
    required this.gridTop,
    required this.gridBottom,
    required this.rowHeight,
    required this.columnWidth,
    required this.bubbleSpacingX,
  });

  /// Template identifier (matches the dedicated supported item count)
  final String templateId;

  /// Number of question columns
  final int columns;

  /// Number of rows per column
  final int rows;

  /// Y position where answer grid starts (in PDF points)
  final double gridTop;

  /// Y position where answer grid ends (in PDF points)
  final double gridBottom;

  /// Height of each row in points (fixed, not calculated)
  final double rowHeight;

  /// Width of each column in points
  final double columnWidth;

  /// Horizontal spacing between bubble centers within a column
  final double bubbleSpacingX;

  Map<String, dynamic> toJson() => {
        'template': templateId,
        'cols': columns,
        'rows': rows,
        'gridTop': gridTop,
        'gridBottom': gridBottom,
        'rowHeight': rowHeight,
        'colWidth': columnWidth,
        'bubbleSpacingX': bubbleSpacingX,
      };

  factory QrLayoutMetadata.fromJson(Map<String, dynamic> json) {
    return QrLayoutMetadata(
      templateId: json['template']?.toString() ?? '',
      columns: _readIntStatic(json['cols']),
      rows: _readIntStatic(json['rows']),
      gridTop: _readDoubleStatic(json['gridTop']),
      gridBottom: _readDoubleStatic(json['gridBottom']),
      rowHeight: _readDoubleStatic(json['rowHeight']),
      columnWidth: _readDoubleStatic(json['colWidth']),
      bubbleSpacingX: _readDoubleStatic(json['bubbleSpacingX']),
    );
  }

  static int _readIntStatic(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _readDoubleStatic(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
