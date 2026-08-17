import 'dart:convert';

import 'package:barcode/barcode.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AnswerSheetGenerator {
  static const PdfColor _panelBorder = PdfColors.grey400;
  static const double _panelBorderWidth = 0.55;
  static const PdfColor _mutedInk = PdfColors.grey700;

  static String? _qrOwnerTeacherId(Subject subject) {
    final fromSubject = subject.ownerTeacherId?.trim();
    if (fromSubject != null && fromSubject.isNotEmpty) {
      return fromSubject;
    }
    return ApiService.currentUserId?.trim();
  }

  static String? _qrOwnerTeacherEmail({String? override}) {
    final fromOverride = override?.trim();
    if (fromOverride != null && fromOverride.isNotEmpty) {
      return fromOverride;
    }
    final fromApi = ApiService.currentEmail?.trim();
    if (fromApi != null && fromApi.isNotEmpty) {
      return fromApi;
    }
    return LocalAuthService.instance.cachedTeacherEmail?.trim();
  }

  static String? _qrOwnerTeacherName({String? override}) {
    final fromOverride = override?.trim();
    if (fromOverride != null && fromOverride.isNotEmpty) {
      return fromOverride;
    }
    return LocalAuthService.instance.cachedTeacherName?.trim();
  }

  static bool _qrPayloadIsCurrent(
    SubjectSheetQrPayload payload,
    Subject subject, {
    String? ownerTeacherEmail,
  }) {
    final currentOwner = _qrOwnerTeacherId(subject);
    final payloadOwner = payload.ownerTeacherId?.trim();
    if (currentOwner != null && currentOwner.isNotEmpty) {
      if (payloadOwner == null || payloadOwner.isEmpty) {
        return false;
      }
      if (payloadOwner != currentOwner) {
        return false;
      }
    }

    final expectedEmail = _qrOwnerTeacherEmail(override: ownerTeacherEmail);
    if (expectedEmail != null && expectedEmail.isNotEmpty) {
      final payloadEmail = payload.ownerTeacherEmail?.trim();
      if (payloadEmail == null || payloadEmail.isEmpty) {
        return false;
      }
      if (payloadEmail.toLowerCase() != expectedEmail.toLowerCase()) {
        return false;
      }
    }

    // Teacher name is intentionally not in the QR (keeps the symbol readable),
    // so it is not part of the currency check.

    final cloudId = subject.cloudId?.trim();
    if (cloudId != null && cloudId.isNotEmpty) {
      final payloadCloud = payload.subjectCloudId?.trim();
      if (payloadCloud == null || payloadCloud.isEmpty) {
        return false;
      }
      if (payloadCloud != cloudId) {
        return false;
      }
    }

    // Force reprint of dense pre-1.5.30 QRs that embedded full layout metadata.
    if (payload.layout != null) {
      return false;
    }

    return true;
  }

  static SubjectSheetQrPayload _newSheetQrPayload(
    Subject subject, {
    String? sectionName,
    String? sheetId,
    String? ownerTeacherEmail,
    String? ownerTeacherName,
  }) {
    final resolvedSection = sectionName ??
        (subject.sectionNames != null && subject.sectionNames!.isNotEmpty
            ? subject.sectionNames!.first
            : null);

    return SubjectSheetQrPayload(
      version: 2,
      sheetId: sheetId ?? generateUniqueSheetId(),
      subjectId: subject.id,
      subjectName: subject.name,
      totalQuestions: subject.totalQuestions,
      passingScore: subject.passingScore,
      sectionName: resolvedSection,
      examDateIso: subject.examDate?.toIso8601String(),
      ownerTeacherId: _qrOwnerTeacherId(subject),
      ownerTeacherEmail: _qrOwnerTeacherEmail(override: ownerTeacherEmail),
      ownerTeacherName: _qrOwnerTeacherName(override: ownerTeacherName),
      subjectCloudId: subject.cloudId,
      // Layout stays in the scanner session, not the QR — denser QR failed on phones.
      layout: null,
    );
  }

  /// Generate single OMR sheet (original)
  static Future<void> generateAndPrint({
    required Subject subject,
    String? sectionName,
  }) async {
    final pdf = pw.Document();
    final totalQuestions =
        subject.totalQuestions > 0 ? subject.totalQuestions : 50;
    final qrPayload = _buildSheetQrPayload(subject, sectionName: sectionName);
    final template = OmrTemplateSpec.forItemCount(totalQuestions);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) => pw.Stack(
          children: [
            // Corner markers and timing marks (absolute positioned)
            _cornerMarkers(totalQuestions),
            // All content using absolute positions from OmrPageConstants
            ..._buildAbsoluteLayout(
                subject, qrPayload, totalQuestions, template),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    await LocalDataStore.instance.persistCountersNow();
  }

  /// Generate multiple identical sheets (same QR) for a subject/section.
  static Future<void> generateMultiple({
    required Subject subject,
    required String sectionName,
    required int copies,
  }) async {
    final safeCopies = copies < 1 ? 1 : copies;
    final pdf = pw.Document();
    final totalQuestions =
        subject.totalQuestions > 0 ? subject.totalQuestions : 50;

    for (var i = 0; i < safeCopies; i++) {
      final qrPayload = _buildSheetQrPayload(subject, sectionName: sectionName);
      final template = OmrTemplateSpec.forItemCount(totalQuestions);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (context) => pw.Stack(
            children: [
              _cornerMarkers(totalQuestions),
              ..._buildAbsoluteLayout(
                  subject, qrPayload, totalQuestions, template),
            ],
          ),
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: '${subject.displayName}_${sectionName}_${safeCopies}copies.pdf',
    );
    await LocalDataStore.instance.persistCountersNow();
  }

  /// NEW: Batch generate class set (1 sheet per student, pre-filled OMR)
  static Future<void> batchGenerate(
      {required Subject subject, required String sectionName}) async {
    final sectionStudents = globalStudentDatabase
        .where((s) =>
            s.section.trim().toUpperCase() == sectionName.trim().toUpperCase())
        .toList();

    if (sectionStudents.isEmpty) {
      throw Exception('No students found in section "$sectionName"');
    }

    final pdf = pw.Document();
    final totalQuestions =
        subject.totalQuestions > 0 ? subject.totalQuestions : 50;

    for (final student in sectionStudents) {
      final qrPayload = _buildSheetQrPayload(subject, sectionName: sectionName);
      final template = OmrTemplateSpec.forItemCount(totalQuestions);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (context) => pw.Stack(
            children: [
              _cornerMarkers(totalQuestions),
              ..._buildAbsoluteLayoutBatch(subject, qrPayload, totalQuestions,
                  template, student, sectionName),
            ],
          ),
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name:
          '${subject.displayName}_${sectionName}_${sectionStudents.length}sheets.pdf',
    );
    await LocalDataStore.instance.persistCountersNow();
  }

  static SubjectSheetQrPayload _buildSheetQrPayload(
    Subject subject, {
    String? sectionName,
  }) {
    final resolvedSection = sectionName ??
        (subject.sectionNames != null && subject.sectionNames!.isNotEmpty
            ? subject.sectionNames!.first
            : null);
    final cached =
        resolvedSection == null ? null : subject.sectionQrData[resolvedSection];
    if (cached != null) {
      try {
        final payload = SubjectSheetQrPayload.fromJson(jsonDecode(cached));
        if (_qrPayloadIsCurrent(payload, subject)) {
          return payload;
        }
      } catch (_) {}
    }

    return _newSheetQrPayload(subject, sectionName: resolvedSection);
  }

  static String buildSheetQrCodeData(
    Subject subject, {
    String? sheetId,
    String? sectionName,
  }) {
    final payload = _buildSheetQrPayload(
      subject,
      sectionName: sectionName,
    );
    if (sheetId != null && sheetId != payload.sheetId) {
      return jsonEncode(
        _newSheetQrPayload(
          subject,
          sectionName: sectionName,
          sheetId: sheetId,
        ).toJson(),
      );
    }
    return jsonEncode(payload.toJson());
  }

  static String buildSheetQrCodeDataForSection({
    required String subjectId,
    required String subjectName,
    required int totalQuestions,
    required int passingScore,
    required String sectionName,
    DateTime? examDate,
    String? sheetId,
    String? ownerTeacherId,
    String? ownerTeacherEmail,
    String? ownerTeacherName,
    String? subjectCloudId,
  }) {
    final subject = Subject(
      id: subjectId,
      name: subjectName,
      answerKey: <int, dynamic>{},
      totalQuestions: totalQuestions,
      passingScore: passingScore,
      examDate: examDate,
      ownerTeacherId: ownerTeacherId,
      cloudId: subjectCloudId,
    );
    return jsonEncode(
      _newSheetQrPayload(
        subject,
        sectionName: sectionName,
        sheetId: sheetId,
        ownerTeacherEmail: ownerTeacherEmail,
        ownerTeacherName: ownerTeacherName,
      ).toJson(),
    );
  }

  static pw.Widget _cornerMarkers(int totalQuestions) {
    const size = OmrPageConstants.cornerMarkerSize;
    const offset = OmrPageConstants.cornerMarkerOffset;
    return pw.Stack(
      children: [
        // Four corner markers for alignment
        pw.Positioned(
          left: offset,
          top: offset,
          child: _cornerBox(size),
        ),
        pw.Positioned(
          right: offset,
          top: offset,
          child: _cornerBox(size),
        ),
        pw.Positioned(
          left: offset,
          bottom: offset,
          child: _cornerBox(size),
        ),
        pw.Positioned(
          right: offset,
          bottom: offset,
          child: _cornerBox(size),
        ),
        // Scanner registration marks — positions are fixed for every template.
        // Do not move/resize without updating OmrProcessor + reprinting sheets.
        ..._buildTimingMarks(),
        // Row reference marks for answer grid alignment validation
        ..._buildRowMarks(totalQuestions),
      ],
    );
  }

  /// Build all page content using absolute positioning from OmrPageConstants
  /// This ensures PDF positions exactly match what the scanner expects
  static List<pw.Widget> _buildAbsoluteLayout(
    Subject subject,
    SubjectSheetQrPayload qrPayload,
    int totalQuestions,
    OmrTemplateSpec template,
  ) {
    return [
      // Header section at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.headerTop,
        child: pw.SizedBox(
          width: OmrPageConstants.contentWidth,
          height: OmrPageConstants.headerHeight,
          child: _headerSection(subject, qrPayload),
        ),
      ),
      // OMR ID section at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.omrIdTop,
        child: pw.SizedBox(
          width: OmrPageConstants.contentWidth,
          height: OmrPageConstants.omrIdHeight,
          child: _idSection(),
        ),
      ),
      // Answer grid at fixed position - this is the critical section
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.answerGridTop,
        child: pw.SizedBox(
          width: OmrPageConstants.answerGridWidth,
          height: OmrPageConstants.answerGridHeight,
          child: _answersSectionAbsolute(totalQuestions, template),
        ),
      ),
      // Footer/calibration section at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.answerRowsBottom,
        child: pw.SizedBox(
          width: OmrPageConstants.contentWidth,
          child: _footerNotes(subject, qrPayload),
        ),
      ),
      ..._buildCalibrationMarks(),
    ];
  }

  /// Build batch layout with student info using absolute positioning
  static List<pw.Widget> _buildAbsoluteLayoutBatch(
    Subject subject,
    SubjectSheetQrPayload qrPayload,
    int totalQuestions,
    OmrTemplateSpec template,
    Student student,
    String sectionName,
  ) {
    return [
      // Header section with student info at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.headerTop,
        child: pw.SizedBox(
          width: OmrPageConstants.contentWidth,
          height: OmrPageConstants.headerHeight,
          child: _headerSectionBatch(subject, qrPayload, student, sectionName),
        ),
      ),
      // Pre-filled OMR ID section at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.omrIdTop,
        child: pw.SizedBox(
          width: OmrPageConstants.contentWidth,
          height: OmrPageConstants.omrIdHeight,
          child: _idSectionPreFilled(student.omrId),
        ),
      ),
      // Answer grid at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.answerGridTop,
        child: pw.SizedBox(
          width: OmrPageConstants.answerGridWidth,
          height: OmrPageConstants.answerGridHeight,
          child: _answersSectionAbsolute(totalQuestions, template),
        ),
      ),
      // Footer/calibration section at fixed position
      pw.Positioned(
        left: OmrPageConstants.marginLeft,
        top: OmrPageConstants.answerRowsBottom,
        child: pw.SizedBox(
          width: OmrPageConstants.contentWidth,
          child: _footerNotes(subject, qrPayload),
        ),
      ),
      ..._buildCalibrationMarks(),
    ];
  }

  /// Answer section using absolute row positioning to match scanner expectations
  static pw.Widget _answersSectionAbsolute(
      int totalQuestions, OmrTemplateSpec template) {
    return pw.Container(
      width: OmrPageConstants.answerGridWidth,
      height: OmrPageConstants.answerGridHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          width: _panelBorderWidth,
          color: _panelBorder,
        ),
      ),
      child: pw.Stack(
        children: [
          ...List.generate(template.columns, (colIndex) {
            final startQ = colIndex * template.rows + 1;
            final endQ = (startQ + template.rows - 1).clamp(1, totalQuestions);

            if (startQ > totalQuestions) {
              return pw.SizedBox();
            }

            return pw.Positioned(
              left: colIndex * template.columnWidth,
              top: 0,
              child: pw.SizedBox(
                width: template.columnWidth,
                height: OmrPageConstants.answerGridHeight,
                child: pw.Stack(
                  children: [
                    _answerOptionIndicatorRow(
                      bubbleSpacingX: template.bubbleSpacingX,
                      columnWidth: template.columnWidth,
                    ),
                    pw.Positioned(
                      left: 0,
                      top: OmrPageConstants.answerOptionIndicatorHeight,
                      child: pw.SizedBox(
                        width: template.columnWidth,
                        height: OmrPageConstants.answerGridContentHeight,
                        child: _questionColumnAbsolute(
                          startQuestion: startQ,
                          endQuestion: endQ,
                          totalRows: template.rows,
                          rowHeight: template.rowHeight,
                          bubbleSpacingX: template.bubbleSpacingX,
                          columnWidth: template.columnWidth,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _answerOptionIndicatorRow({
    required double bubbleSpacingX,
    required double columnWidth,
  }) {
    final bubbleAreaWidth =
        bubbleSpacingX * (OmrPageConstants.answerOptionsCount - 1);
    final usableWidth = columnWidth - (OmrPageConstants.answerColumnInset * 2);
    final rowContentWidth = OmrPageConstants.questionNumberWidth +
        OmrPageConstants.answerNumberBubbleGap +
        bubbleAreaWidth;
    final rowContentLeft = OmrPageConstants.answerColumnInset +
        ((usableWidth - rowContentWidth) / 2);
    final bubbleAreaLeft = rowContentLeft +
        OmrPageConstants.questionNumberWidth +
        OmrPageConstants.answerNumberBubbleGap;

    return pw.SizedBox(
      width: columnWidth,
      height: OmrPageConstants.answerOptionIndicatorHeight,
      child: pw.Stack(
        children:
            List.generate(OmrPageConstants.answerOptionsCount, (optIndex) {
          final bubbleCenterX = bubbleAreaLeft + (optIndex * bubbleSpacingX);
          return pw.Positioned(
            left: bubbleCenterX - 5,
            top: 1,
            child: pw.SizedBox(
              width: 10,
              child: pw.Center(
                child: pw.Text(
                  OmrPageConstants.answerOptionLabels[optIndex],
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Question column with fixed row heights - each row at exact position
  static pw.Widget _questionColumnAbsolute({
    required int startQuestion,
    required int endQuestion,
    required int totalRows,
    required double rowHeight,
    required double bubbleSpacingX,
    required double columnWidth,
  }) {
    final questionCount = endQuestion - startQuestion + 1;
    final bubbleAreaWidth =
        bubbleSpacingX * (OmrPageConstants.answerOptionsCount - 1);
    final usableWidth = columnWidth - (OmrPageConstants.answerColumnInset * 2);
    final rowContentWidth = OmrPageConstants.questionNumberWidth +
        OmrPageConstants.answerNumberBubbleGap +
        bubbleAreaWidth;
    final rowContentLeft = OmrPageConstants.answerColumnInset +
        ((usableWidth - rowContentWidth) / 2);
    final bubbleAreaLeft = rowContentLeft +
        OmrPageConstants.questionNumberWidth +
        OmrPageConstants.answerNumberBubbleGap;

    return pw.Stack(
      children: List.generate(totalRows, (rowIndex) {
        final questionNumber = startQuestion + rowIndex;
        final hasQuestion = rowIndex < questionCount;

        if (!hasQuestion) return pw.SizedBox();

        return pw.Positioned(
          left: 0,
          top: rowIndex * rowHeight,
          child: pw.SizedBox(
            width: columnWidth,
            height: rowHeight,
            child: pw.Stack(
              children: [
                pw.Positioned(
                  left: rowContentLeft,
                  top: (rowHeight / 2) - 4,
                  child: pw.Text('$questionNumber.',
                      style: const pw.TextStyle(fontSize: 7)),
                ),
                ...List.generate(OmrPageConstants.answerOptionsCount,
                    (optIndex) {
                  return pw.Positioned(
                    left: bubbleAreaLeft +
                        (optIndex * bubbleSpacingX) -
                        (OmrPageConstants.answerBubbleDiameter / 2),
                    top: (rowHeight / 2) -
                        (OmrPageConstants.answerBubbleDiameter / 2),
                    child: _bubble(),
                  );
                }),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Timing marks along edges help detect rotation and skew.
  /// Printed as small squares (same size/positions the scanner expects).
  static List<pw.Widget> _buildTimingMarks() {
    const markSize = OmrPageConstants.timingMarkSize;
    const markSpacing = OmrPageConstants.timingMarkSpacing;
    const edgeOffset = OmrPageConstants.timingMarkEdgeOffset;
    const startX = OmrPageConstants.timingMarkStartX;
    const endX = OmrPageConstants.timingMarkEndX;
    const startY = OmrPageConstants.timingMarkStartY;
    const endY = OmrPageConstants.timingMarkEndY;
    final marks = <pw.Widget>[];

    // Top edge timing marks (skip corners)
    for (double x = startX; x < endX; x += markSpacing) {
      marks.add(pw.Positioned(
        left: x,
        top: edgeOffset,
        child: pw.Container(
          width: markSize,
          height: markSize,
          decoration: const pw.BoxDecoration(
            color: PdfColors.black,
          ),
        ),
      ));
    }

    // Bottom edge timing marks (skip corners)
    for (double x = startX; x < endX; x += markSpacing) {
      marks.add(pw.Positioned(
        left: x,
        bottom: edgeOffset,
        child: pw.Container(
          width: markSize,
          height: markSize,
          decoration: const pw.BoxDecoration(
            color: PdfColors.black,
          ),
        ),
      ));
    }

    // Left edge timing marks (skip corners)
    for (double y = startY; y < endY; y += markSpacing) {
      marks.add(pw.Positioned(
        left: edgeOffset,
        top: y,
        child: pw.Container(
          width: markSize,
          height: markSize,
          decoration: const pw.BoxDecoration(
            color: PdfColors.black,
          ),
        ),
      ));
    }

    // Right edge timing marks (skip corners)
    for (double y = startY; y < endY; y += markSpacing) {
      marks.add(pw.Positioned(
        right: edgeOffset,
        top: y,
        child: pw.Container(
          width: markSize,
          height: markSize,
          decoration: const pw.BoxDecoration(
            color: PdfColors.black,
          ),
        ),
      ));
    }

    return marks;
  }

  /// Row reference marks on left edge at each answer row Y position
  /// These help the scanner validate row alignment independently
  static List<pw.Widget> _buildRowMarks(int totalQuestions) {
    final template = OmrTemplateSpec.forItemCount(totalQuestions);
    final rowPositions = OmrRowMarks.getRowMarkPositions(template);
    final marks = <pw.Widget>[];

    for (final y in rowPositions) {
      marks.add(pw.Positioned(
        left: OmrRowMarks.markX,
        top: y - (OmrRowMarks.markSize / 2),
        child: pw.Container(
          width: OmrRowMarks.markSize,
          height: OmrRowMarks.markSize,
          color: PdfColors.black,
        ),
      ));
    }

    return marks;
  }

  static pw.Widget _cornerBox(double size) {
    return pw.Container(
      width: size,
      height: size,
      color: PdfColors.black,
      child: pw.Center(
        child: pw.Container(
          width: size * 0.5, // 50% ratio for optimal contrast
          height: size * 0.5,
          color: PdfColors.white,
        ),
      ),
    );
  }

  /// Batch header with student info
  static pw.Widget _headerSectionBatch(Subject subject,
      SubjectSheetQrPayload qrPayload, Student student, String sectionName) {
    return _buildHeader(
      subject: subject,
      qrPayload: qrPayload,
      subtitleLine1: _fitHeaderText('STUDENT: ${student.name}', maxChars: 42),
      subtitleLine2: _fitHeaderText(
        'OMR: ${student.omrId}   SECTION: $sectionName',
        maxChars: 42,
      ),
    );
  }

  /// Blank-sheet header: name write-in + section info (OMR ID stays empty below).
  /// Text stays inside [OmrPageConstants.headerHeight] — do not grow this box.
  static pw.Widget _headerSection(
      Subject subject, SubjectSheetQrPayload qrPayload) {
    final sectionLabel =
        (qrPayload.sectionName == null || qrPayload.sectionName!.trim().isEmpty)
            ? 'ALL'
            : qrPayload.sectionName!;
    final examDate = subject.examDate == null
        ? ''
        : '   DATE: ${_formatDate(subject.examDate!)}';
    return _buildHeader(
      subject: subject,
      qrPayload: qrPayload,
      subtitleLine1: _fitHeaderText(
        'SECTION: $sectionLabel$examDate   ITEMS: ${subject.totalQuestions}',
        maxChars: 42,
      ),
      // Fixed label + underline; not truncated so the write-in stays usable.
      subtitleLine2: 'NAME: _______________________________',
      instructionLine:
          'Write your name. Shade your OMR ID. One bubble per question. Dark pencil (HB/2B).',
    );
  }

  static pw.Widget _buildHeader({
    required Subject subject,
    required SubjectSheetQrPayload qrPayload,
    required String subtitleLine1,
    required String subtitleLine2,
    String instructionLine =
        'Fill one bubble per question. Use a dark pencil (HB or 2B).',
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_fitHeaderText(subject.displayName, maxChars: 28),
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(subtitleLine1, style: const pw.TextStyle(fontSize: 8.2)),
              pw.SizedBox(height: 2),
              pw.Text(subtitleLine2, style: const pw.TextStyle(fontSize: 8.2)),
              pw.SizedBox(height: 2),
              pw.Text(
                instructionLine,
                style: const pw.TextStyle(fontSize: 7.2, color: _mutedInk),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Container(
          width: OmrPageConstants.qrCodeSize,
          height: OmrPageConstants.qrCodeSize,
          padding: const pw.EdgeInsets.all(3),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.6, color: _panelBorder),
          ),
          child: pw.BarcodeWidget(
            // Lowest correction level = fewest modules = biggest, most
            // camera-readable squares. Laser print quality does not need more.
            barcode: Barcode.qrCode(
              errorCorrectLevel: BarcodeQRCorrectionLevel.low,
            ),
            data: jsonEncode(qrPayload.toJson()),
            drawText: false,
          ),
        ),
      ],
    );
  }

  /// Pre-filled OMR for batch
  static pw.Widget _idSectionPreFilled(String omrId) {
    final digits = omrId.padLeft(4, '0').split('').map(int.parse).toList();
    return _idSectionBase(
      fillResolver: (columnIndex, digit) => digits[columnIndex] == digit,
    );
  }

  static pw.Widget _idSection() {
    return _idSectionBase(
      fillResolver: (_, __) => false,
    );
  }

  static pw.Widget _idSectionBase({
    required bool Function(int columnIndex, int digit) fillResolver,
  }) {
    const relativeFirstColumnX =
        OmrPageConstants.omrIdFirstColumnX - OmrPageConstants.marginLeft;
    const relativeFirstRowY =
        OmrPageConstants.omrIdFirstRowY - OmrPageConstants.omrIdTop;
    const titleTop = 3.0;
    const digitLabelWidth = 8.0;
    const digitLabelOffset = 21.0;

    return pw.Container(
      width: double.infinity,
      height: OmrPageConstants.omrIdHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          width: _panelBorderWidth,
          color: _panelBorder,
        ),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            left: 0,
            right: 0,
            top: titleTop,
            child: pw.Center(
              child: pw.Text(
                'OMR ID (4 DIGITS)',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          ...List.generate(OmrPageConstants.omrIdColumns, (columnIndex) {
            final columnCenterX = relativeFirstColumnX +
                (columnIndex * OmrPageConstants.omrIdColumnSpacing);

            return pw.Stack(
              children: [
                ...List.generate(OmrPageConstants.omrIdRows, (digit) {
                  final bubbleCenterY = relativeFirstRowY +
                      (digit * OmrPageConstants.omrIdRowSpacing);

                  return pw.Positioned(
                    left: columnCenterX - digitLabelOffset,
                    top: bubbleCenterY - 3.2,
                    child: pw.SizedBox(
                      width: digitLabelWidth,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          '$digit',
                          style: const pw.TextStyle(fontSize: 5.8),
                        ),
                      ),
                    ),
                  );
                }),
                ...List.generate(OmrPageConstants.omrIdRows, (digit) {
                  final bubbleCenterY = relativeFirstRowY +
                      (digit * OmrPageConstants.omrIdRowSpacing);

                  return pw.Positioned(
                    left: columnCenterX -
                        (OmrPageConstants.omrIdBubbleDiameter / 2),
                    top: bubbleCenterY -
                        (OmrPageConstants.omrIdBubbleDiameter / 2),
                    child: pw.Container(
                      width: OmrPageConstants.omrIdBubbleDiameter,
                      height: OmrPageConstants.omrIdBubbleDiameter,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: fillResolver(columnIndex, digit)
                            ? PdfColors.black
                            : PdfColors.white,
                        border: pw.Border.all(
                          width: OmrPageConstants.omrIdBubbleBorder,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ],
      ),
    );
  }

  static pw.Widget _bubble() {
    return pw.Container(
      width: 11.5,
      height: 11.5,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: PdfColors.white,
        border: pw.Border.all(width: 1.2),
      ),
    );
  }

  static pw.Widget _footerNotes(
      Subject subject, SubjectSheetQrPayload qrPayload) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4, left: 2, right: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Lay flat, good lighting, dark pencil. Edge marks are for scanning — do not mark them.',
            style: const pw.TextStyle(fontSize: 5.8, color: _mutedInk),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildCalibrationMarks() {
    const bubbleTop = OmrPageConstants.calibrationY -
        (OmrPageConstants.answerBubbleDiameter / 2);

    return [
      pw.Positioned(
        left: OmrPageConstants.calibrationFilledX -
            (OmrPageConstants.answerBubbleDiameter / 2),
        top: bubbleTop,
        child: pw.Container(
          width: OmrPageConstants.answerBubbleDiameter,
          height: OmrPageConstants.answerBubbleDiameter,
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            color: PdfColors.black,
            border: pw.Border.all(
              width: OmrPageConstants.answerBubbleBorder,
              color: PdfColors.black,
            ),
          ),
        ),
      ),
      pw.Positioned(
        left: OmrPageConstants.calibrationEmptyX -
            (OmrPageConstants.answerBubbleDiameter / 2),
        top: bubbleTop,
        child: _bubble(),
      ),
    ];
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _fitHeaderText(String value, {required int maxChars}) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxChars) {
      return normalized;
    }
    return '${normalized.substring(0, maxChars - 3)}...';
  }
}
