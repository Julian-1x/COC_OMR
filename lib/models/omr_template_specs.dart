/// OMR Template Specifications
///
/// This file defines the SINGLE SOURCE OF TRUTH for all OMR sheet layouts.
/// Both the PDF generator and the scanner MUST use these exact values.
/// CI checks Android/iOS literals against this file via
/// `test/omr_native_constants_parity_test.dart`.
///
/// Design principles:
/// 1. Fixed page geometry (A4 595x842pt) - never changes
/// 2. Fixed positions for corner markers, timing marks, QR, OMR ID section
/// 3. Only the answer grid varies by template
/// 4. QR encodes layout metadata so scanner doesn't calculate positions

library omr_template_specs;

import 'dart:convert';

// =============================================================================
// PAGE CONSTANTS (shared by all templates)
// =============================================================================

/// A4 page dimensions in PDF points (72 DPI)
class OmrPageConstants {
  OmrPageConstants._();

  // Page size
  static const double pageWidth = 595.0;
  static const double pageHeight = 842.0;

  // Page margins
  static const double marginLeft = 28.0;
  static const double marginTop = 34.0;
  static const double marginRight = 28.0;
  static const double marginBottom = 28.0;

  // Content area (inside margins)
  static const double contentLeft = marginLeft;
  static const double contentTop = marginTop;
  static const double contentWidth =
      pageWidth - marginLeft - marginRight; // 539
  static const double contentHeight =
      pageHeight - marginTop - marginBottom; // 780

  // Corner markers
  static const double cornerMarkerSize = 20.0;
  static const double cornerMarkerOffset = 8.0;

  // Timing marks — positions/spacing are part of the scan contract; do not change
  // without updating Kotlin/iOS and reprinting all sheets.
  static const double timingMarkSize = 6.0;
  static const double timingMarkSpacing = 80.0;
  static const double timingMarkEdgeOffset = 8.0;
  static const double timingMarkStartX = 60.0;
  static const double timingMarkEndX = 535.0;
  static const double timingMarkStartY = 60.0;
  static const double timingMarkEndY = 780.0;

  // QR code position (top-right of header)
  // Lean payload (no layout in QR) + this size keeps modules readable on phones.
  // Must not extend past omrIdTop (114) — do not raise without moving OMR ID.
  static const double qrCodeSize = 80.0;
  static const double qrCodeX = pageWidth - marginRight - qrCodeSize;
  static const double qrCodeY = marginTop;

  // Header section (subject name, code, etc.)
  static const double headerTop = marginTop;
  static const double headerHeight = 80.0;
  static const double headerBottom = headerTop + headerHeight; // 114 = omrIdTop

  // OMR ID section (4-digit student ID bubbles)
  static const double omrIdTop = 114.0; // 8pt below header
  static const double omrIdHeight = 136.0;
  static const double omrIdBottom = omrIdTop + omrIdHeight; // 250
  static const int omrIdColumns = 4;
  static const int omrIdRows = 10; // digits 0-9

  // OMR ID bubble specifications
  static const double omrIdBubbleDiameter = 11.5;
  static const double omrIdBubbleBorder = 1.2;
  static const double omrIdColumnSpacing = 50.0; // center-to-center
  static const double omrIdRowSpacing = 12.0; // center-to-center
  static const double omrIdFirstColumnX = 222.5; // centered first column
  static const double omrIdFirstRowY = 134.0; // center of first row (digit 0)

  // Answer grid section bounds (varies by template, but outer bounds are fixed)
  static const double answerGridTop = 262.0; // 12pt below OMR ID
  static const double answerGridBottom = 800.0; // 28pt above calibration
  static const double answerGridHeight =
      answerGridBottom - answerGridTop; // 538
  static const double answerGridLeft = marginLeft;
  static const double answerGridRight = pageWidth - marginRight;
  static const double answerGridWidth = answerGridRight - answerGridLeft; // 539

  // Answer grid internal layout
  static const double answerHeaderBarHeight =
      0.0; // no internal title bar in active layout
  static const double answerOptionIndicatorHeight = 14.0; // visible A-E labels
  static const double answerGridFooterHeight =
      30.0; // reserve bottom strip for notes
  static const double answerGridContentHeight =
      answerGridHeight - answerOptionIndicatorHeight - answerGridFooterHeight;
  static const double answerRowsTop =
      answerGridTop + answerOptionIndicatorHeight;
  static const double answerRowsBottom =
      answerRowsTop + answerGridContentHeight;

  // Answer bubble specifications
  static const double answerBubbleDiameter = 11.5;
  static const double answerBubbleBorder = 1.2;
  static const int answerOptionsCount = 5; // Standard presets stay at A-E.
  static const List<String> answerOptionLabels = ['A', 'B', 'C', 'D', 'E', 'F'];
  static const double answerColumnInset = 6.0;
  static const double answerNumberBubbleGap = 6.0;

  // Calibration marks (footer)
  static const double calibrationY = 810.0;
  static const double calibrationFilledX = 80.0;
  static const double calibrationEmptyX = 110.0;
  static const double calibrationBubbleSize = 10.0;

  // Question number label width
  static const double questionNumberWidth = 16.0;
}

// =============================================================================
// TEMPLATE DEFINITIONS
// =============================================================================

/// Supported item counts - only these values are allowed
enum OmrItemCount {
  items30(30),
  items40(40),
  items50(50),
  items60(60),
  items70(70),
  items80(80),
  items90(90),
  items100(100);

  const OmrItemCount(this.value);
  final int value;

  /// Get the dedicated production template for this item count.
  OmrTemplateSpec get template {
    switch (this) {
      case OmrItemCount.items30:
        return OmrTemplateSpec.template30;
      case OmrItemCount.items40:
        return OmrTemplateSpec.template40;
      case OmrItemCount.items50:
        return OmrTemplateSpec.template50;
      case OmrItemCount.items60:
        return OmrTemplateSpec.template60;
      case OmrItemCount.items70:
        return OmrTemplateSpec.template70;
      case OmrItemCount.items80:
        return OmrTemplateSpec.template80;
      case OmrItemCount.items90:
        return OmrTemplateSpec.template90;
      case OmrItemCount.items100:
        return OmrTemplateSpec.template100;
    }
  }

  /// Find the appropriate item count for a given number (rounds up).
  static OmrItemCount forQuestionCount(int questions) {
    if (questions <= 30) return items30;
    if (questions <= 40) return items40;
    if (questions <= 50) return items50;
    if (questions <= 60) return items60;
    if (questions <= 70) return items70;
    if (questions <= 80) return items80;
    if (questions <= 90) return items90;
    return items100;
  }
}

/// Template specification for answer grid layout.
class OmrTemplateSpec {
  const OmrTemplateSpec({
    required this.templateId,
    required this.maxItems,
    required this.columns,
    required this.rows,
    required this.rowHeight,
    required this.columnWidth,
    required this.bubbleSpacingX,
    required this.supportedItemCounts,
  });

  /// Template identifier (matches the dedicated supported item count).
  final String templateId;

  /// Maximum items this template supports.
  final int maxItems;

  /// Number of question columns.
  final int columns;

  /// Number of rows per column.
  final int rows;

  /// Height of each row in points (fixed, not calculated).
  final double rowHeight;

  /// Width of each column in points.
  final double columnWidth;

  /// Horizontal spacing between bubble centers within a column.
  final double bubbleSpacingX;

  /// Item counts that use this template.
  final List<int> supportedItemCounts;

  /// Get the X position (center) of a column.
  double columnCenterX(int colIndex) {
    return OmrPageConstants.answerGridLeft +
        (colIndex * columnWidth) +
        (columnWidth / 2);
  }

  /// Get the Y position (center) of a row within the answer grid.
  double rowCenterY(int rowIndex) {
    return OmrPageConstants.answerRowsTop +
        (rowIndex * rowHeight) +
        (rowHeight / 2);
  }

