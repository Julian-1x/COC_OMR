import 'dart:convert';
import 'dart:math' show min;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/scanner_session_layout.dart';
import 'package:omr_app/theme/app_colors.dart';
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

  /// Block printing Custom sheets that do not fit — wrong density risks bad grades.
  static void _ensureCustomLayoutPrintable(Subject subject) {
    if (!subject.useCustomLayout) {
      return;
    }
    final examReadyError =
        ScannerSessionLayout.examReadyScanErrorForSubject(subject);
    if (examReadyError != null) {
      throw Exception(examReadyError);
    }
    final profile = subject.layoutProfile;
    if (profile.itemCount != subject.totalQuestions) {
      throw Exception(
        'Custom sheet question count does not match a scannable layout. '
        'Pick the layout again under Print Sheets before printing.',
      );
    }
    final fit = subject.customGridColumns != null && subject.customGridRows != null
        ? OmrLayoutProfile.tryComputeExplicitGrid(
            columns: subject.customGridColumns!,
            rows: subject.customGridRows!,
            optionsCount: subject.optionsCount,
            form: subject.layoutForm,
          )
        : OmrLayoutProfile.tryCompute(
            itemCount: subject.totalQuestions,
            optionsCount: subject.optionsCount,
            form: subject.layoutForm,
          );
    if (!fit.isOk) {
      throw Exception(
        fit.errorMessage ??
            'This custom sheet layout does not fit. '
                'Change the saved layout or question count before printing.',
      );
    }
  }

  static PdfPageFormat _printPageFormat(OmrSheetGeometry geometry) =>
      PdfPageFormat(geometry.pageWidth, geometry.pageHeight);

  static Future<bool> _confirmPrintOrientation(
    BuildContext context,
    OmrLayoutProfile profile,
  ) async {
    if (!profile.shouldConfirmPrintOrientation) {
      return true;
    }
    final orientation = profile.geometry.printOrientationLabel;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Print in $orientation'),
        content: Text(profile.printOrientationReminder),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
            ),
            child: const Text('Continue to print'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  static Future<void> _layoutPdfForProfile({
    required OmrLayoutProfile profile,
    required LayoutCallback onLayout,
    String name = 'Document',
    BuildContext? printContext,
  }) async {
    if (printContext != null && printContext.mounted) {
      final ok = await _confirmPrintOrientation(printContext, profile);
      if (!ok) {
        return;
      }
    }
    final format = _printPageFormat(profile.geometry);
    await Printing.layoutPdf(
      onLayout: onLayout,
      name: name,
      format: format,
    );
  }

  /// Generate single OMR sheet (original)
  static Future<void> generateAndPrint({
    required Subject subject,
    String? sectionName,
    BuildContext? printContext,
    bool tileMultiUp = true,
  }) async {
    _ensureCustomLayoutPrintable(subject);
    final pdf = pw.Document();
    final totalQuestions =
        subject.totalQuestions > 0 ? subject.totalQuestions : 50;
    final qrPayload = _buildSheetQrPayload(subject, sectionName: sectionName);
    final profile = subject.layoutProfile;
    final template = profile.grid;
    final optionsCount = profile.optionsCount;
    final g = profile.geometry;

    _appendTiledPages(
      pdf: pdf,
      profile: profile,
      tileMultiUp: tileMultiUp,
      sheetBodies: [
        _buildAbsoluteLayout(
          subject,
          qrPayload,
          totalQuestions,
          template,
          g,
          optionsCount: optionsCount,
        ),
      ],
    );

    await _layoutPdfForProfile(
      profile: profile,
      printContext: printContext,
      onLayout: (_) async => pdf.save(),
    );
    await LocalDataStore.instance.persistCountersNow();
  }

  /// Generate multiple identical sheets (same QR) for a subject/section.
  static Future<void> generateMultiple({
    required Subject subject,
    required String sectionName,
    required int copies,
    BuildContext? printContext,
    bool tileMultiUp = true,
  }) async {
    _ensureCustomLayoutPrintable(subject);
    final safeCopies = copies < 1 ? 1 : copies;
    final pdf = pw.Document();
    final totalQuestions =
        subject.totalQuestions > 0 ? subject.totalQuestions : 50;
    final profile = subject.layoutProfile;
    final template = profile.grid;
    final optionsCount = profile.optionsCount;
    final g = profile.geometry;

    final sheetBodies = <List<pw.Widget>>[];
    for (var i = 0; i < safeCopies; i++) {
      final qrPayload = _buildSheetQrPayload(subject, sectionName: sectionName);
      sheetBodies.add(
        _buildAbsoluteLayout(
          subject,
          qrPayload,
          totalQuestions,
          template,
          g,
          optionsCount: optionsCount,
        ),
      );
    }

    _appendTiledPages(
      pdf: pdf,
      profile: profile,
      tileMultiUp: tileMultiUp,
      sheetBodies: sheetBodies,
    );

    await _layoutPdfForProfile(
      profile: profile,
      printContext: printContext,
      name: '${subject.displayName}_${sectionName}_${safeCopies}copies.pdf',
      onLayout: (_) async => pdf.save(),
    );
    await LocalDataStore.instance.persistCountersNow();
  }

  /// Batch generate class set (1 sheet per student, pre-filled OMR)
  static Future<void> batchGenerate({
    required Subject subject,
    required String sectionName,
    BuildContext? printContext,
    bool tileMultiUp = true,
  }) async {
    _ensureCustomLayoutPrintable(subject);
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
    final profile = subject.layoutProfile;
    final template = profile.grid;
    final optionsCount = profile.optionsCount;
    final g = profile.geometry;

    final sheetBodies = <List<pw.Widget>>[];
    for (final student in sectionStudents) {
      final qrPayload = _buildSheetQrPayload(subject, sectionName: sectionName);
      sheetBodies.add(
        _buildAbsoluteLayoutBatch(
          subject,
          qrPayload,
          totalQuestions,
          template,
          student,
          sectionName,
          g,
          optionsCount: optionsCount,
        ),
      );
    }

    _appendTiledPages(
      pdf: pdf,
      profile: profile,
      tileMultiUp: tileMultiUp,
      sheetBodies: sheetBodies,
    );

    await _layoutPdfForProfile(
      profile: profile,
      printContext: printContext,
      name:
          '${subject.displayName}_${sectionName}_${sectionStudents.length}sheets.pdf',
      onLayout: (_) async => pdf.save(),
    );
    await LocalDataStore.instance.persistCountersNow();
  }

  /// Pack [sheetBodies] onto PDF pages. Each body is one sheet (no corner marks).
  static void _appendTiledPages({
    required pw.Document pdf,
    required OmrLayoutProfile profile,
    required List<List<pw.Widget>> sheetBodies,
    required bool tileMultiUp,
  }) {
    if (sheetBodies.isEmpty) {
      return;
    }

    final g = profile.geometry;
    final tiling =
        tileMultiUp ? OmrSheetTiling.forGeometry(g) : null;
    final perPage = tiling?.sheetsPerPage ?? 1;
    final pageFormat = PdfPageFormat(g.pageWidth, g.pageHeight);

    for (var start = 0; start < sheetBodies.length; start += perPage) {
      final end = min(start + perPage, sheetBodies.length);
      final chunk = sheetBodies.sublist(start, end);

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(0),
          build: (context) => pw.Stack(
            children: [
              if (tiling != null) ..._buildTileCutGuides(tiling, g),
              for (var slot = 0; slot < chunk.length; slot++)
                _positionedSheetTile(
                  profile: profile,
                  dx: tiling?.tileOffsetX(slot, g) ?? 0,
                  dy: tiling?.tileOffsetY(slot, g) ?? 0,
                  body: chunk[slot],
                ),
            ],
          ),
        ),
      );
    }
  }

  static pw.Widget _positionedSheetTile({
    required OmrLayoutProfile profile,
    required double dx,
    required double dy,
    required List<pw.Widget> body,
  }) {
    return pw.Positioned(
      left: dx,
      top: dy,
      child: pw.Stack(
        children: [
          _cornerMarkers(profile),
          ...body,
        ],
      ),
    );
  }

  /// Light guides between tiled sheets — cosmetic only; marks stay on each tile.
  static List<pw.Widget> _buildTileCutGuides(
    OmrSheetTiling tiling,
    OmrSheetGeometry g,
  ) {
    const guideColor = PdfColors.grey300;
    const guideWidth = 0.6;
    final guides = <pw.Widget>[];
    final blockW = g.contentBlockWidth;
    final blockH = g.contentBlockHeight;

    for (var column = 1; column < tiling.columns; column++) {
      final x = column * blockW;
      guides.add(
        pw.Positioned(
          left: x - guideWidth / 2,
          top: 0,
          child: pw.Container(
            width: guideWidth,
            height: g.pageHeight,
            color: guideColor,
          ),
        ),
      );
    }
    for (var row = 1; row < tiling.rows; row++) {
      final y = row * blockH;
      guides.add(
        pw.Positioned(
          left: 0,
          top: y - guideWidth / 2,
          child: pw.Container(
            width: g.pageWidth,
            height: guideWidth,
            color: guideColor,
          ),
        ),
      );
    }
    return guides;
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

  /// Content-block bounds for registration marks.
  /// Full-page presets hug the PDF page; half/quarter hug the used block only.
  static List<double> _usedBlock(OmrSheetGeometry g) {
    return [0.0, 0.0, g.contentBlockWidth, g.contentBlockHeight];
  }

  static pw.Widget _cornerMarkers(OmrLayoutProfile profile) {
    final g = profile.geometry;
    final size = g.cornerMarkerSize;
    final offset = g.cornerMarkerOffset;
    final block = _usedBlock(g);
    final usedLeft = block[0];
    final usedTop = block[1];
    final usedRight = block[2];
    final usedBottom = block[3];
    return pw.Stack(
      children: [
        // Four corner markers at content-block corners (not full page for half/quarter)
        pw.Positioned(
          left: usedLeft + offset,
          top: usedTop + offset,
          child: _cornerBox(size),
        ),
        pw.Positioned(
          left: usedRight - offset - size,
          top: usedTop + offset,
          child: _cornerBox(size),
        ),
        pw.Positioned(
          left: usedLeft + offset,
          top: usedBottom - offset - size,
          child: _cornerBox(size),
        ),
        pw.Positioned(
          left: usedRight - offset - size,
          top: usedBottom - offset - size,
          child: _cornerBox(size),
        ),
        // Scanner registration marks — positions come from layout geometry.
        ..._buildTimingMarks(g),
        // Row reference marks for answer grid alignment validation
        ..._buildRowMarks(profile),
      ],
    );
  }

  /// Build all page content using absolute positioning from layout geometry.
  /// This ensures PDF positions exactly match what the scanner expects.
  static List<pw.Widget> _buildAbsoluteLayout(
    Subject subject,
    SubjectSheetQrPayload qrPayload,
    int totalQuestions,
    OmrTemplateSpec template,
    OmrSheetGeometry g, {
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    return [
      // Header section at fixed position
      pw.Positioned(
        left: g.marginLeft,
        top: g.headerTop,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          height: g.headerHeight,
          child: _headerSection(subject, qrPayload, g),
        ),
      ),
      // OMR ID section at fixed position
      pw.Positioned(
        left: g.marginLeft,
        top: g.omrIdTop,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          height: g.omrIdHeight,
          child: _idSection(g),
        ),
      ),
      // Answer grid at fixed position - this is the critical section
      pw.Positioned(
        left: g.answerGridLeft,
        top: g.answerGridTop,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          height: g.answerGridHeight,
          child: _answersSectionAbsolute(
            totalQuestions,
            template,
            g,
            optionsCount: optionsCount,
          ),
        ),
      ),
      // Footer/calibration section at fixed position
      pw.Positioned(
        left: g.marginLeft,
        top: g.answerRowsBottom,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          child: _footerNotes(subject, qrPayload),
        ),
      ),
      ..._buildCalibrationMarks(g),
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
    OmrSheetGeometry g, {
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    return [
      // Header section with student info at fixed position
      pw.Positioned(
        left: g.marginLeft,
        top: g.headerTop,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          height: g.headerHeight,
          child: _headerSectionBatch(
              subject, qrPayload, student, sectionName, g),
        ),
      ),
      // Pre-filled OMR ID section at fixed position
      pw.Positioned(
        left: g.marginLeft,
        top: g.omrIdTop,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          height: g.omrIdHeight,
          child: _idSectionPreFilled(student.omrId, g),
        ),
      ),
      // Answer grid at fixed position
      pw.Positioned(
        left: g.answerGridLeft,
        top: g.answerGridTop,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          height: g.answerGridHeight,
          child: _answersSectionAbsolute(
            totalQuestions,
            template,
            g,
            optionsCount: optionsCount,
          ),
        ),
      ),
      // Footer/calibration section at fixed position
      pw.Positioned(
        left: g.marginLeft,
        top: g.answerRowsBottom,
        child: pw.SizedBox(
          width: g.answerGridWidth,
          child: _footerNotes(subject, qrPayload),
        ),
      ),
      ..._buildCalibrationMarks(g),
    ];
  }

  /// Answer section using absolute row positioning to match scanner expectations
  static pw.Widget _answersSectionAbsolute(
    int totalQuestions,
    OmrTemplateSpec template,
    OmrSheetGeometry g, {
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    return pw.Container(
      width: g.answerGridWidth,
      height: g.answerGridHeight,
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
                height: g.answerGridHeight,
                child: pw.Stack(
                  children: [
                    _answerOptionIndicatorRow(
                      bubbleSpacingX: template.bubbleSpacingX,
                      columnWidth: template.columnWidth,
                      g: g,
                      optionsCount: optionsCount,
                    ),
                    pw.Positioned(
                      left: 0,
                      top: g.answerOptionIndicatorHeight,
                      child: pw.SizedBox(
                        width: template.columnWidth,
                        height: g.answerGridContentHeight,
                        child: _questionColumnAbsolute(
                          startQuestion: startQ,
                          endQuestion: endQ,
                          totalRows: template.rows,
                          rowHeight: template.rowHeight,
                          bubbleSpacingX: template.bubbleSpacingX,
                          columnWidth: template.columnWidth,
                          g: g,
                          optionsCount: optionsCount,
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
    required OmrSheetGeometry g,
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    final opts = optionsCount.clamp(2, 5);
    final bubbleAreaWidth = bubbleSpacingX * (opts - 1);
    final usableWidth = columnWidth - (g.answerColumnInset * 2);
    final rowContentWidth = g.questionNumberWidth +
        g.answerNumberBubbleGap +
        bubbleAreaWidth;
    final rowContentLeft =
        g.answerColumnInset + ((usableWidth - rowContentWidth) / 2);
    final bubbleAreaLeft =
        rowContentLeft + g.questionNumberWidth + g.answerNumberBubbleGap;

    return pw.SizedBox(
      width: columnWidth,
      height: g.answerOptionIndicatorHeight,
      child: pw.Stack(
        children: List.generate(opts, (optIndex) {
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
    required OmrSheetGeometry g,
    int optionsCount = OmrPageConstants.answerOptionsCount,
  }) {
    final opts = optionsCount.clamp(2, 5);
    final questionCount = endQuestion - startQuestion + 1;
    final bubbleAreaWidth = bubbleSpacingX * (opts - 1);
    final usableWidth = columnWidth - (g.answerColumnInset * 2);
    final rowContentWidth = g.questionNumberWidth +
        g.answerNumberBubbleGap +
        bubbleAreaWidth;
    final rowContentLeft =
        g.answerColumnInset + ((usableWidth - rowContentWidth) / 2);
    final bubbleAreaLeft =
        rowContentLeft + g.questionNumberWidth + g.answerNumberBubbleGap;
    final bubbleDiameter = g.answerBubbleDiameter;

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
                ...List.generate(opts, (optIndex) {
                  return pw.Positioned(
                    left: bubbleAreaLeft +
                        (optIndex * bubbleSpacingX) -
                        (bubbleDiameter / 2),
                    top: (rowHeight / 2) - (bubbleDiameter / 2),
                    child: _bubble(bubbleDiameter),
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
  static List<pw.Widget> _buildTimingMarks(OmrSheetGeometry g) {
    final markSize = g.timingMarkSize;
    final markSpacing = g.timingMarkSpacing;
    final edgeOffset = g.timingMarkEdgeOffset;
    final startX = g.timingMarkStartX;
    final endX = g.timingMarkEndX;
    final startY = g.timingMarkStartY;
    final endY = g.timingMarkEndY;
    final block = _usedBlock(g);
    final usedLeft = block[0];
    final usedTop = block[1];
    final usedRight = block[2];
    final usedBottom = block[3];
    final marks = <pw.Widget>[];

    // Top edge timing marks (skip corners)
    for (double x = startX; x < endX; x += markSpacing) {
      marks.add(pw.Positioned(
        left: x,
        top: usedTop + edgeOffset,
        child: pw.Container(
          width: markSize,
          height: markSize,
          decoration: const pw.BoxDecoration(
            color: PdfColors.black,
          ),
        ),
      ));
    }

    // Bottom edge timing marks (skip corners) — hug content block, not page
    for (double x = startX; x < endX; x += markSpacing) {
      marks.add(pw.Positioned(
        left: x,
        top: usedBottom - edgeOffset - markSize,
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
        left: usedLeft + edgeOffset,
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

    // Right edge timing marks (skip corners) — hug content block, not page
    for (double y = startY; y < endY; y += markSpacing) {
      marks.add(pw.Positioned(
        left: usedRight - edgeOffset - markSize,
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
  static List<pw.Widget> _buildRowMarks(OmrLayoutProfile profile) {
    final g = profile.geometry;
    final marks = <pw.Widget>[];

    for (var row = 0; row < profile.grid.rows; row++) {
      final y = profile.rowCenterY(row);
      marks.add(pw.Positioned(
        left: g.rowMarkX,
        top: y - (g.rowMarkSize / 2),
        child: pw.Container(
          width: g.rowMarkSize,
          height: g.rowMarkSize,
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
  static pw.Widget _headerSectionBatch(
      Subject subject,
      SubjectSheetQrPayload qrPayload,
      Student student,
      String sectionName,
      OmrSheetGeometry g) {
    return _buildHeader(
      subject: subject,
      qrPayload: qrPayload,
      g: g,
      subtitleLine1: _fitHeaderText('STUDENT: ${student.name}', maxChars: 42),
      subtitleLine2: _fitHeaderText(
        'OMR: ${student.omrId}   SECTION: $sectionName',
        maxChars: 42,
      ),
    );
  }

  /// Blank-sheet header: name write-in + section info (OMR ID stays empty below).
  /// Text stays inside [OmrSheetGeometry.headerHeight] — do not grow this box.
  static pw.Widget _headerSection(
      Subject subject, SubjectSheetQrPayload qrPayload, OmrSheetGeometry g) {
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
      g: g,
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
    required OmrSheetGeometry g,
    required String subtitleLine1,
    required String subtitleLine2,
    String instructionLine =
        'Fill one bubble per question. Use a dark pencil (HB or 2B).',
  }) {
    final scale = g.layoutScale;
    final titleFontSize = (16 * scale).clamp(11.0, 18.0);
    final metaFontSize = (8.2 * scale).clamp(7.0, 8.2);
    final hintFontSize = (7.2 * scale).clamp(6.2, 7.2);
    final textMaxWidth = (g.answerGridWidth - g.qrCodeSize - 10)
        .clamp(80.0, g.answerGridWidth);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: textMaxWidth,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _fitHeaderText(subject.displayName, maxChars: 28),
                style: pw.TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: (4 * scale).clamp(2.0, 4.0)),
              pw.Text(
                subtitleLine1,
                style: pw.TextStyle(fontSize: metaFontSize),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                subtitleLine2,
                style: pw.TextStyle(fontSize: metaFontSize),
              ),
              if (scale >= 0.55) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  instructionLine,
                  style: pw.TextStyle(fontSize: hintFontSize, color: _mutedInk),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: (10 * scale).clamp(6.0, 12.0)),
        pw.Container(
          width: g.qrCodeSize,
          height: g.qrCodeSize,
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
  static pw.Widget _idSectionPreFilled(String omrId, OmrSheetGeometry g) {
    final digits = omrId.padLeft(4, '0').split('').map(int.parse).toList();
    return _idSectionBase(
      g: g,
      fillResolver: (columnIndex, digit) => digits[columnIndex] == digit,
    );
  }

  static pw.Widget _idSection(OmrSheetGeometry g) {
    return _idSectionBase(
      g: g,
      fillResolver: (_, __) => false,
    );
  }

  static pw.Widget _idSectionBase({
    required OmrSheetGeometry g,
    required bool Function(int columnIndex, int digit) fillResolver,
  }) {
    final relativeFirstColumnX = g.omrIdFirstColumnX - g.marginLeft;
    final relativeFirstRowY = g.omrIdFirstRowY - g.omrIdTop;
    const omrIdTitleBand = 14.0;
    final scale = g.layoutScale;
    final titleFontSize = (9 * scale).clamp(7.0, 9.0);
    final digitFontSize = (5.8 * scale).clamp(5.0, 5.8);
    final digitLabelWidth = (8 * scale).clamp(6.0, 8.0);
    final digitLabelOffset =
        (g.omrIdBubbleDiameter / 2) + (10 * scale).clamp(7.0, 10.0);

    return pw.Container(
      width: double.infinity,
      height: g.omrIdHeight,
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
            top: 2,
            child: pw.SizedBox(
              height: omrIdTitleBand - 2,
              child: pw.Center(
                child: pw.Text(
                  'OMR ID (4 DIGITS)',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: titleFontSize,
                  ),
                ),
              ),
            ),
          ),
          ...List.generate(OmrPageConstants.omrIdColumns, (columnIndex) {
            final columnCenterX = relativeFirstColumnX +
                (columnIndex * g.omrIdColumnSpacing);

            return pw.Stack(
              children: [
                ...List.generate(OmrPageConstants.omrIdRows, (digit) {
                  final bubbleCenterY =
                      relativeFirstRowY + (digit * g.omrIdRowSpacing);

                  return pw.Positioned(
                    left: columnCenterX - digitLabelOffset,
                    top: bubbleCenterY - (digitFontSize / 2),
                    child: pw.SizedBox(
                      width: digitLabelWidth,
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          '$digit',
                          style: pw.TextStyle(fontSize: digitFontSize),
                        ),
                      ),
                    ),
                  );
                }),
                ...List.generate(OmrPageConstants.omrIdRows, (digit) {
                  final bubbleCenterY =
                      relativeFirstRowY + (digit * g.omrIdRowSpacing);

                  return pw.Positioned(
                    left: columnCenterX - (g.omrIdBubbleDiameter / 2),
                    top: bubbleCenterY - (g.omrIdBubbleDiameter / 2),
                    child: pw.Container(
                      width: g.omrIdBubbleDiameter,
                      height: g.omrIdBubbleDiameter,
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

  static pw.Widget _bubble([double diameter = 11.5]) {
    return pw.Container(
      width: diameter,
      height: diameter,
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
            'Lay flat, good lighting, dark pencil. Edge marks are for scanning - do not mark them.',
            style: const pw.TextStyle(fontSize: 5.8, color: _mutedInk),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildCalibrationMarks(OmrSheetGeometry g) {
    // Keep answerBubbleDiameter for filled/empty so preset sheets match prior PDFs.
    final diameter = g.answerBubbleDiameter;
    final bubbleTop = g.calibrationY - (diameter / 2);

    return [
      pw.Positioned(
        left: g.calibrationFilledX - (diameter / 2),
        top: bubbleTop,
        child: pw.Container(
          width: diameter,
          height: diameter,
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
        left: g.calibrationEmptyX - (diameter / 2),
        top: bubbleTop,
        child: _bubble(diameter),
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
