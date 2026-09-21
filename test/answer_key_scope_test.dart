import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/utils/answer_key_scope.dart';

Subject _subject({
  required String id,
  required String name,
  List<String>? sections,
}) {
  return Subject(
    id: id,
    name: name,
    answerKey: {1: ['A']},
    totalQuestions: 30,
    sectionNames: sections,
  );
}

void main() {
  group('AnswerKeyScope', () {
    test('classifies unassigned, section-only, and shared', () {
      expect(
        AnswerKeyScope.of(_subject(id: '1', name: 'Math')).kind,
        AnswerKeyScopeKind.unassigned,
      );
      expect(
        AnswerKeyScope.of(
          _subject(id: '2', name: 'Math', sections: ['BSIT-01']),
        ).kind,
        AnswerKeyScopeKind.sectionOnly,
      );
      expect(
        AnswerKeyScope.of(
          _subject(
            id: '3',
            name: 'Math',
            sections: ['BSIT-01', 'BSIT-02'],
          ),
        ).kind,
        AnswerKeyScopeKind.shared,
      );
    });

    test('describeSubject keeps same names distinct', () {
      final shared = _subject(
        id: '1',
        name: 'Math',
        sections: ['BSIT-01', 'BSIT-02'],
      );
      final only = _subject(
        id: '2',
        name: 'Math',
        sections: ['BSIT-01'],
      );
      expect(
        AnswerKeyScope.of(shared).describeSubject(shared),
        'Math · Shared (BSIT-01, BSIT-02)',
      );
      expect(
        AnswerKeyScope.of(only).describeSubject(only),
        'Math · BSIT-01 only',
      );
    });

    test('printScopeTag marks shared vs section-only', () {
      final shared = AnswerKeyScope.of(
        _subject(
          id: '1',
          name: 'Math',
          sections: ['A', 'B'],
        ),
      );
      final only = AnswerKeyScope.of(
        _subject(id: '2', name: 'Math', sections: ['A']),
      );
      expect(shared.printScopeTag(printedSection: 'A'), 'SHARED KEY');
      expect(only.printScopeTag(printedSection: 'A'), 'THIS SECTION ONLY');
    });

    test('wrongKeyMessage names both section scopes', () {
      final scanner = _subject(
        id: 'SUB-1',
        name: 'Math',
        sections: ['BSIT-01'],
      );
      final sheet = _subject(
        id: 'SUB-2',
        name: 'Math',
        sections: ['BSIT-02'],
      );
      final message = AnswerKeyScope.wrongKeyMessage(
        scannerSubject: scanner,
        sheetSubject: sheet,
      );
      expect(message, contains('BSIT-02 only'));
      expect(message, contains('BSIT-01 only'));
      expect(message, contains('different keys per section'));
    });

    test('wrongSectionForOpenKeyMessage differs for shared vs section-only', () {
      final only = _subject(
        id: '1',
        name: 'Math',
        sections: ['BSIT-01'],
      );
      final shared = _subject(
        id: '2',
        name: 'Math',
        sections: ['BSIT-01', 'BSIT-02'],
      );
      expect(
        AnswerKeyScope.wrongSectionForOpenKeyMessage(
          scannerSubject: only,
          sheetSection: 'BSIT-03',
        ),
        contains('section-only key'),
      );
      expect(
        AnswerKeyScope.wrongSectionForOpenKeyMessage(
          scannerSubject: shared,
          sheetSection: 'BSIT-03',
        ),
        contains('shared key'),
      );
    });
  });
}