  /// Get the X position (center) of a specific bubble (0=A, 1=B, etc.).
  ///
  /// [optionsCount] defaults to 5 so proven preset sheets keep identical math.
  double bubbleCenterX(
    int colIndex,
    int optionIndex, {
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    final optionSpan = (optionsCount.clamp(2, 6) - 1);
    final columnLeft =
        OmrPageConstants.answerGridLeft + (colIndex * columnWidth);
    final bubbleAreaWidth = bubbleSpacingX * optionSpan;
    final usableWidth = columnWidth - (OmrPageConstants.answerColumnInset * 2);
    final rowContentWidth = OmrPageConstants.questionNumberWidth +
        OmrPageConstants.answerNumberBubbleGap +
        bubbleAreaWidth;
    final rowContentLeft = columnLeft +
        OmrPageConstants.answerColumnInset +
        ((usableWidth - rowContentWidth) / 2);
    final bubbleAreaLeft = rowContentLeft +
        OmrPageConstants.questionNumberWidth +
        OmrPageConstants.answerNumberBubbleGap;
    return bubbleAreaLeft + (optionIndex * bubbleSpacingX);
  }

  /// Get the column and row for a question number (1-based).
  (int col, int row) questionPosition(int questionNumber) {
    final zeroBasedIndex = questionNumber - 1;
    final col = zeroBasedIndex ~/ rows;
    final row = zeroBasedIndex % rows;
    return (col, row);
  }

  /// Get the center position of a specific answer bubble.
  (double x, double y) bubblePosition(
    int questionNumber,
    int optionIndex, {
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    final (col, row) = questionPosition(questionNumber);
    return (
      bubbleCenterX(col, optionIndex, optionsCount: optionsCount),
      rowCenterY(row),
    );
  }

  /// Convert to JSON for QR payload.
  Map<String, dynamic> toJson() => {
        'template': templateId,
        'cols': columns,
        'rows': rows,
        'gridTop': OmrPageConstants.answerRowsTop,
        'gridBottom': OmrPageConstants.answerRowsBottom,
        'rowHeight': rowHeight,
        'colWidth': columnWidth,
        'bubbleSpacingX': bubbleSpacingX,
      };

  /// Create from JSON (from QR payload).
  static OmrTemplateSpec fromJson(Map<String, dynamic> json) {
    final templateId = json['template'] as String;
    return _templates[templateId] ??
        (throw ArgumentError('Unknown template: $templateId'));
  }

  // ---------------------------------------------------------------------------
  // DEDICATED PRODUCTION TEMPLATES
  // ---------------------------------------------------------------------------

  static const template30 = OmrTemplateSpec(
    templateId: '30',
    maxItems: 30,
    columns: 3,
    rows: 10,
    rowHeight: 49.4,
    columnWidth: 179.6666666667,
    bubbleSpacingX: 26.0,
    supportedItemCounts: [30],
  );

  static const template40 = OmrTemplateSpec(
    templateId: '40',
    maxItems: 40,
    columns: 4,
    rows: 10,
    rowHeight: 49.4,
    columnWidth: 134.75,
    bubbleSpacingX: 22.0,
    supportedItemCounts: [40],
  );

  static const template50 = OmrTemplateSpec(
    templateId: '50',
    maxItems: 50,
    columns: 5,
    rows: 10,
    rowHeight: 49.4,
    columnWidth: 107.8,
    bubbleSpacingX: 17.0,
    supportedItemCounts: [50],
  );

  static const template60 = OmrTemplateSpec(
    templateId: '60',
    maxItems: 60,
    columns: 5,
    rows: 12,
    rowHeight: 41.1666666667,
    columnWidth: 107.8,
    bubbleSpacingX: 17.0,
    supportedItemCounts: [60],
  );

  static const template70 = OmrTemplateSpec(
    templateId: '70',
    maxItems: 70,
    columns: 5,
    rows: 14,
    rowHeight: 35.2857142857,
    columnWidth: 107.8,
    bubbleSpacingX: 17.0,
    supportedItemCounts: [70],
  );

  static const template80 = OmrTemplateSpec(
    templateId: '80',
    maxItems: 80,
    columns: 5,
    rows: 16,
    rowHeight: 30.875,
    columnWidth: 107.8,
    bubbleSpacingX: 17.0,
    supportedItemCounts: [80],
  );

  static const template90 = OmrTemplateSpec(
    templateId: '90',
    maxItems: 90,
    columns: 5,
    rows: 18,
    rowHeight: 27.4444444444,
    columnWidth: 107.8,
    bubbleSpacingX: 17.0,
    supportedItemCounts: [90],
  );

  static const template100 = OmrTemplateSpec(
    templateId: '100',
    maxItems: 100,
    columns: 5,
    rows: 20,
    rowHeight: 24.7,
    columnWidth: 107.8,
    bubbleSpacingX: 17.0,
    supportedItemCounts: [100],
  );

  /// All templates indexed by ID.
  static const Map<String, OmrTemplateSpec> _templates = {
    '30': template30,
    '40': template40,
    '50': template50,
    '60': template60,
    '70': template70,
    '80': template80,
    '90': template90,
    '100': template100,
  };

  /// Get template by ID.
  static OmrTemplateSpec? byId(String id) => _templates[id];

  /// Get the appropriate template for an item count.
  static OmrTemplateSpec forItemCount(int itemCount) {
    return OmrItemCount.forQuestionCount(itemCount).template;
  }

  /// All available templates.
  static List<OmrTemplateSpec> get all => [
        template30,
        template40,
        template50,
        template60,
        template70,
        template80,
        template90,
        template100,
      ];
}

// =============================================================================
// CUSTOM LAYOUT PROFILE (additive — does not replace frozen 30–100 presets)
// =============================================================================

/// Portrait (tall) vs landscape (wide).
enum OmrLayoutOrientation {
  lengthwise,
  crosswise;

  String get id => name;
  String get teacherLabel =>
      this == OmrLayoutOrientation.lengthwise ? 'Lengthwise' : 'Crosswise';

  /// Label that matches the phone/tablet print dialog (Portrait / Landscape).
  String get printLabel =>
      this == OmrLayoutOrientation.lengthwise ? 'Portrait' : 'Landscape';

  static OmrLayoutOrientation fromId(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    if (value.contains('cross')) return OmrLayoutOrientation.crosswise;
    return OmrLayoutOrientation.lengthwise;
  }
}

/// How much of the page the quiz block uses.
enum OmrLayoutPageFill {
  full,
  half,
  quarter;

  String get id => name;
  String get teacherLabel {
    switch (this) {
      case OmrLayoutPageFill.full:
        return 'Full page';
      case OmrLayoutPageFill.half:
        return 'Half page';
      case OmrLayoutPageFill.quarter:
        return '1/4 page';
    }
  }

  static OmrLayoutPageFill fromId(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'half':
        return OmrLayoutPageFill.half;
      case 'quarter':
      case '1/4':
      case 'q':
        return OmrLayoutPageFill.quarter;
      default:
        return OmrLayoutPageFill.full;
    }
  }
}

/// Combined form id stored on [Subject.layoutShape] (backward-compatible field).
class OmrLayoutForm {
  const OmrLayoutForm({
    required this.orientation,
    required this.pageFill,
  });

  final OmrLayoutOrientation orientation;
  final OmrLayoutPageFill pageFill;

  String get id => '${orientation.id}_${pageFill.id}';

  /// All six custom forms are scannable when native uses session geometry.
  bool get isExamReadyForScan => true;

  static const String notExamReadyScanMessage =
      'This custom layout could not be locked for scanning. '
      'Re-open Scan from this subject, or pick another saved layout.';

  static OmrLayoutForm fromId(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    // Legacy Compact/Long → lengthwise full.
    if (value == 'compact' || value == 'long' || value.isEmpty) {
      return const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
    }
    final parts = value.split('_');
    if (parts.length >= 2) {
      return OmrLayoutForm(
        orientation: OmrLayoutOrientation.fromId(parts[0]),
        pageFill: OmrLayoutPageFill.fromId(parts.sublist(1).join('_')),
      );
    }
    return OmrLayoutForm(
      orientation: OmrLayoutOrientation.fromId(value),
      pageFill: OmrLayoutPageFill.fromId(value),
    );
  }
}

/// Full page + registration + answer-grid bounds chosen for a layout form.
///
/// Custom sheets use this so print and scanner share the same mark placement.
class OmrSheetGeometry {
  const OmrSheetGeometry({
    required this.pageWidth,
    required this.pageHeight,
    required this.contentBlockWidth,
    required this.contentBlockHeight,
    required this.marginLeft,
    required this.marginTop,
    required this.marginRight,
    required this.marginBottom,
    required this.cornerMarkerSize,
    required this.cornerMarkerOffset,
    required this.timingMarkSize,
    required this.timingMarkSpacing,
    required this.timingMarkEdgeOffset,
    required this.timingMarkStartX,
    required this.timingMarkEndX,
    required this.timingMarkStartY,
    required this.timingMarkEndY,
    required this.headerTop,
    required this.headerHeight,
    required this.omrIdTop,
    required this.omrIdHeight,
    required this.omrIdFirstColumnX,
    required this.omrIdFirstRowY,
    required this.omrIdColumnSpacing,
    required this.omrIdRowSpacing,
    required this.omrIdBubbleDiameter,
    required this.answerGridTop,
    required this.answerGridBottom,
    required this.answerGridLeft,
    required this.answerGridRight,
    required this.answerOptionIndicatorHeight,
    required this.answerGridFooterHeight,
    required this.answerBubbleDiameter,
    required this.answerColumnInset,
    required this.answerNumberBubbleGap,
    required this.questionNumberWidth,
    required this.calibrationY,
    required this.calibrationFilledX,
    required this.calibrationEmptyX,
    required this.calibrationBubbleSize,
    required this.rowMarkX,
    required this.rowMarkSize,
    required this.qrCodeSize,
    required this.qrCodeX,
    required this.qrCodeY,
  });

  final double pageWidth;
  final double pageHeight;

  /// Printed content block the corner markers hug (≤ page for half/¼).
  /// Native warps detected corners to this size so bubble coords stay correct.
  final double contentBlockWidth;
  final double contentBlockHeight;
  final double marginLeft;
  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double cornerMarkerSize;
  final double cornerMarkerOffset;
  final double timingMarkSize;
  final double timingMarkSpacing;
  final double timingMarkEdgeOffset;
  final double timingMarkStartX;
  final double timingMarkEndX;
  final double timingMarkStartY;
  final double timingMarkEndY;
  final double headerTop;
  final double headerHeight;
  final double omrIdTop;
  final double omrIdHeight;
  final double omrIdFirstColumnX;
  final double omrIdFirstRowY;
  final double omrIdColumnSpacing;
  final double omrIdRowSpacing;
  final double omrIdBubbleDiameter;
  final double answerGridTop;
  final double answerGridBottom;
  final double answerGridLeft;
  final double answerGridRight;
  final double answerOptionIndicatorHeight;
  final double answerGridFooterHeight;
  final double answerBubbleDiameter;
  final double answerColumnInset;
  final double answerNumberBubbleGap;
  final double questionNumberWidth;
  final double calibrationY;
  final double calibrationFilledX;
  final double calibrationEmptyX;
  final double calibrationBubbleSize;
  final double rowMarkX;
  final double rowMarkSize;
  final double qrCodeSize;
  final double qrCodeX;
  final double qrCodeY;

  double get answerGridWidth => answerGridRight - answerGridLeft;
  double get answerGridHeight => answerGridBottom - answerGridTop;
  double get answerRowsTop => answerGridTop + answerOptionIndicatorHeight;
  double get answerRowsBottom =>
      answerGridBottom - answerGridFooterHeight;
  double get answerGridContentHeight =>
      answerRowsBottom - answerRowsTop;
  double get contentWidth => pageWidth - marginLeft - marginRight;
  double get headerBottom => headerTop + headerHeight;
  double get omrIdBottom => omrIdTop + omrIdHeight;

  /// Scale factor vs full portrait width (1.0 = frozen 30–100 sheet).
  double get layoutScale => contentBlockWidth / OmrPageConstants.pageWidth;

  /// Whether the PDF page is wider than tall (landscape print).
  bool get isLandscapePrint => pageWidth > pageHeight;

  /// Teacher-facing orientation for the system print dialog.
  String get printOrientationLabel =>
      isLandscapePrint ? 'Landscape' : 'Portrait';

  /// Exact production geometry used by frozen 30–100 sheets.
  factory OmrSheetGeometry.standardPortrait() {
    return const OmrSheetGeometry(
      pageWidth: OmrPageConstants.pageWidth,
      pageHeight: OmrPageConstants.pageHeight,
      contentBlockWidth: OmrPageConstants.pageWidth,
      contentBlockHeight: OmrPageConstants.pageHeight,
      marginLeft: OmrPageConstants.marginLeft,
      marginTop: OmrPageConstants.marginTop,
      marginRight: OmrPageConstants.marginRight,
      marginBottom: OmrPageConstants.marginBottom,
      cornerMarkerSize: OmrPageConstants.cornerMarkerSize,
      cornerMarkerOffset: OmrPageConstants.cornerMarkerOffset,
      timingMarkSize: OmrPageConstants.timingMarkSize,
      timingMarkSpacing: OmrPageConstants.timingMarkSpacing,
      timingMarkEdgeOffset: OmrPageConstants.timingMarkEdgeOffset,
      timingMarkStartX: OmrPageConstants.timingMarkStartX,
      timingMarkEndX: OmrPageConstants.timingMarkEndX,
      timingMarkStartY: OmrPageConstants.timingMarkStartY,
      timingMarkEndY: OmrPageConstants.timingMarkEndY,
      headerTop: OmrPageConstants.headerTop,
      headerHeight: OmrPageConstants.headerHeight,
      omrIdTop: OmrPageConstants.omrIdTop,
      omrIdHeight: OmrPageConstants.omrIdHeight,
      omrIdFirstColumnX: OmrPageConstants.omrIdFirstColumnX,
      omrIdFirstRowY: OmrPageConstants.omrIdFirstRowY,
      omrIdColumnSpacing: OmrPageConstants.omrIdColumnSpacing,
      omrIdRowSpacing: OmrPageConstants.omrIdRowSpacing,
      omrIdBubbleDiameter: OmrPageConstants.omrIdBubbleDiameter,
      answerGridTop: OmrPageConstants.answerGridTop,
      answerGridBottom: OmrPageConstants.answerGridBottom,
      answerGridLeft: OmrPageConstants.answerGridLeft,
      answerGridRight: OmrPageConstants.answerGridRight,
      answerOptionIndicatorHeight: OmrPageConstants.answerOptionIndicatorHeight,
      answerGridFooterHeight: OmrPageConstants.answerGridFooterHeight,
      answerBubbleDiameter: OmrPageConstants.answerBubbleDiameter,
      answerColumnInset: OmrPageConstants.answerColumnInset,
      answerNumberBubbleGap: OmrPageConstants.answerNumberBubbleGap,
      questionNumberWidth: OmrPageConstants.questionNumberWidth,
      calibrationY: OmrPageConstants.calibrationY,
      calibrationFilledX: OmrPageConstants.calibrationFilledX,
      calibrationEmptyX: OmrPageConstants.calibrationEmptyX,
      calibrationBubbleSize: OmrPageConstants.calibrationBubbleSize,
      rowMarkX: OmrRowMarks.markX,
      rowMarkSize: OmrRowMarks.markSize,
      qrCodeSize: OmrPageConstants.qrCodeSize,
      qrCodeX: OmrPageConstants.qrCodeX,
      qrCodeY: OmrPageConstants.qrCodeY,
    );
  }

