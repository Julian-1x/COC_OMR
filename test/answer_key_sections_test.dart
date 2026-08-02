import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/utils/answer_key_sections.dart';

void main() {
  setUp(() {
    globalSections = [];
    globalSubjects = [];
    globalStudentDatabase = [];
    resetSubjectCounter();
  });

  test('sectionsAvailableToAdd excludes assigned and sibling-owned sections', () {
    globalSections = [
      Section(name: 'BSIT-01'),
      Section(name: 'BSIT-02'),
      Section(name: 'BSIT-03'),
    ];
    globalSubjects = [
      Subject(
        id: 'SUB-0001',
        name: 'Math',
        answerKey: {1: ['A']},
        totalQuestions: 50,
        sectionNames: ['BSIT-02', 'BSIT-03'],
      ),
      Subject(
        id: 'SUB-0002',
        name: 'Math',
        answerKey: {1: ['B']},
        totalQuestions: 50,
        sectionNames: ['BSIT-04'],
      ),
    ];

    final available = sectionsAvailableToAdd(globalSubjects.first);

    expect(available, ['BSIT-01']);
  });

  test('addSectionToSubject merges section and marks sync pending', () {
    final subject = Subject(
      id: 'SUB-0001',
      name: 'Math',
      answerKey: {1: ['A']},
      totalQuestions: 50,
      sectionNames: ['BSIT-02'],
      examDate: DateTime(2026, 7, 8),
      passingScore: 30,
    );

    final updated = addSectionToSubject(subject, 'BSIT-01');

    expect(updated, isNotNull);
    expect(updated!.sectionNames, ['BSIT-01', 'BSIT-02']);
    expect(updated.sectionQrData?['BSIT-01'], isNotEmpty);
    expect(updated.syncStatus, SyncStatus.pending);
  });

  test('restoreMissingSectionLinks reattaches from QR map', () {
    final subject = Subject(
      id: 'SUB-0001',
      name: 'Math',
      answerKey: {
        1: ['A'],
      },
      totalQuestions: 50,
      sectionNames: const <String>[],
      sectionQrData: const {
        'BSIT-01': 'qr-payload',
      },
      examDate: DateTime(2026, 7, 8),
      passingScore: 30,
      syncStatus: SyncStatus.synced,
    );

    final restored = restoreMissingSectionLinks(
      subject,
      activeSectionNames: const ['BSIT-01'],
    );

    expect(restored.sectionNames, ['BSIT-01']);
    expect(restored.syncStatus, SyncStatus.pending);
  });
}
