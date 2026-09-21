import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/scanner_session_layout.dart';

void main() {
  test('session layout matches template for each supported item count', () {
    const counts = <int>[30, 40, 50, 60, 70, 80, 90, 100];
    for (final count in counts) {
      final subject = Subject(
        id: 'SUB-$count',
        name: 'Math $count',
        answerKey: {for (int i = 1; i <= count; i++) i: 'A'},
        totalQuestions: count,
      );
      final session = ScannerSessionLayout.fromSubject(subject);
      final template = OmrTemplateSpec.forItemCount(count);
      final native = session.toNativeMap();

      expect(session.templateId, template.templateId);
      expect(session.totalQuestions, count);
      expect(session.isCustom, isFalse);
      expect(session.layoutMode, 'preset');
      expect(native['template'], template.templateId);
      expect(native['isCustom'], isFalse);
      expect(native['layoutMode'], 'preset');
      expect(native['useFrozenRegistrationMarks'], isTrue);
      expect(native['cols'], template.columns);
      expect(native['rows'], template.rows);
      expect(native['gridTop'], OmrPageConstants.answerRowsTop);
      expect(native['rowHeight'], template.rowHeight);
      expect(native['bubbleSpacingX'], template.bubbleSpacingX);
      expect(native['contentBlockWidth'], OmrPageConstants.pageWidth);
      expect(native['contentBlockHeight'], OmrPageConstants.pageHeight);
    }
  });

  test('custom 30-question sheet is not treated as frozen preset by identity',
      () {
    final subject = Subject(
      id: 'SUB-CUSTOM-30',
      name: 'Quiz 30',
      answerKey: {for (int i = 1; i <= 30; i++) i: 'A'},
      totalQuestions: 30,
      useCustomLayout: true,
      optionsCount: 4,
      layoutShape: 'lengthwise_full',
      customGridColumns: 3,
      customGridRows: 10,
    );
    final session = ScannerSessionLayout.fromSubject(subject);
    final native = session.toNativeMap();

    expect(session.isCustom, isTrue);
    expect(session.layoutMode, 'custom');
    expect(native['isCustom'], isTrue);
    expect(native['layoutMode'], 'custom');
    expect(native['layoutShape'], 'lengthwise_full');
    expect(native['useFrozenRegistrationMarks'], isFalse);
    expect(session.optionsCount, 4);
    expect(session.totalQuestions, 30);
  });

  test('half-page custom is unlocked and warps to content block', () {
    final fit = OmrLayoutProfile.tryCompute(
      itemCount: 10,
      optionsCount: 5,
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.half,
      ),
    );
    expect(fit.isOk, isTrue);

    final subject = Subject(
      id: 'SUB-HALF',
      name: 'Half quiz',
      answerKey: {for (int i = 1; i <= 10; i++) i: 'A'},
      totalQuestions: 10,
      useCustomLayout: true,
      optionsCount: 5,
      layoutShape: 'lengthwise_half',
      customGridColumns: fit.profile!.grid.columns,
      customGridRows: fit.profile!.grid.rows,
    );
    expect(
      ScannerSessionLayout.examReadyScanErrorForSubject(subject),
      isNull,
    );
    final session = ScannerSessionLayout.fromSubject(subject);
    final native = session.toNativeMap();
    expect(native['useFrozenRegistrationMarks'], isFalse);
    expect(native['layoutShape'], 'lengthwise_half');
    expect(
      (native['contentBlockHeight'] as num).toDouble(),
      closeTo(OmrPageConstants.pageHeight / 2, 0.5),
    );
    expect(
      (native['contentBlockWidth'] as num).toDouble(),
      closeTo(OmrPageConstants.pageWidth, 0.5),
    );
    expect(native['timingMarkEndY'], isNotNull);
    expect(native['omrIdFirstColumnX'], isNotNull);
    expect(native['calibrationY'], isNotNull);
    expect(native['rowMarkX'], isNotNull);
  });

  test('legacy landscape custom is blocked before scan (portrait-only policy)',
      () {
    final subject = Subject(
      id: 'SUB-LAND',
      name: 'Wide quiz',
      answerKey: {for (int i = 1; i <= 12; i++) i: 'A'},
      totalQuestions: 12,
      useCustomLayout: true,
      optionsCount: 4,
      layoutShape: 'crosswise_full',
      customGridColumns: 3,
      customGridRows: 4,
    );
    final gate = ScannerSessionLayout.examReadyScanErrorForSubject(subject);
    expect(gate, isNotNull);
    expect(gate!.toLowerCase(), contains('landscape'));
  });

  test('portrait full custom is exam-ready when grid is saved', () {
    final fit = OmrLayoutProfile.tryCompute(
      itemCount: 15,
      optionsCount: 5,
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
    );
    expect(fit.isOk, isTrue);

    final subject = Subject(
      id: 'SUB-FULL',
      name: 'Full custom',
      answerKey: {for (int i = 1; i <= 15; i++) i: 'A'},
      totalQuestions: 15,
      useCustomLayout: true,
      optionsCount: 5,
      layoutShape: 'lengthwise_full',
      customGridColumns: fit.profile!.grid.columns,
      customGridRows: fit.profile!.grid.rows,
    );
    expect(
      ScannerSessionLayout.examReadyScanErrorForSubject(subject),
      isNull,
    );
  });

  test('six-choice custom session exposes optionsCount 6 and subjectId to native',
      () {
    final fit = OmrLayoutProfile.tryCompute(
      itemCount: 20,
      optionsCount: 6,
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
    );
    expect(fit.isOk, isTrue);
    expect(fit.profile!.optionLabels, ['A', 'B', 'C', 'D', 'E', 'F']);

    final subject = Subject(
      id: 'SUB-SIX',
      name: 'Six choice quiz',
      answerKey: {for (int i = 1; i <= 20; i++) i: 'F'},
      totalQuestions: 20,
      useCustomLayout: true,
      optionsCount: 6,
      layoutShape: 'lengthwise_full',
      customGridColumns: fit.profile!.grid.columns,
      customGridRows: fit.profile!.grid.rows,
    );
    final session = ScannerSessionLayout.fromSubject(subject);
    final native = session.toNativeMap();

    expect(native['optionsCount'], 6);
    expect(native['subjectId'], 'SUB-SIX');
    expect(native['isCustom'], isTrue);
    expect(native['useFrozenRegistrationMarks'], isFalse);
    expect(session.optionsCount, 6);
  });

  test('dense max-fit grid stays above scan-safe row height', () {
    const form = OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.full,
    );
    final maxFit = OmrLayoutProfile.maxFitItems(form: form, optionsCount: 6);
    final fit = OmrLayoutProfile.tryCompute(
      itemCount: maxFit,
      optionsCount: 6,
      form: form,
    );
    expect(fit.isOk, isTrue);
    final profile = fit.profile!;
    expect(
      profile.grid.rowHeight,
      greaterThanOrEqualTo(OmrLayoutProfile.scanMinRowHeight(profile.geometry)),
    );
    expect(
      profile.grid.bubbleSpacingX,
      greaterThanOrEqualTo(
        OmrLayoutProfile.scanMinBubbleSpacing(profile.form, profile.geometry),
      ),
    );
    expect(profile.grid.rows, lessThanOrEqualTo(OmrLayoutProfile.maxRowsPerColumn));
    final subject = Subject(
      id: 'SUB-MAX',
      name: 'Long custom',
      answerKey: {for (int i = 1; i <= maxFit; i++) i: 'A'},
      totalQuestions: maxFit,
      useCustomLayout: true,
      optionsCount: 6,
      layoutShape: 'lengthwise_full',
      customGridColumns: profile.grid.columns,
      customGridRows: profile.grid.rows,
    );
    expect(ScannerSessionLayout.examReadyScanErrorForSubject(subject), isNull);
    final native = ScannerSessionLayout.fromSubject(subject).toNativeMap();
    expect(native['optionsCount'], 6);
    expect((native['rowHeight'] as num).toDouble(),
        greaterThanOrEqualTo(OmrLayoutProfile.minRowHeightDense));
    expect((native['bubbleSpacingX'] as num).toDouble(),
        greaterThanOrEqualTo(OmrLayoutProfile.minBubbleSpacingXDense));
  });

  test('200 x A-F is blocked when it would violate scan floors', () {
    final fit = OmrLayoutProfile.tryComputeExplicitGrid(
      columns: 5,
      rows: 40,
      optionsCount: 6,
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
    );
    // 5x40 was the old tight pack — must not pass the reliable floors.
    expect(fit.isOk, isFalse);
  });
}
