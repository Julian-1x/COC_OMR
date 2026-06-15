import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';

void main() {
  const supportedItemCounts = [30, 40, 50, 60, 70, 80, 90, 100];
  const expectedLayouts = {
    30: ('30', 3, 10),
    40: ('40', 4, 10),
    50: ('50', 5, 10),
    60: ('60', 5, 12),
    70: ('70', 5, 14),
    80: ('80', 5, 16),
    90: ('90', 5, 18),
    100: ('100', 5, 20),
  };

  group('OMR template layout validation', () {
    test('supported item counts resolve to valid templates', () {
      for (final itemCount in supportedItemCounts) {
        final template = OmrTemplateSpec.forItemCount(itemCount);

        expect(template.columns, greaterThan(0),
            reason: 'columns for $itemCount');
        expect(template.rows, greaterThan(0), reason: 'rows for $itemCount');
        expect(template.rowHeight, greaterThan(0),
            reason: 'rowHeight for $itemCount');
        expect(
          template.columnWidth,
          greaterThan(0),
          reason: 'columnWidth for $itemCount',
        );
        expect(
          template.bubbleSpacingX,
          greaterThan(0),
          reason: 'bubbleSpacingX for $itemCount',
        );
      }
    });

    test('each supported item count uses a dedicated production layout', () {
      for (final itemCount in supportedItemCounts) {
        final template = OmrTemplateSpec.forItemCount(itemCount);
        final expected = expectedLayouts[itemCount]!;
        final (expectedTemplateId, expectedColumns, expectedRows) = expected;

        expect(template.templateId, expectedTemplateId,
            reason: 'template ID for $itemCount');
        expect(template.columns, expectedColumns,
            reason: 'columns for $itemCount');
        expect(template.rows, expectedRows, reason: 'rows for $itemCount');
        expect(template.maxItems, itemCount,
            reason: 'maxItems should stay exact for $itemCount');
        expect(template.supportedItemCounts, [itemCount],
            reason: 'supported counts should be dedicated for $itemCount');

        final (lastCol, lastRow) = template.questionPosition(itemCount);
        expect(lastCol, expectedColumns - 1,
            reason: 'last question should reach final column for $itemCount');
        expect(lastRow, expectedRows - 1,
            reason: 'last question should reach final row for $itemCount');
      }
    });

    test('QR payload includes explicit layout metadata for all templates', () {
      for (final itemCount in supportedItemCounts) {
        final subject = Subject(
          name: 'Subject $itemCount',
          answerKey: {for (int i = 1; i <= itemCount; i++) i: 'A'},
          totalQuestions: itemCount,
        );

        final qrData = AnswerSheetGenerator.buildSheetQrCodeData(subject);
        final payload = SubjectSheetQrPayload.fromJson(
          Map<String, dynamic>.from(jsonDecode(qrData) as Map),
        );

        expect(payload.version, 2, reason: 'payload version for $itemCount');
        expect(payload.hasExplicitLayout, isTrue,
            reason: 'layout metadata for $itemCount');
        expect(
          payload.layout?.templateId,
          OmrTemplateSpec.forItemCount(itemCount).templateId,
          reason: 'template ID for $itemCount',
        );
      }
    });

    test('answer bubble positions stay inside the page for all templates', () {
      for (final itemCount in supportedItemCounts) {
        final template = OmrTemplateSpec.forItemCount(itemCount);

        for (int question = 1; question <= itemCount; question++) {
          for (int optionIndex = 0;
              optionIndex < OmrPageConstants.answerOptionsCount;
              optionIndex++) {
            final (x, y) = template.bubblePosition(question, optionIndex);

            expect(
              x,
              inInclusiveRange(
                OmrPageConstants.marginLeft,
                OmrPageConstants.pageWidth - OmrPageConstants.marginRight,
              ),
              reason:
                  'bubble X for question $question on $itemCount-item sheet',
            );
            expect(
              y,
              inInclusiveRange(
                OmrPageConstants.answerGridTop,
                OmrPageConstants.answerGridBottom,
              ),
              reason:
                  'bubble Y for question $question on $itemCount-item sheet',
            );
          }
        }
      }
    });

    test('row reference marks match template row count', () {
      for (final itemCount in supportedItemCounts) {
        final template = OmrTemplateSpec.forItemCount(itemCount);
        final rowMarks = OmrRowMarks.getRowMarkPositions(template);

        expect(
          rowMarks.length,
          template.rows,
          reason: 'one row tick per template row for $itemCount',
        );
        for (final y in rowMarks) {
          expect(
            y,
            inInclusiveRange(
              OmrPageConstants.answerRowsTop,
              OmrPageConstants.answerRowsBottom,
            ),
            reason: 'row mark Y for $itemCount-item sheet',
          );
        }
      }
    });

    test('timing mark grid matches scanner sampling contract', () {
      final topMarks = <double>[];
      for (double x = OmrPageConstants.timingMarkStartX;
          x < OmrPageConstants.timingMarkEndX;
          x += OmrPageConstants.timingMarkSpacing) {
        topMarks.add(x);
      }

      expect(topMarks, isNotEmpty);
      expect(topMarks.first, OmrPageConstants.timingMarkStartX);
      expect(
        topMarks.last,
        lessThan(OmrPageConstants.timingMarkEndX),
      );

      final verticalMarks = <double>[];
      for (double y = OmrPageConstants.timingMarkStartY;
          y < OmrPageConstants.timingMarkEndY;
          y += OmrPageConstants.timingMarkSpacing) {
        verticalMarks.add(y);
      }

      expect(verticalMarks.length, greaterThanOrEqualTo(4));
    });

    test('OMR ID and calibration anchors stay inside their fixed sections', () {
      expect(
        OmrPageConstants.omrIdFirstRowY,
        inInclusiveRange(
          OmrPageConstants.omrIdTop,
          OmrPageConstants.omrIdBottom,
        ),
      );

      const lastOmrRowY = OmrPageConstants.omrIdFirstRowY +
          ((OmrPageConstants.omrIdRows - 1) * OmrPageConstants.omrIdRowSpacing);
      expect(
        lastOmrRowY,
        inInclusiveRange(
          OmrPageConstants.omrIdTop,
          OmrPageConstants.omrIdBottom,
        ),
      );

      expect(
        OmrPageConstants.calibrationFilledX,
        inInclusiveRange(
          OmrPageConstants.marginLeft,
          OmrPageConstants.pageWidth - OmrPageConstants.marginRight,
        ),
      );
      expect(
        OmrPageConstants.calibrationEmptyX,
        inInclusiveRange(
          OmrPageConstants.marginLeft,
          OmrPageConstants.pageWidth - OmrPageConstants.marginRight,
        ),
      );
      expect(
        OmrPageConstants.calibrationY,
        inInclusiveRange(0, OmrPageConstants.pageHeight),
      );
    });
  });
}
