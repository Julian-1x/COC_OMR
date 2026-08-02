import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';

void main() {
  const supportedItemCounts = <int>[30, 40, 50, 60, 70, 80, 90, 100];

  setUp(() {
    globalStudentDatabase = <Student>[];
    globalSections = <Section>[];
    globalSubjects = <Subject>[];
    globalScanResults = <ScanResult>[];
    globalDeadlines = <Deadline>[];
    rebuildStudentIndex();
  });

  group('Scanner QR/OMR grading contract', () {
    test('QR payload resolves back to correct subject for all layouts', () {
      for (final itemCount in supportedItemCounts) {
        final subject = Subject(
          id: 'SUB-$itemCount',
          name: 'Math $itemCount',
          answerKey: <int, String>{
            for (int i = 1; i <= itemCount; i++) i: 'A',
          },
          totalQuestions: itemCount,
          sectionNames: const <String>['Grade 10-A'],
        );
        globalSubjects.add(subject);

        final qrData = AnswerSheetGenerator.buildSheetQrCodeData(subject);
        final payload = SubjectSheetQrPayload.fromJson(
          Map<String, dynamic>.from(jsonDecode(qrData) as Map),
        );

        expect(payload.hasExplicitLayout, isFalse,
            reason: 'Print QR is lean — layout comes from scanner session');
        expect(payload.totalQuestions, itemCount);
        expect(payload.layout, isNull);
        expect(payload.resolveSubject()?.id, subject.id);
        expect(payload.isCocIssued, isTrue);
      }
    });

    test('QR section disambiguates same-name subjects for grading', () {
      final sectionA = Subject(
        id: 'SUB-A',
        name: 'Science',
        answerKey: <int, String>{for (int i = 1; i <= 50; i++) i: 'A'},
        totalQuestions: 50,
        sectionNames: const <String>['G10-A'],
      );
      final sectionB = Subject(
        id: 'SUB-B',
        name: 'Science',
        answerKey: <int, String>{for (int i = 1; i <= 50; i++) i: 'B'},
        totalQuestions: 50,
        sectionNames: const <String>['G10-B'],
      );
      globalSubjects.addAll(<Subject>[sectionA, sectionB]);

      final qrJson = <String, dynamic>{
        'v': 2,
        'sheetId': 'SHEET-1',
        'subjectId': '',
        'subjectName': 'Science',
        'questions': 50,
        'passingScore': 30,
        'section': 'G10-B',
        'layout': OmrTemplateSpec.forItemCount(50).toJson(),
      };

      final payload = SubjectSheetQrPayload.fromJson(qrJson);
      expect(payload.resolveSubject()?.id, 'SUB-B');
    });

    test('QR payload includes COC app issuer tag', () {
      final subject = Subject(
        id: 'SUB-50',
        name: 'Math',
        answerKey: <int, String>{for (int i = 1; i <= 50; i++) i: 'A'},
        totalQuestions: 50,
        sectionNames: const <String>['G10-A'],
        ownerTeacherId: 'teacher-1',
        cloudId: 'cloud-subject-1',
      );
      globalSubjects.add(subject);

      final qrData = AnswerSheetGenerator.buildSheetQrCodeData(subject);
      final json = Map<String, dynamic>.from(jsonDecode(qrData) as Map);
      expect(json['a'] ?? json['app'], SubjectSheetQrPayload.cocOmrAppId);
      expect(json['ot'] ?? json['ownerTeacherId'], 'teacher-1');
      expect(json['ci'] ?? json['subjectCloudId'], 'cloud-subject-1');

      final payload = SubjectSheetQrPayload.fromJson(json);
      expect(payload.isCocIssued, isTrue);
      expect(payload.ownerTeacherId, 'teacher-1');
      // Lean print QR — no layout blob (session supplies grid).
      expect(json.containsKey('l') || json.containsKey('layout'), isFalse);
      expect(json.containsKey('ps') || json.containsKey('passingScore'), isFalse);
      expect(json.containsKey('on') || json.containsKey('ownerTeacherName'), isFalse);

      // Keep the printed symbol sparse enough for phone cameras to decode.
      expect(qrData.length, lessThan(220),
          reason: 'Dense QR payloads fail to scan from printed sheets');
    });

    test('foreign app tag is not treated as COC sheet', () {
      final payload = SubjectSheetQrPayload.fromJson({
        'app': 'evalbee',
        'v': 2,
        'sheetId': 'X-1',
        'subjectId': 'S1',
        'subjectName': 'Math',
        'questions': 50,
        'passingScore': 30,
      });
      expect(payload.isCocIssued, isFalse);
    });

    test('legacy COC QR without app tag still counts as ours', () {
      final payload = SubjectSheetQrPayload.fromJson({
        'v': 2,
        'sheetId': 'SHEET-1',
        'subjectId': 'SUB-1',
        'subjectName': 'Math',
        'questions': 50,
        'passingScore': 30,
      });
      expect(payload.app, isNull);
      expect(payload.isCocIssued, isTrue);
    });

    test('OMR ID roster linking and scoring stay consistent', () {
      final student = Student(
        schoolId: '2026-0001',
        omrId: '0007',
        name: 'Learner One',
        section: 'G10-A',
      );
      addStudent(student);
      rebuildStudentIndex();

      final subject = Subject(
        id: 'SUB-50',
        name: 'English',
        answerKey: <int, String>{for (int i = 1; i <= 50; i++) i: 'C'},
        totalQuestions: 50,
      );

      expect(findStudentByOmrId('0007')?.name, 'Learner One');
      expect(findStudentByOmrId('9999'), isNull);

      final perfectAnswers = <int, String>{for (int i = 1; i <= 50; i++) i: 'C'};
      final mixedAnswers = <int, String>{
        for (int i = 1; i <= 25; i++) i: 'C',
        for (int i = 26; i <= 50; i++) i: 'A',
      };

      expect(subject.calculateSmartScore(perfectAnswers), 50);
      expect(subject.calculateSmartScore(mixedAnswers), 25);
    });
  });
}
