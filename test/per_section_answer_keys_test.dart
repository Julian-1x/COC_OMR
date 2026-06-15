import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';

Subject _mathForSection(String id, String section, Map<int, List<String>> key) {
  return Subject(
    id: id,
    name: 'Math',
    answerKey: key,
    totalQuestions: 30,
    sectionNames: [section],
    examDate: DateTime(2026, 4, 8),
  );
}

void main() {
  setUp(() {
    globalSubjects = [];
    resetSubjectCounter();
  });

  test('two Math keys for different sections can coexist', () {
    final mathA = _mathForSection('SUB-0001', 'BSIT-1A', {1: ['A']});
    final mathB = _mathForSection('SUB-0002', 'BSIT-1B', {1: ['B']});

    globalSubjects = [mathA, mathB];

    expect(globalSubjects.length, 2);
    expect(mathA.answerKey[1], ['A']);
    expect(mathB.answerKey[1], ['B']);
  });

  test('resolveSubject prefers subjectId over ambiguous name', () {
    globalSubjects = [
      _mathForSection('SUB-0001', 'BSIT-1A', {1: ['A']}),
      _mathForSection('SUB-0002', 'BSIT-1B', {1: ['B']}),
    ];

    final payload = SubjectSheetQrPayload(
      version: 2,
      sheetId: 'SHEET-0001',
      subjectId: 'SUB-0002',
      subjectName: 'Math',
      totalQuestions: 30,
      passingScore: 0,
      sectionName: 'BSIT-1B',
    );

    expect(payload.resolveSubject()?.id, 'SUB-0002');
  });

  test('resolveSubject disambiguates by section when names collide', () {
    globalSubjects = [
      _mathForSection('SUB-0001', 'BSIT-1A', {1: ['A']}),
      _mathForSection('SUB-0002', 'BSIT-1B', {1: ['B']}),
    ];

    final payload = SubjectSheetQrPayload(
      version: 2,
      sheetId: 'SHEET-0002',
      subjectId: '',
      subjectName: 'Math',
      totalQuestions: 30,
      passingScore: 0,
      sectionName: 'BSIT-1A',
    );

    expect(payload.resolveSubject()?.id, 'SUB-0001');
  });

  test('resolveSubject returns null when name matches multiple subjects without section', () {
    globalSubjects = [
      _mathForSection('SUB-0001', 'BSIT-1A', {1: ['A']}),
      _mathForSection('SUB-0002', 'BSIT-1B', {1: ['B']}),
    ];

    final payload = SubjectSheetQrPayload(
      version: 2,
      sheetId: 'SHEET-0003',
      subjectId: '',
      subjectName: 'Math',
      totalQuestions: 30,
      passingScore: 0,
      sectionName: null,
    );

    expect(payload.resolveSubject(), isNull);
  });

  test('section overlap is detectable for same subject name', () {
    final existing = _mathForSection('SUB-0001', 'BSIT-1A', {1: ['A']});
    globalSubjects = [existing];

    final takenSections = (existing.sectionNames ?? const <String>[])
        .map(normalizeSectionName)
        .toSet();
    final candidateSections = {normalizeSectionName('BSIT-1A')};
    final candidateSectionsB = {normalizeSectionName('BSIT-1B')};

    expect(takenSections.intersection(candidateSections), isNotEmpty);
    expect(takenSections.intersection(candidateSectionsB), isEmpty);
  });
}
