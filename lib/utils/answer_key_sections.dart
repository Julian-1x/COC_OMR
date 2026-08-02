import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart' as generator;

/// All section names known from classes, rosters, and existing answer keys.
Set<String> collectKnownSectionNames({
  Iterable<Section>? sections,
  Iterable<Student>? students,
  Iterable<Subject>? subjects,
}) {
  final sectionSource = sections ?? globalSections;
  final studentSource = students ?? globalStudentDatabase;
  final subjectSource = subjects ?? globalSubjects;

  final names = <String>{};
  for (final section in sectionSource) {
    names.add(normalizeSectionName(section.name));
  }
  for (final student in studentSource) {
    names.add(normalizeSectionName(student.section));
  }
  for (final subject in subjectSource) {
    for (final section in subject.sectionNames ?? const <String>[]) {
      names.add(normalizeSectionName(section));
    }
  }
  return names;
}

Set<String> _normalizedSectionsOf(Subject subject) {
  return (subject.sectionNames ?? const <String>[])
      .map(normalizeSectionName)
      .toSet();
}

String _normalizedSubjectName(String name) => name.trim().toUpperCase();

/// Sections already on another answer key with the same subject name.
Set<String> sectionsTakenBySiblingSubjects(
  Subject subject, {
  Iterable<Subject>? subjects,
}) {
  final subjectSource = subjects ?? globalSubjects;
  final subjectName = _normalizedSubjectName(subject.name);
  final taken = <String>{};
  for (final other in subjectSource) {
    if (other.id == subject.id) {
      continue;
    }
    if (_normalizedSubjectName(other.name) != subjectName) {
      continue;
    }
    taken.addAll(_normalizedSectionsOf(other));
  }
  return taken;
}

/// Sections that can be added to [subject] without conflicting with a sibling key.
List<String> sectionsAvailableToAdd(
  Subject subject, {
  Iterable<Section>? sections,
  Iterable<Student>? students,
  Iterable<Subject>? subjects,
}) {
  final subjectSource = subjects ?? globalSubjects;
  final assigned = _normalizedSectionsOf(subject);
  final taken = sectionsTakenBySiblingSubjects(subject, subjects: subjectSource);
  return collectKnownSectionNames(
    sections: sections,
    students: students,
    subjects: subjectSource,
  )
      .where((section) => !assigned.contains(section) && !taken.contains(section))
      .toList()
    ..sort();
}

Subject? findConflictingSubjectForSection({
  required Subject subject,
  required String sectionName,
  Iterable<Subject>? subjects,
}) {
  final subjectSource = subjects ?? globalSubjects;
  final normalizedSection = normalizeSectionName(sectionName);
  final subjectName = _normalizedSubjectName(subject.name);
  for (final other in subjectSource) {
    if (other.id == subject.id) {
      continue;
    }
    if (_normalizedSubjectName(other.name) != subjectName) {
      continue;
    }
    if (_normalizedSectionsOf(other).contains(normalizedSection)) {
      return other;
    }
  }
  return null;
}

Map<String, String> buildSectionQrDataForSubject(
  Subject subject,
  List<String> sections,
) {
  final examDate = subject.examDate ?? DateTime.now();
  final sectionQrData = <String, String>{};
  for (final section in sections) {
    sectionQrData[section] =
        generator.AnswerSheetGenerator.buildSheetQrCodeDataForSection(
      subjectId: subject.id,
      subjectName: subject.name,
      totalQuestions: subject.totalQuestions,
      passingScore: subject.passingScore,
      examDate: examDate,
      sectionName: section,
      ownerTeacherId: subject.ownerTeacherId,
      subjectCloudId: subject.cloudId,
    );
  }
  return sectionQrData;
}

/// Returns an updated subject with [sectionName] merged in, or null if already assigned.
Subject? addSectionToSubject(Subject subject, String sectionName) {
  final canonical = normalizeSectionName(sectionName);
  if (canonical.isEmpty) {
    return null;
  }

  final existing = (subject.sectionNames ?? const <String>[])
      .map(normalizeSectionName)
      .toSet();
  if (existing.contains(canonical)) {
    return null;
  }

  final mergedNames = [...existing, canonical].toList()..sort();
  final sectionQrData = buildSectionQrDataForSubject(subject, mergedNames);

  return subject.copyWith(
    sectionNames: mergedNames,
    sectionQrData: sectionQrData,
    syncStatus: SyncStatus.pending,
    updatedAt: DateTime.now(),
  );
}

/// Re-link active sections that still have QR data but were stripped from
/// [Subject.sectionNames] by older archive builds.
Subject restoreMissingSectionLinks(
  Subject subject, {
  Iterable<String> activeSectionNames = const <String>[],
}) {
  final active = activeSectionNames.map(normalizeSectionName).toSet()
    ..removeWhere((name) => name.isEmpty);
  if (active.isEmpty) {
    return subject;
  }

  final linked = (subject.sectionNames ?? const <String>[])
      .map(normalizeSectionName)
      .where((name) => name.isNotEmpty)
      .toSet();

  final qrKeys = subject.sectionQrData.keys
      .map(normalizeSectionName)
      .where((name) => name.isNotEmpty)
      .toSet();

  final missing = active
      .where((section) => !linked.contains(section) && qrKeys.contains(section))
      .toSet();

  if (missing.isEmpty) {
    return subject;
  }

  final mergedNames = {...linked, ...missing}.toList()..sort();
  return subject.copyWith(
    sectionNames: mergedNames,
    sectionQrData: buildSectionQrDataForSubject(subject, mergedNames),
    syncStatus: SyncStatus.pending,
    updatedAt: DateTime.now(),
  );
}
