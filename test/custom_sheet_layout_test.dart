import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';

void main() {
  test('CustomSheetLayout applyToSubject sets print fields', () {
    final layout = CustomSheetLayout(
      id: 'csl_test',
      name: 'Quiz 15',
      totalQuestions: 15,
      optionsCount: 4,
      layoutShape: 'lengthwise_half',
      gridColumns: 3,
      gridRows: 5,
      inputMode: CustomSheetLayoutInputMode.byQuestions,
      createdAt: DateTime(2026),
    );

    final subject = Subject(
      name: 'MATH',
      answerKey: const {1: 'A'},
      totalQuestions: 15,
    );

    final linked = layout.applyToSubject(subject);
    expect(linked.useCustomLayout, isTrue);
    expect(linked.optionsCount, 4);
    expect(linked.layoutShape, 'lengthwise_half');
    expect(linked.customLayoutId, 'csl_test');
    expect(linked.customGridColumns, 3);
    expect(linked.customGridRows, 5);
  });

  test('validateForSubject blocks question count mismatch', () {
    final layout = CustomSheetLayout.create(
      name: 'Fifteen',
      totalQuestions: 15,
      optionsCount: 5,
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
      inputMode: CustomSheetLayoutInputMode.byQuestions,
    );

    final subject = Subject(
      name: 'MATH',
      answerKey: const {1: 'A'},
      totalQuestions: 50,
    );

    expect(layout.validateForSubject(subject), isNotNull);
  });

  test('validateForSubject allows half-page layouts when scan-ready', () {
    final layout = CustomSheetLayout(
      id: 'csl_half',
      name: 'Half 10',
      totalQuestions: 10,
      optionsCount: 5,
      layoutShape: 'lengthwise_half',
      gridColumns: 2,
      gridRows: 5,
      inputMode: CustomSheetLayoutInputMode.byQuestions,
      createdAt: DateTime(2026),
    );
    final subject = Subject(
      name: 'QUIZ',
      answerKey: {for (int i = 1; i <= 10; i++) i: 'A'},
      totalQuestions: 10,
    );
    expect(layout.validateForSubject(subject), isNull);
    expect(layout.examReadyScanError, isNull);
  });
}
