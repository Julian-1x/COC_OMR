import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';

/// Locked layout for one exam-day scan session (preset or custom).
///
/// Built once when the teacher opens Scan for a subject. Native OpenCV uses
/// [toNativeMap] so bubble positions match the printed sheet exactly — never
/// inferred from question count alone (a custom 30-Q sheet is not template "30").
class ScannerSessionLayout {
  const ScannerSessionLayout({
    required this.templateId,
    required this.columns,
    required this.rows,
    required this.gridTop,
    required this.gridBottom,
    required this.rowHeight,
    required this.columnWidth,
    required this.bubbleSpacingX,
    required this.optionsCount,
    required this.totalQuestions,
    required this.subjectId,
    required this.subjectName,
    required this.geometry,
    required this.isCustom,
    required this.layoutMode,
    required this.layoutShape,
  });

  final String templateId;
  final int columns;
  final int rows;
  final double gridTop;
  final double gridBottom;
  final double rowHeight;
  final double columnWidth;
  final double bubbleSpacingX;
  final int optionsCount;
  final int totalQuestions;
  final String subjectId;
  final String subjectName;
  final OmrSheetGeometry geometry;

  /// True when this subject uses a custom sheet (even if Q count is 30–100).
  final bool isCustom;

  /// `preset` = frozen 30–100 path; `custom` = session-geometry path.
  final String layoutMode;

  final String layoutShape;

  /// Build from the subject the teacher selected before opening the scanner.
  ///
  /// Custom subjects must pass [examReadyScanErrorForSubject] first — this
  /// method never invents a substitute grid when the saved layout is invalid.
  static ScannerSessionLayout fromSubject(Subject subject) {
    final OmrLayoutProfile profile;
    if (subject.useCustomLayout) {
      final gate = examReadyScanErrorForSubject(subject);
      if (gate != null) {
        throw StateError(gate);
      }
      profile = subject.scannableCustomLayoutProfile!;
    } else {
      profile = OmrLayoutProfile.preset(subject.totalQuestions);
    }
    final template = profile.grid;
    final geometry = profile.geometry;
    final isCustom = subject.useCustomLayout || profile.isCustom;
    return ScannerSessionLayout(
      templateId: template.templateId,
      columns: template.columns,
      rows: template.rows,
      gridTop: geometry.answerRowsTop,
      gridBottom: geometry.answerRowsBottom,
      rowHeight: template.rowHeight,
      columnWidth: template.columnWidth,
      bubbleSpacingX: template.bubbleSpacingX,
      optionsCount: profile.optionsCount,
      totalQuestions: subject.totalQuestions,
      subjectId: subject.id,
      subjectName: subject.name,
      geometry: geometry,
      isCustom: isCustom,
      layoutMode: isCustom ? 'custom' : 'preset',
      layoutShape: profile.form.id,
    );
  }

  /// Null when OK to print/scan; otherwise a teacher-facing block reason.
  static String? examReadyScanErrorForSubject(Subject subject) {
    if (!subject.useCustomLayout) {
      return null;
    }

    if (subject.customGridColumns == null ||
        subject.customGridRows == null ||
        subject.customGridColumns! < 1 ||
        subject.customGridRows! < 1) {
      return 'This custom sheet is missing its layout grid. '
          'Open Print Sheets and pick the custom layout again before '
          'printing or scanning.';
    }

    final form = subject.layoutForm;
    if (!OmrLayoutProfile.allCustomForms.any((f) => f.id == form.id)) {
      return 'This custom sheet uses a landscape layout that is no longer '
          'supported. Open the custom sheet editor and pick a portrait layout '
          'before printing or scanning.';
    }

    final fit = OmrLayoutProfile.tryComputeExplicitGrid(
      columns: subject.customGridColumns!,
      rows: subject.customGridRows!,
      optionsCount: subject.optionsCount,
      form: form,
      itemCount: subject.totalQuestions,
    );
    if (!fit.isOk) {
      return fit.errorMessage ??
          'This custom sheet layout is no longer scannable. '
              'Pick a different layout or question count.';
    }

    final profile = fit.profile!;
    if (profile.itemCount < subject.totalQuestions) {
      return 'This custom sheet fits ${profile.itemCount} questions, but '
          'the answer key has ${subject.totalQuestions}. '
          'Update the layout or question count before printing or scanning.';
    }

    final gridCapacity =
        subject.customGridColumns! * subject.customGridRows!;
    if (subject.totalQuestions > gridCapacity) {
      return 'This layout grid holds $gridCapacity questions, but '
          'the answer key has ${subject.totalQuestions}.';
    }

    if (profile.grid.rowHeight <
        OmrLayoutProfile.scanMinRowHeight(profile.geometry)) {
      return 'Rows on this sheet are too small to scan reliably. '
          'Pick a larger page size or fewer questions.';
    }
    if (profile.grid.rows > OmrLayoutProfile.maxRowsPerColumn) {
      return 'This layout has too many rows per column to scan reliably. '
          'Pick a layout with more columns or fewer questions.';
    }
    if (profile.grid.columns >
        OmrLayoutProfile.maxColumnsFor(
          form,
          itemCount: subject.totalQuestions,
        )) {
      return 'This layout is too wide to scan reliably on a phone. '
          'Pick a taller layout with at most '
          '${OmrLayoutProfile.maxColumnsFor(form, itemCount: subject.totalQuestions)} '
          'question columns (like the standard sheets).';
    }
    if (profile.grid.columns == 1 && subject.totalQuestions > 25) {
      return 'A single question column is not reliable for this many questions. '
          'Pick a layout with at least 2 columns.';
    }
    final minSpacing =
        OmrLayoutProfile.scanMinBubbleSpacing(form, profile.geometry);
    if (profile.grid.bubbleSpacingX < minSpacing) {
      return 'Bubbles on this sheet are too close together to scan reliably. '
          'Pick a larger page size or fewer answer choices.';
    }
    if (profile.grid.rowHeight <
        profile.geometry.answerBubbleDiameter +
            OmrLayoutProfile.minBubbleVerticalClearance) {
      return 'Answer bubbles would sit too close vertically to scan reliably. '
          'Pick fewer questions or a larger page size.';
    }
    if (!profile.bubblesFitInsideColumns()) {
      return 'Bubbles on this sheet would overlap column edges. '
          'Pick a larger page size, fewer columns, or fewer answer choices.';
    }
    if (!profile.hasAdequateTimingMarks()) {
      return 'This sheet does not have enough timing marks to align the scanner. '
          'Pick a larger page size or fewer questions.';
    }

    return null;
  }

  Map<String, dynamic> toNativeMap() {
    return {
      'template': templateId,
      'cols': columns,
      'rows': rows,
      'gridTop': gridTop,
      'gridBottom': gridBottom,
      'rowHeight': rowHeight,
      'colWidth': columnWidth,
      'bubbleSpacingX': bubbleSpacingX,
      'optionsCount': optionsCount,
      // Explicit identity — native must not infer from question count.
      'isCustom': isCustom,
      'layoutMode': layoutMode,
      'layoutShape': layoutShape,
      'totalQuestions': totalQuestions,
      'subjectId': subjectId,
      // Preset 30–100 keep frozen mark constants; every custom form uses session.
      'useFrozenRegistrationMarks': !isCustom,
      ...geometry.toNativeMap(),
    };
  }
}
