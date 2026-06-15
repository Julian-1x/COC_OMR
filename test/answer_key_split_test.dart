import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';

/// Mirrors split-on-save behavior from AnswerKeyPage.
(Subject original, Subject split) simulateSplitSave({
  required Subject existing,
  required String focusSection,
  required Map<int, List<String>> splitAnswerKey,
  required String newSubjectId,
}) {
  final normalizedFocus = normalizeSectionName(focusSection);
  final remainingSections = (existing.sectionNames ?? const <String>[])
      .map(normalizeSectionName)
      .where((section) => section != normalizedFocus)
      .toList()
    ..sort();

  final updatedOriginal = existing.copyWith(
    sectionNames: remainingSections,
    updatedAt: DateTime(2026, 6, 13),
  );

  final splitSubject = Subject(
    id: newSubjectId,
    name: existing.name,
    answerKey: splitAnswerKey,
    totalQuestions: existing.totalQuestions,
    sectionNames: [normalizedFocus],
    examDate: existing.examDate,
    passingScore: existing.passingScore,
  );

  return (updatedOriginal, splitSubject);
}

void main() {
  setUp(() {
    globalSubjects = [];
    resetSubjectCounter();
  });

  test('split edit keeps section 1 answers on original subject', () {
    final shared = Subject(
      id: 'SUB-0001',
      name: 'Physics',
      answerKey: {1: ['A'], 2: ['B']},
      totalQuestions: 30,
      sectionNames: ['BSIT-1A', 'BSIT-1B'],
      examDate: DateTime(2026, 4, 8),
    );

    final (original, split) = simulateSplitSave(
      existing: shared,
      focusSection: 'BSIT-1B',
      splitAnswerKey: {1: ['C'], 2: ['D']},
      newSubjectId: 'SUB-0002',
    );

    expect(original.sectionNames, ['BSIT-1A']);
    expect(original.answerKey[1], ['A']);
    expect(original.answerKey[2], ['B']);

    expect(split.id, 'SUB-0002');
    expect(split.sectionNames, ['BSIT-1B']);
    expect(split.answerKey[1], ['C']);
    expect(split.answerKey[2], ['D']);
  });

  test('shared subject with two sections is detectable for UI badge', () {
    final shared = Subject(
      id: 'SUB-0001',
      name: 'Physics',
      answerKey: {1: ['A']},
      totalQuestions: 30,
      sectionNames: ['BSIT-1A', 'BSIT-1B'],
    );
    final single = Subject(
      id: 'SUB-0002',
      name: 'Physics',
      answerKey: {1: ['B']},
      totalQuestions: 30,
      sectionNames: ['BSIT-1C'],
    );

    expect((shared.sectionNames ?? []).length > 1, isTrue);
    expect((single.sectionNames ?? []).length > 1, isFalse);
  });
}