  /// Dense full-page geometry for high question counts that still stay
  /// phone-scannable (row pitch ≥ [OmrLayoutProfile.minRowHeightDense]).
  ///
  /// Keeps the same registration marks / OMR ID / QR as [standardPortrait],
  /// but reclaims footer strip and uses slightly smaller answer bubbles.
  /// Half/¼ sheets never use this. Counts that would violate scan floors are
  /// rejected — we do not force 200 questions when bubbles would be unsafe.
  factory OmrSheetGeometry.denseFullPortrait() {
    const bubble = 9.5;
    const footer = 8.0;
    const inset = bubble / 2 + 1.0; // 5.75 — outer edge stays inside column
    return const OmrSheetGeometry(
      pageWidth: OmrPageConstants.pageWidth,
      pageHeight: OmrPageConstants.pageHeight,
      contentBlockWidth: OmrPageConstants.pageWidth,
      contentBlockHeight: OmrPageConstants.pageHeight,
      marginLeft: OmrPageConstants.marginLeft,
      marginTop: OmrPageConstants.marginTop,
      marginRight: OmrPageConstants.marginRight,
      marginBottom: OmrPageConstants.marginBottom,
      cornerMarkerSize: OmrPageConstants.cornerMarkerSize,
      cornerMarkerOffset: OmrPageConstants.cornerMarkerOffset,
      timingMarkSize: OmrPageConstants.timingMarkSize,
      timingMarkSpacing: OmrPageConstants.timingMarkSpacing,
      timingMarkEdgeOffset: OmrPageConstants.timingMarkEdgeOffset,
      timingMarkStartX: OmrPageConstants.timingMarkStartX,
      timingMarkEndX: OmrPageConstants.timingMarkEndX,
      timingMarkStartY: OmrPageConstants.timingMarkStartY,
      timingMarkEndY: OmrPageConstants.timingMarkEndY,
      headerTop: OmrPageConstants.headerTop,
      headerHeight: OmrPageConstants.headerHeight,
      omrIdTop: OmrPageConstants.omrIdTop,
      omrIdHeight: OmrPageConstants.omrIdHeight,
      omrIdFirstColumnX: OmrPageConstants.omrIdFirstColumnX,
      omrIdFirstRowY: OmrPageConstants.omrIdFirstRowY,
      omrIdColumnSpacing: OmrPageConstants.omrIdColumnSpacing,
      omrIdRowSpacing: OmrPageConstants.omrIdRowSpacing,
      omrIdBubbleDiameter: OmrPageConstants.omrIdBubbleDiameter,
      answerGridTop: OmrPageConstants.answerGridTop,
      answerGridBottom: OmrPageConstants.answerGridBottom,
      answerGridLeft: OmrPageConstants.answerGridLeft,
      answerGridRight: OmrPageConstants.answerGridRight,
      answerOptionIndicatorHeight: OmrPageConstants.answerOptionIndicatorHeight,
      answerGridFooterHeight: footer,
      answerBubbleDiameter: bubble,
      answerColumnInset: inset,
      answerNumberBubbleGap: 4.0,
      questionNumberWidth: 13.0,
      calibrationY: OmrPageConstants.calibrationY,
      calibrationFilledX: OmrPageConstants.calibrationFilledX,
      calibrationEmptyX: OmrPageConstants.calibrationEmptyX,
      calibrationBubbleSize: OmrPageConstants.calibrationBubbleSize,
      rowMarkX: OmrRowMarks.markX,
      rowMarkSize: OmrRowMarks.markSize,
      qrCodeSize: OmrPageConstants.qrCodeSize,
      qrCodeX: OmrPageConstants.qrCodeX,
      qrCodeY: OmrPageConstants.qrCodeY,
    );
  }

  /// Row marks sit left of the answer grid but must not overlap left-edge timing marks.
  /// Clearance reserves the scanner's row-mark sample half-width (native uses ~markSize).
  static double _rowMarkX({
    required double contentLeft,
    required double timingEdge,
    required double timingSize,
    required double rowMarkSize,
    required double scale,
  }) {
    final leftOfContent = contentLeft - (10 * scale).clamp(6.0, 10.0);
    final sampleHalf = rowMarkSize.clamp(3.0, 6.0);
    final clearOfTiming = timingEdge + timingSize + sampleHalf + 1.0;
    return leftOfContent < clearOfTiming ? clearOfTiming : leftOfContent;
  }

  /// Auto-place page size, content block, and registration marks for a form.
  factory OmrSheetGeometry.forForm(OmrLayoutForm form) {
    final lengthwise =
        form.orientation == OmrLayoutOrientation.lengthwise;
    // Full portrait custom sheets must match the proven 30–100 geometry.
    // Re-deriving OMR ID/footer on scale=1 used to steal answer-band height
    // and block high question counts (including the advertised 200 cap).
    if (lengthwise && form.pageFill == OmrLayoutPageFill.full) {
      return OmrSheetGeometry.standardPortrait();
    }
    final pageWidth =
        lengthwise ? OmrPageConstants.pageWidth : OmrPageConstants.pageHeight;
    final pageHeight =
        lengthwise ? OmrPageConstants.pageHeight : OmrPageConstants.pageWidth;

    // Used block on the page (full / half / quarter). Marks hug this block.
    late final double blockLeft;
    late final double blockTop;
    late final double blockWidth;
    late final double blockHeight;
    switch (form.pageFill) {
      case OmrLayoutPageFill.full:
        blockLeft = 0;
        blockTop = 0;
        blockWidth = pageWidth;
        blockHeight = pageHeight;
        break;
      case OmrLayoutPageFill.half:
        blockLeft = 0;
        blockTop = 0;
        blockWidth = pageWidth;
        blockHeight = pageHeight / 2;
        break;
      case OmrLayoutPageFill.quarter:
        blockLeft = 0;
        blockTop = 0;
        blockWidth = pageWidth / 2;
        blockHeight = pageHeight / 2;
        break;
    }

    final scaleW = blockWidth / OmrPageConstants.pageWidth;
    final scaleH = blockHeight / OmrPageConstants.pageHeight;
    // Half sheets are full-width but half-height — scale must follow the short axis
    // or OMR ID consumes the answer band (exam-day failure).
    final scale = (scaleW < scaleH ? scaleW : scaleH).clamp(0.48, 1.0).toDouble();
    final marginLeft = (OmrPageConstants.marginLeft * scale).clamp(12.0, 28.0);
    final marginRight = (OmrPageConstants.marginRight * scale).clamp(12.0, 28.0);
    final marginTop = (OmrPageConstants.marginTop * scale).clamp(14.0, 34.0);
    final marginBottom =
        (OmrPageConstants.marginBottom * scale).clamp(12.0, 28.0);
    final cornerSize =
        (OmrPageConstants.cornerMarkerSize * scale).clamp(12.0, 20.0);
    final cornerOffset =
        (OmrPageConstants.cornerMarkerOffset * scale).clamp(5.0, 8.0);
    final timingSize =
        (OmrPageConstants.timingMarkSize * scale).clamp(4.0, 6.0);
    final timingEdge =
        (OmrPageConstants.timingMarkEdgeOffset * scale).clamp(5.0, 8.0);

    final contentLeft = blockLeft + marginLeft;
    final contentTop = blockTop + marginTop;
    final contentRight = blockLeft + blockWidth - marginRight;
    final contentBottom = blockTop + blockHeight - marginBottom;
    final contentWidth = contentRight - contentLeft;

    // QR — never shrink below a phone-scannable size on ½/¼ sheets.
    final qrSize = (OmrPageConstants.qrCodeSize * scale)
        .clamp(56.0, OmrPageConstants.qrCodeSize)
        .toDouble();
    final qrCodeX = contentRight - qrSize;
    final qrCodeY = contentTop;

    // Header must clear the QR and two metadata lines.
    final headerHeight = [
      (OmrPageConstants.headerHeight * scale).clamp(52.0, 80.0),
      qrSize + 8.0,
    ].reduce((a, b) => a > b ? a : b);
    final headerTop = contentTop;

    // OMR ID — height derived from bubble grid (10 rows), not a fixed clamp.
    const omrIdTitleBand = 14.0;
    const omrIdDigitRows = OmrPageConstants.omrIdRows;
    final omrBubble =
        (OmrPageConstants.omrIdBubbleDiameter * scale).clamp(8.0, 11.5);
    var omrRowSpacing =
        (OmrPageConstants.omrIdRowSpacing * scale).clamp(8.0, 12.0);
    final maxOmrBlockWidth = contentWidth * 0.94;
    var omrColSpacing =
        (OmrPageConstants.omrIdColumnSpacing * scale).clamp(22.0, 50.0);
    final maxColSpacing =
        (maxOmrBlockWidth - omrBubble) / (OmrPageConstants.omrIdColumns - 1);
    if (omrColSpacing > maxColSpacing) {
      omrColSpacing = maxColSpacing.clamp(18.0, 50.0);
    }
    // Digit masks must not touch: spacing ≥ bubble diameter + 3 pt.
    final minOmrRowSpacing = omrBubble + 3.0;
    if (omrRowSpacing < minOmrRowSpacing) {
      omrRowSpacing = minOmrRowSpacing;
    }
    final omrBlockWidth =
        omrColSpacing * (OmrPageConstants.omrIdColumns - 1) + omrBubble;
    var omrIdHeight = omrIdTitleBand +
        omrBubble +
        (omrIdDigitRows - 1) * omrRowSpacing +
        8.0;
    final omrIdTop =
        headerTop + headerHeight + (6 * scale).clamp(4.0, 8.0);
    var omrIdFirstRowY = omrIdTop + omrIdTitleBand + (omrBubble / 2);
    final omrIdFirstColumnX =
        contentLeft + ((contentWidth - omrBlockWidth) / 2);

    final footerReserve =
        (OmrPageConstants.answerGridFooterHeight * scale).clamp(16.0, 30.0);
    final optionBar =
        (OmrPageConstants.answerOptionIndicatorHeight * scale).clamp(10.0, 14.0);
    var answerGridTop =
        omrIdTop + omrIdHeight + (10 * scale).clamp(6.0, 12.0);
    var answerGridBottom = contentBottom - footerReserve;
    final answerGridLeft = contentLeft;
    final answerGridRight = contentRight;

    // If the block is very tight, compress OMR row spacing before overlapping.
    // Never go below digit-mask clearance — better to shrink answer area / reject.
    final minAnswerGridHeight = 48.0;
    final availableForAnswers =
        answerGridBottom - answerGridTop - optionBar - footerReserve;
    if (availableForAnswers < minAnswerGridHeight) {
      final deficit = minAnswerGridHeight - availableForAnswers;
      final spacingShrink = deficit / (omrIdDigitRows - 1);
      final shrunk = omrRowSpacing - spacingShrink;
      final upper = minOmrRowSpacing > 12.0 ? minOmrRowSpacing : 12.0;
      omrRowSpacing = shrunk.clamp(minOmrRowSpacing, upper);
      omrIdHeight = omrIdTitleBand +
          omrBubble +
          (omrIdDigitRows - 1) * omrRowSpacing +
          8.0;
      omrIdFirstRowY = omrIdTop + omrIdTitleBand + (omrBubble / 2);
      answerGridTop =
          omrIdTop + omrIdHeight + (10 * scale).clamp(6.0, 12.0);
    }

    final answerRowsTop = answerGridTop + optionBar;
    final answerRowsBottom = answerGridBottom - footerReserve;

    // Timing marks span the answer grid vertically (scanner registration band).
    final timingInsetX =
        (OmrPageConstants.timingMarkStartX * scale).clamp(20.0, 60.0);
    final timingStartX = blockLeft + timingInsetX;
    final timingEndX = blockLeft + blockWidth - timingInsetX;
    final gridBandTop = (answerRowsTop - (14 * scale).clamp(8.0, 14.0))
        .clamp(blockTop + timingEdge, blockTop + blockHeight - timingEdge);
    final gridBandBottom = (answerRowsBottom + (14 * scale).clamp(8.0, 14.0))
        .clamp(blockTop + timingEdge, blockTop + blockHeight - timingEdge);
    final timingStartY = gridBandTop;
    final timingEndY = gridBandBottom;
    final gridSpan = (timingEndY - timingStartY).clamp(40.0, blockHeight);
    var timingSpacing = (OmrPageConstants.timingMarkSpacing * scale).clamp(
      24.0,
      (gridSpan / 3).clamp(24.0, 80.0),
    );
    // Scanner needs ≥4 marks per edge; tighten spacing if the band is short.
    final xSpan = (timingEndX - timingStartX).clamp(40.0, blockWidth);
    final ySpan = (timingEndY - timingStartY).clamp(40.0, blockHeight);
    final maxSpacingForFourX = xSpan / 3.0;
    final maxSpacingForFourY = ySpan / 3.0;
    if (timingSpacing > maxSpacingForFourX) {
      timingSpacing = maxSpacingForFourX.clamp(16.0, timingSpacing);
    }
    if (timingSpacing > maxSpacingForFourY) {
      timingSpacing = maxSpacingForFourY.clamp(16.0, timingSpacing);
    }

    final answerBubble =
        (OmrPageConstants.answerBubbleDiameter * scale).clamp(8.0, 11.5);
    // Keep calibration fully inside the printable block (≈4 pt printer bleed).
    final calSize =
        (OmrPageConstants.calibrationBubbleSize * scale).clamp(7.0, 10.0);
    const printerBleed = 4.0;
    final calY = (contentBottom - (calSize / 2) - printerBleed)
        .clamp(contentTop + 20.0, contentBottom - (calSize / 2));
    final answerColumnInset = [
      (OmrPageConstants.answerColumnInset * scale).clamp(3.0, 6.0),
      answerBubble / 2 + 1.0,
    ].reduce((a, b) => a > b ? a : b);

    return OmrSheetGeometry(
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      contentBlockWidth: blockWidth,
      contentBlockHeight: blockHeight,
      marginLeft: marginLeft,
      marginTop: marginTop,
      marginRight: marginRight,
      marginBottom: marginBottom,
      cornerMarkerSize: cornerSize,
      cornerMarkerOffset: cornerOffset,
      timingMarkSize: timingSize,
      timingMarkSpacing: timingSpacing,
      timingMarkEdgeOffset: timingEdge,
      timingMarkStartX: timingStartX,
      timingMarkEndX: timingEndX,
      timingMarkStartY: timingStartY,
      timingMarkEndY: timingEndY,
      headerTop: headerTop,
      headerHeight: headerHeight,
      omrIdTop: omrIdTop,
      omrIdHeight: omrIdHeight,
      omrIdFirstColumnX: omrIdFirstColumnX,
      omrIdFirstRowY: omrIdFirstRowY,
      omrIdColumnSpacing: omrColSpacing,
      omrIdRowSpacing: omrRowSpacing,
      omrIdBubbleDiameter: omrBubble,
      answerGridTop: answerGridTop,
      answerGridBottom: answerGridBottom,
      answerGridLeft: answerGridLeft,
      answerGridRight: answerGridRight,
      answerOptionIndicatorHeight: optionBar,
      answerGridFooterHeight: footerReserve,
      answerBubbleDiameter: answerBubble,
      answerColumnInset: answerColumnInset,
      answerNumberBubbleGap:
          (OmrPageConstants.answerNumberBubbleGap * scale).clamp(3.0, 6.0),
      questionNumberWidth:
          (OmrPageConstants.questionNumberWidth * scale).clamp(10.0, 16.0),
      calibrationY: calY,
      calibrationFilledX: contentLeft + (52 * scale).clamp(24.0, 52.0),
      calibrationEmptyX: contentLeft + (82 * scale).clamp(40.0, 82.0),
      calibrationBubbleSize: calSize,
      rowMarkX: OmrSheetGeometry._rowMarkX(
        contentLeft: contentLeft,
        timingEdge: timingEdge,
        timingSize: timingSize,
        rowMarkSize: (OmrRowMarks.markSize * scale).clamp(3.0, 4.0),
        scale: scale,
      ),
      rowMarkSize: (OmrRowMarks.markSize * scale).clamp(3.0, 4.0),
      qrCodeSize: qrSize,
      qrCodeX: qrCodeX,
      qrCodeY: qrCodeY,
    );
  }

