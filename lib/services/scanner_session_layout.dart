import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';

/// Locked layout metadata for an exam scan session.
///
/// Passed to native OMR so each sheet skips QR decode and uses the exact
/// template geometry from the selected answer key / printed sheets.
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
    required this.totalQuestions,
    required this.subjectId,
    required this.subjectName,
  });

  final String templateId;
  final int columns;
  final int rows;
  final double gridTop;
  final double gridBottom;
  final double rowHeight;
  final double columnWidth;
  final double bubbleSpacingX;
  final int totalQuestions;
  final String subjectId;
  final String subjectName;

  /// Build from the subject the teacher selected before opening the scanner.
  static ScannerSessionLayout fromSubject(Subject subject) {
    final template = OmrTemplateSpec.forItemCount(subject.totalQuestions);
    return ScannerSessionLayout(
      templateId: template.templateId,
      columns: template.columns,
      rows: template.rows,
      gridTop: OmrPageConstants.answerRowsTop,
      gridBottom: OmrPageConstants.answerRowsBottom,
      rowHeight: template.rowHeight,
      columnWidth: template.columnWidth,
      bubbleSpacingX: template.bubbleSpacingX,
      totalQuestions: subject.totalQuestions,
      subjectId: subject.id,
      subjectName: subject.name,
    );
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
    };
  }
}
