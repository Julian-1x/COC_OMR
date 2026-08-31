import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';

void main() {
  group('Answer sheet PDF output', () {
    test('standard 50-question sheet produces a non-empty PDF', () async {
      final subject = Subject(
        name: 'Midterm Exam',
        answerKey: {for (int i = 1; i <= 50; i++) i: 'A'},
        totalQuestions: 50,
      );

      final bytes = await AnswerSheetGenerator.buildSamplePdfBytes(subject);

      expect(bytes.length, greaterThan(5000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('custom quarter sheet produces a non-empty PDF', () async {
      final subject = Subject(
        name: 'Sample Exam',
        answerKey: const <int, dynamic>{},
        totalQuestions: 10,
        useCustomLayout: true,
        optionsCount: 4,
        layoutShape: 'lengthwise_quarter',
        customGridColumns: 2,
        customGridRows: 5,
      );

      final bytes = await AnswerSheetGenerator.buildSamplePdfBytes(subject);

      expect(bytes.length, greaterThan(4000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