  Map<String, dynamic> toNativeMap() => {
        'pageWidth': pageWidth,
        'pageHeight': pageHeight,
        'contentBlockWidth': contentBlockWidth,
        'contentBlockHeight': contentBlockHeight,
        'answerGridLeft': answerGridLeft,
        'answerGridRight': answerGridRight,
        'answerRowsTop': answerRowsTop,
        'answerRowsBottom': answerRowsBottom,
        'answerColumnInset': answerColumnInset,
        'answerNumberBubbleGap': answerNumberBubbleGap,
        'questionNumberWidth': questionNumberWidth,
        'answerBubbleDiameter': answerBubbleDiameter,
        'cornerMarkerSize': cornerMarkerSize,
        'cornerMarkerOffset': cornerMarkerOffset,
        'timingMarkSize': timingMarkSize,
        'timingMarkSpacing': timingMarkSpacing,
        'timingMarkEdgeOffset': timingMarkEdgeOffset,
        'timingMarkStartX': timingMarkStartX,
        'timingMarkEndX': timingMarkEndX,
        'timingMarkStartY': timingMarkStartY,
        'timingMarkEndY': timingMarkEndY,
        'rowMarkX': rowMarkX,
        'rowMarkSize': rowMarkSize,
        'omrIdFirstColumnX': omrIdFirstColumnX,
        'omrIdFirstRowY': omrIdFirstRowY,
        'omrIdColumnSpacing': omrIdColumnSpacing,
        'omrIdRowSpacing': omrIdRowSpacing,
        'omrIdBubbleDiameter': omrIdBubbleDiameter,
        'calibrationY': calibrationY,
        'calibrationFilledX': calibrationFilledX,
        'calibrationEmptyX': calibrationEmptyX,
        'calibrationBubbleSize': calibrationBubbleSize,
        'qrCodeX': qrCodeX,
        'qrCodeY': qrCodeY,
        'qrCodeSize': qrCodeSize,
      };
}

/// How many custom-sheet tiles fit on one bond page at 100% scale (no shrinking).
///
/// Half-page layouts → 2 per page; quarter → 4. Full page → not tileable.
class OmrSheetTiling {
  const OmrSheetTiling({
    required this.columns,
    required this.rows,
  });

  final int columns;
  final int rows;

  static const double _epsilon = 0.05;

  int get sheetsPerPage => columns * rows;

  String get savePaperLabel {
    switch (sheetsPerPage) {
      case 4:
        return '4 answer sheets per bond paper';
      case 2:
        return '2 answer sheets per bond paper';
      default:
        return '$sheetsPerPage answer sheets per bond paper';
    }
  }

  String get savePaperSubtitle =>
      'Each sheet is printed at full size — use 100% scale (Actual size), not Fit to page. '
      'Light guides show where to cut or fold.';

  /// Tile offsets for slot index 0 … [sheetsPerPage] − 1 (left-to-right, top-to-bottom).
  double tileOffsetX(int slotIndex, OmrSheetGeometry geometry) =>
      (slotIndex % columns) * geometry.contentBlockWidth;

  double tileOffsetY(int slotIndex, OmrSheetGeometry geometry) =>
      (slotIndex ~/ columns) * geometry.contentBlockHeight;

  /// Returns null when the block does not divide the page evenly or only one fits.
  static OmrSheetTiling? forGeometry(OmrSheetGeometry geometry) {
    final blockW = geometry.contentBlockWidth;
    final blockH = geometry.contentBlockHeight;
    final pageW = geometry.pageWidth;
    final pageH = geometry.pageHeight;

    if (blockW <= 0 || blockH <= 0) {
      return null;
    }
    if (!_dividesEvenly(pageW, blockW) || !_dividesEvenly(pageH, blockH)) {
      return null;
    }

    final columns = (pageW / blockW).round();
    final rows = (pageH / blockH).round();
    if (columns < 1 || rows < 1) {
      return null;
    }

    final sheetsPerPage = columns * rows;
    if (sheetsPerPage <= 1) {
      return null;
    }

    // Guard against float drift — tiles must exactly fill the page.
    if ((columns * blockW - pageW).abs() > _epsilon ||
        (rows * blockH - pageH).abs() > _epsilon) {
      return null;
    }

    return OmrSheetTiling(columns: columns, rows: rows);
  }

  static bool _dividesEvenly(double total, double part) {
    final count = total / part;
    final rounded = count.round();
    if (rounded < 1) {
      return false;
    }
    return (rounded * part - total).abs() <= _epsilon;
  }
}

/// Result of trying to fit a Custom sheet.
class OmrLayoutFitResult {
  const OmrLayoutFitResult.ok(this.profile) : errorMessage = null;
  const OmrLayoutFitResult.fail(this.errorMessage) : profile = null;

  final OmrLayoutProfile? profile;
  final String? errorMessage;

  bool get isOk => profile != null;
}

/// How strongly we recommend a layout for exam-day scanning.
enum OmrLayoutSuggestionTier {
  recommended,
  workable,
  tight;

  String get pickerLabel {
    switch (this) {
      case OmrLayoutSuggestionTier.recommended:
        return 'Recommended';
      case OmrLayoutSuggestionTier.workable:
        return 'Also works';
      case OmrLayoutSuggestionTier.tight:
        return 'Tight layout';
    }
  }
}

/// One scannable layout option for the guided custom-sheet picker.
class OmrLayoutSuggestion {
  const OmrLayoutSuggestion({
    required this.form,
    required this.profile,
    required this.tier,
    required this.title,
    required this.subtitle,
  });

