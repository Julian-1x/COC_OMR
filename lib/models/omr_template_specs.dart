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
  static const double qrCodeSize = 72.0;
  static const double qrCodeX = pageWidth - marginRight - qrCodeSize; // 495
  static const double qrCodeY = marginTop; // 34

  // Header section (subject name, code, etc.)
  static const double headerTop = marginTop;
  static const double headerHeight = 72.0; // Same as QR height
  static const double headerBottom = headerTop + headerHeight; // 106

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
  static const int answerOptionsCount = 5; // A, B, C, D, E
  static const List<String> answerOptionLabels = ['A', 'B', 'C', 'D', 'E'];
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
  double bubbleCenterX(int colIndex, int optionIndex) {
    final columnLeft =
        OmrPageConstants.answerGridLeft + (colIndex * columnWidth);
    final bubbleAreaWidth =
        bubbleSpacingX * (OmrPageConstants.answerOptionsCount - 1);
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
  (double x, double y) bubblePosition(int questionNumber, int optionIndex) {
    final (col, row) = questionPosition(questionNumber);
    return (bubbleCenterX(col, optionIndex), rowCenterY(row));
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
