import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';

/// Locked layout metadata for an exam scan session.
///
/// Passed to native OMR so each sheet skips QR decode and uses the exact
/// template geometry from the selected answer key / printed sheets.
///
/// Identity rule (critical for accuracy):
/// - Standard vs custom is decided by [isCustom] / subject.useCustomLayout —
///   **never** by question count alone.
/// - A custom 30-question sheet must not be treated as frozen template "30".
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
  static ScannerSessionLayout fromSubject(Subject subject) {
    final profile = subject.layoutProfile;
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

    final fit = OmrLayoutProfile.tryComputeExplicitGrid(
      columns: subject.customGridColumns!,
      rows: subject.customGridRows!,
      optionsCount: subject.optionsCount,
      form: subject.layoutForm,
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

    if (profile.grid.rowHeight < OmrLayoutProfile.minRowHeight) {
      return 'Rows on this sheet are too small to scan reliably. '
          'Pick a larger page size or fewer questions.';
    }
    if (profile.grid.bubbleSpacingX < OmrLayoutProfile.minBubbleSpacingX) {
      return 'Bubbles on this sheet are too close together to scan reliably. '
          'Pick a larger page size or fewer answer choices.';
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
      // Preset 30–100 keep frozen mark constants; every custom form uses session.
      'useFrozenRegistrationMarks': !isCustom,
      ...geometry.toNativeMap(),
    };
  }
}