  final OmrLayoutForm form;
  final OmrLayoutProfile profile;
  final OmrLayoutSuggestionTier tier;
  final String title;
  final String subtitle;

  String get id => form.id;
}

/// A scan-safe columns × rows choice for a fixed question count.
class OmrAvailableGridSize {
  const OmrAvailableGridSize({
    required this.columns,
    required this.rows,
  });

  final int columns;
  final int rows;

  int get capacity => columns * rows;

  String get label => '$columns × $rows';

  String get detail =>
      '$columns question columns · $rows rows each · $capacity questions';
}

/// A page/orientation combo that cannot fit the requested quiz.
class OmrLayoutBlockedOption {
  const OmrLayoutBlockedOption({
    required this.form,
    required this.reason,
  });

  final OmrLayoutForm form;
  final String reason;

  String get title {
    final orientation = form.orientation.printLabel;
    final size = form.pageFill.teacherLabel;
    return '$orientation · $size';
  }
}

/// Resolved print/scan layout for a subject.
class OmrLayoutProfile {
  const OmrLayoutProfile({
    required this.grid,
    required this.optionsCount,
    required this.isCustom,
    required this.form,
    required this.itemCount,
    required this.geometry,
  });

  final OmrTemplateSpec grid;
  final int optionsCount;
  final bool isCustom;
  final OmrLayoutForm form;
  final int itemCount;
  final OmrSheetGeometry geometry;

  static const int minCustomItems = 5;
  static const int maxCustomItems = 200;
  /// Preferred row pitch for comfortable phone fill detection.
  static const double minRowHeight = 20.0;
  /// Dense full-page absolute floor — still phone-scannable (not merely printable).
  /// Kept well above bubble diameter so fill detection has vertical clearance.
  static const double minRowHeightDense = 16.0;
  /// Extra slack above [minRowHeightDense] so packs never pinch the floor
  /// (printer scale + phone framing variance).
  static const double densePackMargin = 0.5;
  /// Preferred option-bubble gap for roomy packs.
  static const double minBubbleSpacingX = 12.5;
  /// Dense full-page option gap — close to roomy floor so neighbors stay distinct.
  static const double minBubbleSpacingXDense = 11.5;
  /// Extra slack above dense option spacing (same rationale as [densePackMargin]).
  static const double denseSpacingMargin = 0.5;
  static const double minBubbleSpacingXQuarter = 14.0;
  static const double preferredMaxBubbleSpacingX = 26.0;
  /// Minimum (rowHeight − bubbleDiameter) so stacked bubbles do not touch.
  static const double minBubbleVerticalClearance = 4.0;
  /// Cap rows per column so sheets stay frameable and row marks stay distinct.
  /// Matches dense full-page height ÷ (minRowHeightDense + densePackMargin).
  static const int maxRowsPerColumn = 31;
  /// Preferred portrait column count — matches proven 30/60/100 family.
  static const int maxColumnsLengthwise = 5;
  /// Extra columns allowed only when Q count exceeds 5×[maxRowsPerColumn].
  /// Still capped so packs stay tall (not 10-wide strips).
  static const int absoluteMaxColumnsLengthwise = 8;
  static const int maxColumnsQuarter = 4;
  /// Prefer packs with at least this many rows when an even alternative exists.
  static const int minBalancedRows = 6;

  static bool _isFullLengthwise(OmrLayoutForm form) =>
      form.orientation == OmrLayoutOrientation.lengthwise &&
      form.pageFill == OmrLayoutPageFill.full;

  /// Column cap so phone framing stays vertical like standard sheets.
  /// [itemCount] may raise the cap slightly for very high Q counts only.
  static int maxColumnsFor(OmrLayoutForm form, {int itemCount = 0}) {
    if (form.orientation == OmrLayoutOrientation.crosswise) {
      return 6;
    }
    if (form.pageFill == OmrLayoutPageFill.quarter) {
      return maxColumnsQuarter;
    }
    if (itemCount <= 0) {
      return maxColumnsLengthwise;
    }
    final preferredCapacity = maxColumnsLengthwise * maxRowsPerColumn;
    if (itemCount <= preferredCapacity) {
      return maxColumnsLengthwise;
    }
    final needed = (itemCount / maxRowsPerColumn).ceil();
    if (needed <= maxColumnsLengthwise) {
      return maxColumnsLengthwise;
    }
    return needed.clamp(maxColumnsLengthwise, absoluteMaxColumnsLengthwise);
  }

  /// Tighter sheets need wider bubble gaps to avoid neighbor misreads.
  static double minBubbleSpacingXFor(OmrLayoutForm form) =>
      form.pageFill == OmrLayoutPageFill.quarter
          ? minBubbleSpacingXQuarter
          : minBubbleSpacingX;

  /// Scan floors for a resolved profile (dense sheets use smaller bubbles).
  static double scanMinRowHeight(OmrSheetGeometry geometry) {
    final clearanceFloor =
        geometry.answerBubbleDiameter + minBubbleVerticalClearance;
    final packFloor =
        geometry.answerBubbleDiameter < OmrPageConstants.answerBubbleDiameter
            ? minRowHeightDense + densePackMargin
            : minRowHeight;
    return clearanceFloor > packFloor ? clearanceFloor : packFloor;
  }

  static double scanMinBubbleSpacing(
    OmrLayoutForm form,
    OmrSheetGeometry geometry,
  ) {
    if (form.pageFill == OmrLayoutPageFill.quarter) {
      return minBubbleSpacingXQuarter;
    }
    if (geometry.answerBubbleDiameter < OmrPageConstants.answerBubbleDiameter) {
      return minBubbleSpacingXDense + denseSpacingMargin;
    }
    return minBubbleSpacingX;
  }

  /// True when a candidate grid is safe for phone fill detection.
  static bool _rowPitchScannable({
    required double rowHeight,
    required OmrSheetGeometry geometry,
    required double minRow,
  }) {
    if (rowHeight < minRow) {
      return false;
    }
    if (rowHeight <
        geometry.answerBubbleDiameter + minBubbleVerticalClearance) {
      return false;
    }
    return true;
  }

  /// Deprecated alias used by older UI code paths.
  OmrLayoutShape get shape => form.pageFill == OmrLayoutPageFill.full &&
          form.orientation == OmrLayoutOrientation.lengthwise
      ? OmrLayoutShape.compact
      : OmrLayoutShape.long;

  List<String> get optionLabels =>
      OmrPageConstants.answerOptionLabels.take(optionsCount.clamp(2, 6)).toList();

  String get previewLabel => isCustom
      ? 'Custom $itemCount · $optionsCount opts · '
          '${geometry.printOrientationLabel} · ${form.pageFill.teacherLabel} '
          '(${grid.columns}×${grid.rows})'
      : 'Standard $itemCount (${grid.columns}×${grid.rows})';

  /// Non-default layouts need an explicit print-orientation reminder.
  bool get shouldConfirmPrintOrientation =>
      isCustom ||
      form.orientation != OmrLayoutOrientation.lengthwise ||
      form.pageFill != OmrLayoutPageFill.full;

  String get printOrientationReminder {
    final orientation = geometry.printOrientationLabel;
    final sizeNote = form.pageFill == OmrLayoutPageFill.full
        ? orientation
        : '$orientation · ${form.pageFill.teacherLabel}';
    final frameTip = form.pageFill == OmrLayoutPageFill.full
        ? ''
        : ' When scanning, fill the camera frame with the printed '
            '${form.pageFill.teacherLabel.toLowerCase()} area only (not blank paper).';
    return 'Print in $orientation. On the print screen, keep Orientation on '
        '$orientation ($sizeNote). Do not rotate the page — wrong orientation '
        'breaks scanning.$frameTip';
  }

  factory OmrLayoutProfile.preset(int itemCount) {
    final template = OmrTemplateSpec.forItemCount(itemCount);
    return OmrLayoutProfile(
      grid: template,
      optionsCount: OmrPageConstants.answerOptionsCount,
      isCustom: false,
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
      itemCount: itemCount,
      geometry: OmrSheetGeometry.standardPortrait(),
    );
  }

  factory OmrLayoutProfile.resolve({
    required int totalQuestions,
    bool useCustomLayout = false,
    int optionsCount = OmrPageConstants.answerOptionsCount,
    OmrLayoutForm? form,
    OmrLayoutShape? shape,
  }) {
    final opts = optionsCount.clamp(2, 6);
    final resolvedForm = form ??
        (shape != null
            ? OmrLayoutForm.fromId(shape.id)
            : const OmrLayoutForm(
                orientation: OmrLayoutOrientation.lengthwise,
                pageFill: OmrLayoutPageFill.full,
              ));

    if (!useCustomLayout) {
      return OmrLayoutProfile.preset(totalQuestions);
    }

    // Exact proven sheet when Custom mirrors standard lengthwise full + 5 opts.
    final exactPreset = OmrTemplateSpec.byId('$totalQuestions');
    if (exactPreset != null &&
        opts == OmrPageConstants.answerOptionsCount &&
        resolvedForm.orientation == OmrLayoutOrientation.lengthwise &&
        resolvedForm.pageFill == OmrLayoutPageFill.full) {
      return OmrLayoutProfile(
        grid: exactPreset,
        optionsCount: opts,
        isCustom: true,
        form: resolvedForm,
        itemCount: totalQuestions,
        geometry: OmrSheetGeometry.standardPortrait(),
      );
    }

    final fit = tryCompute(
      itemCount: totalQuestions,
      optionsCount: opts,
      form: resolvedForm,
    );
    if (fit.profile != null) {
      return fit.profile!;
    }

    // Never fall back to a standard preset while Custom is on — that would
    // print/scan the wrong sheet. Clamp to this form's safe capacity instead.
    final capped = maxFitItems(form: resolvedForm, optionsCount: opts);
    if (capped >= minCustomItems) {
      final clamped = tryCompute(
        itemCount: capped,
        optionsCount: opts,
        form: resolvedForm,
      );
      if (clamped.profile != null) {
        return clamped.profile!;
      }
    }

    // Last resort: still stay on this form's geometry with minimum items.
    final minimal = tryCompute(
      itemCount: minCustomItems,
      optionsCount: opts,
      form: resolvedForm,
    );
    if (minimal.profile != null) {
      return minimal.profile!;
    }

    // Geometry itself is unusable — keep Custom flags but use empty-safe preset
    // only so callers do not crash; UI/save must already block this case.
    return OmrLayoutProfile.preset(totalQuestions);
  }

  /// Conservative exam-day caps on top of pure geometry packing.
  /// Smaller sheets get lower limits so bubbles stay scannable.
  static int safetyCapForForm(OmrLayoutForm form) {
    switch (form.pageFill) {
      case OmrLayoutPageFill.full:
        return 200;
      case OmrLayoutPageFill.half:
        return form.orientation == OmrLayoutOrientation.crosswise ? 70 : 90;
      case OmrLayoutPageFill.quarter:
        return form.orientation == OmrLayoutOrientation.crosswise ? 12 : 15;
    }
  }

  /// Portrait forms the engine still understands, including legacy half/quarter
  /// layouts that were already saved or printed.
  static const List<OmrLayoutForm> allCustomForms = _allCustomForms;

  /// Forms offered when creating or changing a custom sheet.
  ///
  /// Full portrait only. Half and quarter print 2–4 sheets per bond page and
  /// force teachers to tilt or zoom the camera to fill the frame — too hard
  /// on exam day. Landscape/crosswise is also not offered.
  static const List<OmrLayoutForm> teacherSelectableCustomForms = [
    OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.full,
    ),
  ];

  static const List<OmrLayoutForm> _allCustomForms = [
    OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.full,
    ),
    OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.half,
    ),
    OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.quarter,
    ),
  ];

  static OmrLayoutSuggestionTier _tierForForm(OmrLayoutForm form) {
    if (form.orientation == OmrLayoutOrientation.lengthwise &&
        form.pageFill == OmrLayoutPageFill.full) {
      return OmrLayoutSuggestionTier.recommended;
    }
    if (form.pageFill == OmrLayoutPageFill.quarter) {
      return OmrLayoutSuggestionTier.tight;
    }
    return OmrLayoutSuggestionTier.workable;
  }

  static int _formSortKey(OmrLayoutForm form) {
    var key = _tierForForm(form).index * 10;
    if (form.orientation == OmrLayoutOrientation.lengthwise) {
      key += 0;
    } else {
      key += 3;
    }
    switch (form.pageFill) {
      case OmrLayoutPageFill.full:
        key += 0;
        break;
      case OmrLayoutPageFill.half:
        key += 1;
        break;
      case OmrLayoutPageFill.quarter:
        key += 2;
        break;
    }
    return key;
  }

  static String _suggestionTitle(OmrLayoutForm form, OmrLayoutProfile profile) {
    return '${form.orientation.printLabel} · ${form.pageFill.teacherLabel} · '
        '${profile.grid.columns}×${profile.grid.rows} grid';
  }

  static String _suggestionSubtitle(
    OmrLayoutForm form,
    OmrLayoutSuggestionTier tier,
  ) {
    switch (tier) {
      case OmrLayoutSuggestionTier.recommended:
        return 'Best for scanning — one full portrait sheet, phone upright.';
      case OmrLayoutSuggestionTier.workable:
        if (form.pageFill == OmrLayoutPageFill.half) {
          return 'Two sheets per bond page — fill the camera with the printed half only.';
        }
        return 'Good for short quizzes — keep the phone upright while scanning.';
      case OmrLayoutSuggestionTier.tight:
        if (form.pageFill == OmrLayoutPageFill.quarter) {
          return 'Four sheets per bond page — fill the frame with the printed ¼ only.';
        }
        return 'Compact layout — bubbles are closer together; scan carefully.';
    }
  }

  /// Ranked scannable layouts for a question count + choice count.
  static List<OmrLayoutSuggestion> suggestLayouts({
    required int itemCount,
    required int optionsCount,
  }) {
    final suggestions = <OmrLayoutSuggestion>[];
    for (final form in teacherSelectableCustomForms) {
      final fit = tryCompute(
        itemCount: itemCount,
        optionsCount: optionsCount,
        form: form,
      );
      if (!fit.isOk || fit.profile == null) {
        continue;
      }
      final tier = _tierForForm(form);
      suggestions.add(
        OmrLayoutSuggestion(
          form: form,
          profile: fit.profile!,
          tier: tier,
          title: _suggestionTitle(form, fit.profile!),
          subtitle: _suggestionSubtitle(form, tier),
        ),
      );
    }
    suggestions.sort(
      (a, b) => _formSortKey(a.form).compareTo(_formSortKey(b.form)),
    );
    return suggestions;
  }

  /// Layout combos that do not fit the requested quiz.
  static List<OmrLayoutBlockedOption> blockedLayouts({
    required int itemCount,
    required int optionsCount,
  }) {
    final validIds =
        suggestLayouts(itemCount: itemCount, optionsCount: optionsCount)
            .map((s) => s.id)
            .toSet();
    final blocked = <OmrLayoutBlockedOption>[];
    for (final form in teacherSelectableCustomForms) {
      if (validIds.contains(form.id)) {
        continue;
      }
      final fit = tryCompute(
        itemCount: itemCount,
        optionsCount: optionsCount,
        form: form,
      );
      blocked.add(
        OmrLayoutBlockedOption(
          form: form,
          reason: fit.errorMessage ??
              'This combination is not scannable for $itemCount questions.',
        ),
      );
    }
    blocked.sort(
      (a, b) => _formSortKey(a.form).compareTo(_formSortKey(b.form)),
    );
    return blocked;
  }

  /// Print sizes that fit an instructor-chosen columns × rows grid.
  static List<OmrLayoutSuggestion> suggestExplicitGridLayouts({
    required int columns,
    required int rows,
    required int optionsCount,
  }) {
    final suggestions = <OmrLayoutSuggestion>[];
    for (final form in teacherSelectableCustomForms) {
      final fit = tryComputeExplicitGrid(
        columns: columns,
        rows: rows,
        optionsCount: optionsCount,
        form: form,
      );
      if (!fit.isOk || fit.profile == null) {
        continue;
      }
      final tier = _tierForForm(form);
      suggestions.add(
        OmrLayoutSuggestion(
          form: form,
          profile: fit.profile!,
          tier: tier,
          title: _suggestionTitle(form, fit.profile!),
          subtitle: _suggestionSubtitle(form, tier),
        ),
      );
    }
    suggestions.sort(
      (a, b) => _formSortKey(a.form).compareTo(_formSortKey(b.form)),
    );
    return suggestions;
  }

  /// Print sizes blocked for an instructor-chosen columns × rows grid.
  static List<OmrLayoutBlockedOption> blockedExplicitGridLayouts({
    required int columns,
    required int rows,
    required int optionsCount,
  }) {
    final validIds = suggestExplicitGridLayouts(
      columns: columns,
      rows: rows,
      optionsCount: optionsCount,
    ).map((s) => s.id).toSet();
    final blocked = <OmrLayoutBlockedOption>[];
    for (final form in teacherSelectableCustomForms) {
      if (validIds.contains(form.id)) {
        continue;
      }
      final fit = tryComputeExplicitGrid(
        columns: columns,
        rows: rows,
        optionsCount: optionsCount,
        form: form,
      );
      blocked.add(
        OmrLayoutBlockedOption(
          form: form,
          reason: fit.errorMessage ??
              'This grid is not scannable on this page size.',
        ),
      );
    }
    blocked.sort(
      (a, b) => _formSortKey(a.form).compareTo(_formSortKey(b.form)),
    );
    return blocked;
  }

  /// Even-fill grids (columns × rows = [itemCount]) that stay scan-safe
  /// on at least one custom print size. Used when the teacher sets questions
  /// first, then picks from available sizes only.
  static List<OmrAvailableGridSize> availableGridSizes({
    required int itemCount,
    required int optionsCount,
  }) {
    final items = itemCount;
    final opts = optionsCount.clamp(2, 6);
    if (items < minCustomItems || items > maxCustomItems) {
      return const [];
    }

    final out = <OmrAvailableGridSize>[];
    final maxCols = maxColumnsFor(
      const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
      itemCount: items,
    );
    for (var columns = 1; columns <= maxCols; columns++) {
      if (items % columns != 0) {
        continue;
      }
      final rows = items ~/ columns;
      if (rows < 1 || rows > maxRowsPerColumn) {
        continue;
      }
      if (columns == 1 && items > 25) {
        continue;
      }
      final fits = suggestExplicitGridLayouts(
        columns: columns,
        rows: rows,
        optionsCount: opts,
      );
      if (fits.isEmpty) {
        continue;
      }
      out.add(OmrAvailableGridSize(columns: columns, rows: rows));
    }

    // Prefer standard-like column counts (5, 4, 3…) — tall vertical packs.
    const preferred = [5, 4, 3, 2, 6, 7, 8, 1];
    int rank(int columns) {
      final index = preferred.indexOf(columns);
      return index >= 0 ? index : preferred.length + columns;
    }

    out.sort((a, b) {
      final byPreferred = rank(a.columns).compareTo(rank(b.columns));
      if (byPreferred != 0) {
        return byPreferred;
      }
      return a.rows.compareTo(b.rows);
    });
    return out;
  }

  static OmrLayoutFitResult tryCompute({
    required int itemCount,
    required int optionsCount,
    required OmrLayoutForm form,
    OmrLayoutShape? shape,
  }) {
    final resolvedForm = shape != null ? OmrLayoutForm.fromId(shape.id) : form;
    final items = itemCount;
    final opts = optionsCount.clamp(2, 6);
    if (items < minCustomItems) {
      return OmrLayoutFitResult.fail(
        'Custom sheets need at least $minCustomItems questions.',
      );
    }
    if (items > maxCustomItems) {
      return OmrLayoutFitResult.fail(
        'Custom sheets support at most $maxCustomItems questions. '
        'Use a proven standard sheet when it matches, or fewer questions.',
      );
    }

    final maxFit = maxFitItems(form: resolvedForm, optionsCount: opts);
    if (maxFit < minCustomItems) {
      return OmrLayoutFitResult.fail(
        'A ${resolvedForm.pageFill.teacherLabel.toLowerCase()} '
        '${resolvedForm.orientation.teacherLabel.toLowerCase()} sheet '
        'is too small for scannable bubbles. Use a full portrait page.',
      );
    }
    if (items > maxFit) {
      return OmrLayoutFitResult.fail(
        'A ${resolvedForm.pageFill.teacherLabel.toLowerCase()} '
        '${resolvedForm.orientation.teacherLabel.toLowerCase()} sheet '
        'with $opts choices can fit at most $maxFit questions. '
        'You asked for $items — use Full page, fewer questions, or fewer choices.',
      );
    }

    final packed = _packBestAcrossGeometries(
      items: items,
      opts: opts,
      form: resolvedForm,
    );
    if (packed.isOk) {
      return packed;
    }

    return OmrLayoutFitResult.fail(
      'A ${resolvedForm.pageFill.teacherLabel.toLowerCase()} '
      '${resolvedForm.orientation.teacherLabel.toLowerCase()} sheet '
      'with $opts choices can fit at most $maxFit questions. '
      'You asked for $items — use Full page, fewer questions, or fewer choices.',
    );
  }

  static List<({OmrSheetGeometry geometry, double minRow, double minSpacing})>
      _packAttemptsFor(OmrLayoutForm form) {
    final attempts = <({
      OmrSheetGeometry geometry,
      double minRow,
      double minSpacing
    })>[
      (
        geometry: OmrSheetGeometry.forForm(form),
        minRow: minRowHeight,
        minSpacing: minBubbleSpacingXFor(form),
      ),
    ];
    if (_isFullLengthwise(form)) {
      final denseGeometry = OmrSheetGeometry.denseFullPortrait();
      attempts.add((
        geometry: denseGeometry,
        minRow: scanMinRowHeight(denseGeometry),
        minSpacing: scanMinBubbleSpacing(form, denseGeometry),
      ));
    }
    return attempts;
  }

  static OmrLayoutFitResult _packBestAcrossGeometries({
    required int items,
    required int opts,
    required OmrLayoutForm form,
  }) {
    OmrLayoutProfile? best;
      var bestEven = false;
    var bestEmpty = 1 << 30;
    var bestShortfall = 1 << 30;
    var bestDense = true;
    var bestSlack = -1.0;
    var bestRows = 0;

    for (final attempt in _packAttemptsFor(form)) {
      final geometry = attempt.geometry;
      final minRow = attempt.minRow;
      final minSpacing = attempt.minSpacing;
      final dense = geometry.answerBubbleDiameter <
          OmrPageConstants.answerBubbleDiameter;
      if (geometry.answerGridContentHeight < minRow * 2 ||
          geometry.answerGridWidth < 80) {
        continue;
      }

      final columnOrder = _columnPackOrder(items: items, form: form);
      final gridHeight = geometry.answerGridContentHeight;
      final gridWidth = geometry.answerGridWidth;

      for (final columns in columnOrder) {
        final rows = (items / columns).ceil();
        if (rows < 1 || rows > maxRowsPerColumn) continue;
        // One very tall column is hard to frame and weakens row-mark lock.
        if (columns == 1 && items > 25) continue;
        final rowHeight = gridHeight / rows;
        if (!_rowPitchScannable(
          rowHeight: rowHeight,
          geometry: geometry,
          minRow: minRow,
        )) {
          continue;
        }

        final columnWidth = gridWidth / columns;
        final maxSpacing = _maxBubbleSpacing(
          columnWidth,
          opts,
          geometry: geometry,
        );
        if (maxSpacing < minSpacing) continue;

        final bubbleSpacingX = maxSpacing < preferredMaxBubbleSpacingX
            ? maxSpacing
            : preferredMaxBubbleSpacingX;

        final slack = [
          rowHeight - minRow,
          bubbleSpacingX - minSpacing,
        ].reduce((a, b) => a < b ? a : b);

        final evenFill = items % columns == 0;
        final emptySlots = columns * rows - items;
        final remInLastCol = items % rows;
        final shortfall =
            evenFill || remInLastCol == 0 ? 0 : rows - remInLastCol;

        // Prefer: even fill → fewer empties → smaller shortfall →
        // roomy (non-dense) geometry → taller pack when current is shallow →
        // (uneven only) more slack.
        // When two even packs tie, keep the earlier preferred column count
        // (5,4,3…) — do not let max-capped bubble spacing favor 1–2 columns.
        final better = best == null ||
            (!bestEven && evenFill) ||
            (evenFill == bestEven && emptySlots < bestEmpty) ||
            (evenFill == bestEven &&
                emptySlots == bestEmpty &&
                shortfall < bestShortfall) ||
            (evenFill == bestEven &&
                emptySlots == bestEmpty &&
                shortfall == bestShortfall &&
                bestDense &&
                !dense) ||
            (evenFill == bestEven &&
                emptySlots == bestEmpty &&
                shortfall == bestShortfall &&
                dense == bestDense &&
                bestRows < minBalancedRows &&
                rows > bestRows &&
                // Stay standard-like: do not collapse to 1–2 skinny columns
                // just to gain row count.
                columns >= 3) ||
            (evenFill == bestEven &&
                emptySlots == bestEmpty &&
                shortfall == bestShortfall &&
                dense == bestDense &&
                !evenFill &&
                slack > bestSlack);
        if (!better) continue;

        final templateId =
            'custom_${items}_o${opts}_${form.id}_${columns}x$rows';
        final grid = OmrTemplateSpec(
          templateId: templateId,
          maxItems: items,
          columns: columns,
          rows: rows,
          rowHeight: rowHeight,
          columnWidth: columnWidth,
          bubbleSpacingX: bubbleSpacingX,
          supportedItemCounts: [items],
        );

        final candidate = OmrLayoutProfile(
          grid: grid,
          optionsCount: opts,
          isCustom: true,
          form: form,
          itemCount: items,
          geometry: geometry,
        );
        if (!candidate.bubblesFitInsideColumns()) {
          continue;
        }
        if (!candidate.hasAdequateTimingMarks()) {
          continue;
        }

        bestEven = evenFill;
        bestEmpty = emptySlots;
        bestShortfall = shortfall;
        bestDense = dense;
        bestSlack = slack;
        bestRows = rows;
        best = candidate;
      }
    }

    if (best != null) {
      return OmrLayoutFitResult.ok(best);
    }
    return OmrLayoutFitResult.fail(
      'A ${form.pageFill.teacherLabel.toLowerCase()} '
      '${form.orientation.teacherLabel.toLowerCase()} sheet '
      'with $opts choices cannot fit $items questions scannably.',
    );
  }

  static OmrLayoutFitResult _tryComputeWithoutRecursion({
    required int itemCount,
    required int optionsCount,
    required OmrLayoutForm form,
  }) {
    return _packBestAcrossGeometries(
      items: itemCount,
      opts: optionsCount.clamp(2, 6),
      form: form,
    );
  }

  /// Prefers 5→4→3 columns for typical quizzes; small counts stay tall
  /// (1–3 columns); allows 6–8 only when needed for high Q counts.
  static List<int> _columnPackOrder({
    required int items,
    required OmrLayoutForm form,
  }) {
    final maxCols = maxColumnsFor(form, itemCount: items);
    final List<int> preferred;
    if (form.orientation == OmrLayoutOrientation.crosswise) {
      preferred = const [4, 5, 3, 6, 2, 1];
    } else if (items <= 12) {
      // Tiny quizzes: one tall column (or 2–3), never a single wide row.
      preferred = const [2, 3, 1, 4, 5, 6, 7, 8];
    } else {
      preferred = const [5, 4, 3, 2, 6, 7, 8, 1];
    }
    final allowed = preferred.where((c) => c <= maxCols).toList();
    final divisors = <int>[];
    final rest = <int>[];
    for (final columns in allowed) {
      if (items % columns == 0) {
        divisors.add(columns);
      } else {
        rest.add(columns);
      }
    }
    return [...divisors, ...rest];
  }

  /// Raw geometric upper bound before the column solver walk-down.
  static int _geometricMaxFitItems({
    required OmrLayoutForm form,
    required int optionsCount,
  }) {
    final opts = optionsCount.clamp(2, 6);
    final useDense = _isFullLengthwise(form);
    final geometry = useDense
        ? OmrSheetGeometry.denseFullPortrait()
        : OmrSheetGeometry.forForm(form);
    final minRow = scanMinRowHeight(geometry);
    final minSpacing = scanMinBubbleSpacing(form, geometry);
    final gridHeight = geometry.answerGridContentHeight;
    final gridWidth = geometry.answerGridWidth;
    if (gridHeight < minRow || gridWidth < 80) {
      return 0;
    }

    final columnOrder = _columnPackOrder(items: maxCustomItems, form: form);
    final capacityOrder = columnOrder.isNotEmpty
        ? columnOrder
        : List<int>.generate(
            maxColumnsFor(form, itemCount: maxCustomItems),
            (i) => i + 1,
          ).reversed.toList();

    var best = 0;
    for (final columns in capacityOrder) {
      final columnWidth = gridWidth / columns;
      final maxSpacing = _maxBubbleSpacing(
        columnWidth,
        opts,
        geometry: geometry,
      );
      if (maxSpacing < minSpacing) continue;

      var maxRows = (gridHeight / minRow).floor();
      if (maxRows > maxRowsPerColumn) {
        maxRows = maxRowsPerColumn;
      }
      if (columns == 1 && maxRows > 25) {
        maxRows = 25;
      }
      if (maxRows < 1) continue;
      final capacity = columns * maxRows;
      if (capacity > best) {
        best = capacity;
      }
    }

    if (best > maxCustomItems) {
      best = maxCustomItems;
    }
    final safety = safetyCapForForm(form);
    if (best > safety) {
      best = safety;
    }
    return best;
  }

  static OmrLayoutFitResult tryComputeExplicitGrid({
    required int columns,
    required int rows,
    required int optionsCount,
    required OmrLayoutForm form,
    /// Actual question count. May be less than [columns]×[rows] when the
    /// last column has empty slots (e.g. 200 questions on a 7×29 grid).
    int? itemCount,
  }) {
    final cols = columns.clamp(1, 10);
    final rowCount = rows.clamp(1, 200);
    final capacity = cols * rowCount;
    final opts = optionsCount.clamp(2, 6);
    final items = itemCount ?? capacity;

    if (items < minCustomItems) {
      return OmrLayoutFitResult.fail(
        'Custom sheets need at least $minCustomItems questions.',
      );
    }
    if (items > maxCustomItems) {
      return OmrLayoutFitResult.fail(
        'Custom sheets support at most $maxCustomItems questions.',
      );
    }
    if (capacity < items) {
      return OmrLayoutFitResult.fail(
        'Grid $cols×$rowCount holds only $capacity questions, but this exam '
        'has $items. Pick a larger grid or fewer questions.',
      );
    }
    // Allow a short empty tail in the last column; reject nearly-empty columns.
    if (capacity - items >= cols) {
      return OmrLayoutFitResult.fail(
        'Grid $cols×$rowCount has too many empty slots for $items questions. '
        'Use Automatic layout or a tighter grid.',
      );
    }

    final roomy = _tryExplicitGridOnGeometry(
      columns: cols,
      rows: rowCount,
      items: items,
      opts: opts,
      form: form,
      geometry: OmrSheetGeometry.forForm(form),
      minRow: minRowHeight,
      minSpacing: minBubbleSpacingXFor(form),
    );
    if (roomy.isOk) {
      return roomy;
    }
    if (_isFullLengthwise(form)) {
      final denseGeometry = OmrSheetGeometry.denseFullPortrait();
      final dense = _tryExplicitGridOnGeometry(
        columns: cols,
        rows: rowCount,
        items: items,
        opts: opts,
        form: form,
        geometry: denseGeometry,
        minRow: scanMinRowHeight(denseGeometry),
        minSpacing: scanMinBubbleSpacing(form, denseGeometry),
      );
      if (dense.isOk) {
        return dense;
      }
    }

    final maxFit = maxFitItems(form: form, optionsCount: opts);
    if (maxFit < minCustomItems) {
      return OmrLayoutFitResult.fail(
        'A ${form.pageFill.teacherLabel.toLowerCase()} '
        '${form.orientation.teacherLabel.toLowerCase()} sheet '
        'is too small for scannable bubbles. Use a full portrait page.',
      );
    }
    if (items > maxFit) {
      return OmrLayoutFitResult.fail(
        'A ${form.pageFill.teacherLabel.toLowerCase()} '
        '${form.orientation.teacherLabel.toLowerCase()} sheet '
        'with $opts choices can fit at most $maxFit questions. '
        'You asked for $items — use Full page, fewer questions, or fewer choices.',
      );
    }
    return roomy;
  }

  static OmrLayoutFitResult _tryExplicitGridOnGeometry({
    required int columns,
    required int rows,
    required int items,
    required int opts,
    required OmrLayoutForm form,
    required OmrSheetGeometry geometry,
    required double minRow,
    required double minSpacing,
  }) {
    if (geometry.answerGridContentHeight < minRow * 2 ||
        geometry.answerGridWidth < 80) {
      return const OmrLayoutFitResult.fail(
        'This page size is too small for a scannable answer grid. '
        'Try Full page or Half page.',
      );
    }

    final gridHeight = geometry.answerGridContentHeight;
    final gridWidth = geometry.answerGridWidth;
    final rowHeight = gridHeight / rows;
    if (rows > maxRowsPerColumn) {
      return OmrLayoutFitResult.fail(
        'Grid height $rows exceeds the scan-safe maximum of '
        '$maxRowsPerColumn rows per column. Use more columns or fewer questions.',
      );
    }
    final maxCols = maxColumnsFor(form, itemCount: items);
    if (columns > maxCols) {
      return OmrLayoutFitResult.fail(
        'Grid width $columns is too wide to scan reliably on a phone. '
        'Use at most $maxCols tall columns (like the standard sheets), '
        'not a wide strip.',
      );
    }
    if (columns == 1 && items > 25) {
      return const OmrLayoutFitResult.fail(
        'A single question column is not reliable for this many questions. '
        'Use at least 2 columns.',
      );
    }
    if (!_rowPitchScannable(
      rowHeight: rowHeight,
      geometry: geometry,
      minRow: minRow,
    )) {
      return OmrLayoutFitResult.fail(
        'Grid height $rows is too tall for this sheet — rows would be '
        'too small to scan reliably. Try fewer rows, more columns, '
        'or a larger page size.',
      );
    }

    final columnWidth = gridWidth / columns;
    final maxSpacing = _maxBubbleSpacing(
      columnWidth,
      opts,
      geometry: geometry,
    );
    if (maxSpacing < minSpacing) {
      return OmrLayoutFitResult.fail(
        'Grid width $columns is too wide for this sheet — bubbles would be '
        'too close together. Try fewer columns or fewer answer choices.',
      );
    }

    final bubbleSpacingX = maxSpacing < preferredMaxBubbleSpacingX
        ? maxSpacing
        : preferredMaxBubbleSpacingX;

    final templateId =
        'custom_${items}_o${opts}_${form.id}_${columns}x$rows';
    final grid = OmrTemplateSpec(
      templateId: templateId,
      maxItems: items,
      columns: columns,
      rows: rows,
      rowHeight: rowHeight,
      columnWidth: columnWidth,
      bubbleSpacingX: bubbleSpacingX,
      supportedItemCounts: [items],
    );

    final profile = OmrLayoutProfile(
      grid: grid,
      optionsCount: opts,
      isCustom: true,
      form: form,
      itemCount: items,
      geometry: geometry,
    );
    if (!profile.bubblesFitInsideColumns()) {
      return const OmrLayoutFitResult.fail(
        'Bubbles would spill past column edges on this grid. '
        'Try fewer columns, fewer choices, or a larger page size.',
      );
    }
    if (!profile.hasAdequateTimingMarks()) {
      return const OmrLayoutFitResult.fail(
        'This page size does not leave enough room for timing marks. '
        'Use a full portrait page.',
      );
    }

    return OmrLayoutFitResult.ok(profile);
  }

  /// Hard capacity for a form + option count (scannable min spacing).
  static int maxFitItems({
    required OmrLayoutForm form,
    required int optionsCount,
  }) {
    var capped = _geometricMaxFitItems(
      form: form,
      optionsCount: optionsCount,
    );
    final opts = optionsCount.clamp(2, 6);
    while (capped >= minCustomItems) {
      if (_tryComputeWithoutRecursion(
        itemCount: capped,
        optionsCount: opts,
        form: form,
      ).isOk) {
        return capped;
      }
      capped--;
    }
    return 0;
  }

  /// Teacher-facing capacity line for the answer-key UI.
  static String capacityHint({
    required OmrLayoutForm form,
    required int optionsCount,
  }) {
    final maxFit = maxFitItems(form: form, optionsCount: optionsCount);
    final opts = optionsCount.clamp(2, 6);
    final labels =
        OmrPageConstants.answerOptionLabels.take(opts).join('-');
    if (maxFit < minCustomItems) {
      return 'This ${form.pageFill.teacherLabel.toLowerCase()} '
          '${form.orientation.teacherLabel.toLowerCase()} sheet is too small '
          'for a scannable quiz. Use a full portrait page.';
    }
    return 'This ${form.pageFill.teacherLabel.toLowerCase()} '
        '${form.orientation.teacherLabel.toLowerCase()} sheet with $labels '
        'can fit $minCustomItems–$maxFit questions.';
  }

  double rowCenterY(int rowIndex) {
    return geometry.answerRowsTop +
        (rowIndex * grid.rowHeight) +
        (grid.rowHeight / 2);
  }

  double bubbleCenterX(int colIndex, int optionIndex) {
    final optionSpan = (optionsCount.clamp(2, 6) - 1);
    final columnLeft = geometry.answerGridLeft + (colIndex * grid.columnWidth);
    final bubbleAreaWidth = grid.bubbleSpacingX * optionSpan;
    final usableWidth =
        grid.columnWidth - (geometry.answerColumnInset * 2);
    final rowContentWidth = geometry.questionNumberWidth +
        geometry.answerNumberBubbleGap +
        bubbleAreaWidth;
    final rowContentLeft = columnLeft +
        geometry.answerColumnInset +
        ((usableWidth - rowContentWidth) / 2);
    final bubbleAreaLeft = rowContentLeft +
        geometry.questionNumberWidth +
        geometry.answerNumberBubbleGap;
    return bubbleAreaLeft + (optionIndex * grid.bubbleSpacingX);
  }

  static double _maxBubbleSpacing(
    double columnWidth,
    int optionsCount, {
    required OmrSheetGeometry geometry,
  }) {
    final usableWidth = columnWidth - (geometry.answerColumnInset * 2);
    final fixed =
        geometry.questionNumberWidth + geometry.answerNumberBubbleGap;
    // Reserve the full bubble diameter so the outer edge stays inside the column
    // (centers alone would let radius spill past answerColumnInset on ¼ sheets).
    final span = usableWidth - fixed - geometry.answerBubbleDiameter;
    final gaps = (optionsCount.clamp(2, 6) - 1);
    if (gaps <= 0) return span;
    if (span <= 0) return 0;
    return span / gaps;
  }

  /// True when every answer bubble stays inside its column (scan contract).
  bool bubblesFitInsideColumns() {
    final opts = optionsCount.clamp(2, 6);
    for (var col = 0; col < grid.columns; col++) {
      final leftEdge =
          bubbleCenterX(col, 0) - (geometry.answerBubbleDiameter / 2);
      final rightEdge = bubbleCenterX(col, opts - 1) +
          (geometry.answerBubbleDiameter / 2);
      final columnLeft =
          geometry.answerGridLeft + (col * grid.columnWidth);
      final columnRight = columnLeft + grid.columnWidth;
      if (leftEdge < columnLeft - 0.05 || rightEdge > columnRight + 0.05) {
        return false;
      }
    }
    return true;
  }

  /// Timing marks on each edge — scanner needs enough samples to trust alignment.
  bool hasAdequateTimingMarks({int minPerEdge = 4}) {
    final g = geometry;
    final spacing = g.timingMarkSpacing;
    if (spacing <= 0) return false;
    final xCount =
        ((g.timingMarkEndX - g.timingMarkStartX) / spacing).floor() + 1;
    final yCount =
        ((g.timingMarkEndY - g.timingMarkStartY) / spacing).floor() + 1;
    return xCount >= minPerEdge && yCount >= minPerEdge;
  }
}

/// Legacy name kept so older references compile; prefer [OmrLayoutForm].
enum OmrLayoutShape {
  compact,
  long;

  String get id => name;

  static OmrLayoutShape fromId(String? raw) {
    final form = OmrLayoutForm.fromId(raw);
    if (form.orientation == OmrLayoutOrientation.crosswise ||
        form.pageFill != OmrLayoutPageFill.full) {
      return OmrLayoutShape.long;
    }
    return OmrLayoutShape.compact;
  }
}

// =============================================================================
// QR PAYLOAD v2 (includes layout metadata)
// =============================================================================

/// Enhanced QR payload with layout information.
class OmrQrPayloadV2 {
  const OmrQrPayloadV2({
    required this.version,
    required this.sheetId,
    required this.subjectId,
    required this.subjectName,
    required this.questions,
    required this.passingScore,
    this.section,
    this.examDate,
    required this.layout,
  });

  /// Payload version (2 for this format).
  final int version;

  /// Unique sheet identifier.
  final String sheetId;

  /// Subject ID.
  final String subjectId;

  /// Subject name.
  final String subjectName;

  /// Total questions on this sheet.
  final int questions;

  /// Passing score.
  final int passingScore;

  /// Optional section name.
  final String? section;

  /// Optional exam date.
  final String? examDate;

  /// Layout specification.
  final OmrTemplateSpec layout;

  /// Get the template ID.
  String get templateId => layout.templateId;

  /// Convert to JSON string for QR encoding.
  String toJsonString() {
    final map = <String, dynamic>{
      'v': version,
      'sheetId': sheetId,
      'subjectId': subjectId,
      'subjectName': subjectName,
      'questions': questions,
      'passingScore': passingScore,
      if (section != null) 'section': section,
      if (examDate != null) 'examDate': examDate,
      'layout': layout.toJson(),
    };
    return jsonEncode(map);
  }

  /// Parse from JSON string (from QR scan).
  static OmrQrPayloadV2? fromJsonString(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      final version = map['v'] as int? ?? 1;

      // Handle v1 payloads (backward compatibility)
      if (version == 1) {
        return _fromV1(map);
      }

      final layoutJson = map['layout'] as Map<String, dynamic>;
      return OmrQrPayloadV2(
        version: version,
        sheetId: map['sheetId'] as String,
        subjectId: map['subjectId'] as String,
        subjectName: map['subjectName'] as String,
        questions: map['questions'] as int,
        passingScore: map['passingScore'] as int,
        section: map['section'] as String?,
        examDate: map['examDate'] as String?,
        layout: OmrTemplateSpec.fromJson(layoutJson),
      );
    } catch (e) {
      return null;
    }
  }

  /// Convert v1 payload to v2 (backward compatibility).
  static OmrQrPayloadV2 _fromV1(Map<String, dynamic> v1Map) {
    final questions = v1Map['questions'] as int? ?? 50;
    return OmrQrPayloadV2(
      version: 1, // Keep original version for tracking
      sheetId: v1Map['sheetId'] as String? ?? '',
      subjectId: v1Map['subjectId'] as String? ?? '',
      subjectName: v1Map['subjectName'] as String? ?? '',
      questions: questions,
      passingScore: v1Map['passingScore'] as int? ?? (questions * 0.6).round(),
      section: v1Map['section'] as String?,
      examDate: v1Map['examDate'] as String?,
      layout: OmrTemplateSpec.forItemCount(questions),
    );
  }

  /// Check if this is a legacy v1 payload (layout was inferred, not explicit).
  bool get isLegacyV1 => version == 1;
}

// NOTE: OmrQrPayloadV2 uses inline JSON methods because this file is a
// specification file. The actual QR encoding/decoding is handled by
// SubjectSheetQrPayload in exam_data.dart with proper dart:convert imports.

// =============================================================================
// ROW REFERENCE MARKS (for scanner alignment validation)
// =============================================================================

/// Positions for row reference marks on the left edge.
class OmrRowMarks {
  OmrRowMarks._();

  /// Size of row reference marks (scanner samples a 2× this region).
  static const double markSize = 4.0;

  /// X position (left edge).
  static const double markX =
      OmrPageConstants.marginLeft - 10.0; // 18pt from left edge

  /// Get Y positions for row marks for a given template.
  static List<double> getRowMarkPositions(OmrTemplateSpec template) {
    return List.generate(
      template.rows,
      (rowIndex) => template.rowCenterY(rowIndex),
    );
  }
}
