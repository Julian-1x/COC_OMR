import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/omr_template_specs.dart';

void main() {
  group('Frozen 30–100 presets', () {
    test('template numbers stay exactly as proven in production', () {
      expect(OmrTemplateSpec.template50.columns, 5);
      expect(OmrTemplateSpec.template50.rows, 10);
      expect(OmrTemplateSpec.template50.rowHeight, 49.4);
      expect(OmrTemplateSpec.template50.bubbleSpacingX, 17.0);
      expect(OmrTemplateSpec.template100.rows, 20);
      expect(OmrTemplateSpec.template100.rowHeight, 24.7);
    });

    test('preset resolve ignores custom knobs when custom is off', () {
      final profile = OmrLayoutProfile.resolve(
        totalQuestions: 50,
        useCustomLayout: false,
        optionsCount: 3,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.crosswise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      expect(profile.isCustom, isFalse);
      expect(profile.optionsCount, 5);
      expect(profile.grid.templateId, '50');
      expect(profile.geometry.pageWidth, OmrPageConstants.pageWidth);
      expect(profile.geometry.pageHeight, OmrPageConstants.pageHeight);
    });
  });

  group('Flexible custom forms', () {
    test('crosswise uses landscape page size', () {
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 40,
        optionsCount: 4,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.crosswise,
          pageFill: OmrLayoutPageFill.full,
        ),
      );
      expect(fit.isOk, isTrue);
      final g = fit.profile!.geometry;
      expect(g.pageWidth, OmrPageConstants.pageHeight);
      expect(g.pageHeight, OmrPageConstants.pageWidth);
      expect(g.isLandscapePrint, isTrue);
      expect(g.printOrientationLabel, 'Landscape');
      expect(g.timingMarkEndX, greaterThan(g.timingMarkStartX));
      expect(g.answerGridContentHeight, greaterThan(40));
    });

    test('lengthwise uses portrait page size', () {
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 40,
        optionsCount: 4,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.full,
        ),
      );
      expect(fit.isOk, isTrue);
      final g = fit.profile!.geometry;
      expect(g.isLandscapePrint, isFalse);
      expect(g.printOrientationLabel, 'Portrait');
    });

    test('quarter places a smaller content block with marks inside it', () {
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 20,
        optionsCount: 3,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      expect(fit.isOk, isTrue);
      final g = fit.profile!.geometry;
      expect(g.answerGridRight, lessThan(OmrPageConstants.pageWidth * 0.6));
      expect(g.answerGridBottom, lessThan(OmrPageConstants.pageHeight * 0.6));
      expect(g.timingMarkEndY, lessThan(OmrPageConstants.pageHeight * 0.6));
    });

    test('legacy compact/long ids map to lengthwise full', () {
      expect(OmrLayoutForm.fromId('compact').id, 'lengthwise_full');
      expect(OmrLayoutForm.fromId('long').id, 'lengthwise_full');
      expect(OmrLayoutForm.fromId('crosswise_quarter').pageFill,
          OmrLayoutPageFill.quarter);
    });

    test('quarter sheet rejects too many questions with clear capacity', () {
      final quarter = const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.quarter,
      );
      final maxFit = OmrLayoutProfile.maxFitItems(
        form: quarter,
        optionsCount: 5,
      );
      expect(maxFit, lessThanOrEqualTo(20));
      expect(maxFit, greaterThanOrEqualTo(OmrLayoutProfile.minCustomItems));

      final tooMany = OmrLayoutProfile.tryCompute(
        itemCount: 50,
        optionsCount: 5,
        form: quarter,
      );
      expect(tooMany.isOk, isFalse);
      expect(tooMany.errorMessage, contains('at most $maxFit'));
      expect(tooMany.errorMessage, contains('50'));
    });

    test('half and full also enforce capacity (not only 1/4)', () {
      final half = const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.half,
      );
      final fullCross = const OmrLayoutForm(
        orientation: OmrLayoutOrientation.crosswise,
        pageFill: OmrLayoutPageFill.full,
      );

      expect(OmrLayoutProfile.maxFitItems(form: half, optionsCount: 5),
          lessThanOrEqualTo(45));
      expect(
        OmrLayoutProfile.tryCompute(
          itemCount: 80,
          optionsCount: 5,
          form: half,
        ).isOk,
        isFalse,
      );

      expect(
        OmrLayoutProfile.maxFitItems(form: fullCross, optionsCount: 5),
        lessThanOrEqualTo(80),
      );
      expect(
        OmrLayoutProfile.tryCompute(
          itemCount: 100,
          optionsCount: 5,
          form: fullCross,
        ).isOk,
        isFalse,
      );
    });

    test('custom resolve does not silently switch to standard preset', () {
      final profile = OmrLayoutProfile.resolve(
        totalQuestions: 50,
        useCustomLayout: true,
        optionsCount: 5,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      expect(profile.isCustom, isTrue);
      expect(profile.form.pageFill, OmrLayoutPageFill.quarter);
      expect(profile.itemCount, lessThanOrEqualTo(20));
      expect(profile.geometry.answerGridBottom,
          lessThan(OmrPageConstants.pageHeight * 0.6));
    });

    test('capacity hint names the sheet form', () {
      final hint = OmrLayoutProfile.capacityHint(
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
        optionsCount: 3,
      );
      expect(hint.toLowerCase(), contains('1/4'));
      expect(hint, contains('A-B-C'));
    });

    test('explicit grid 2x3 on full lengthwise passes', () {
      final fit = OmrLayoutProfile.tryComputeExplicitGrid(
        columns: 2,
        rows: 3,
        optionsCount: 5,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.full,
        ),
      );
      expect(fit.isOk, isTrue);
      expect(fit.profile!.grid.columns, 2);
      expect(fit.profile!.grid.rows, 3);
      expect(fit.profile!.itemCount, 6);
    });

    test('explicit grid rejects overcrowded quarter sheet', () {
      final fit = OmrLayoutProfile.tryComputeExplicitGrid(
        columns: 5,
        rows: 10,
        optionsCount: 5,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      expect(fit.isOk, isFalse);
    });

    test('suggestLayouts offers all fitting forms including landscape and half',
        () {
      final suggestions = OmrLayoutProfile.suggestLayouts(
        itemCount: 10,
        optionsCount: 4,
      );
      expect(suggestions, isNotEmpty);
      expect(
        suggestions.any((s) => s.form.id == 'lengthwise_full'),
        isTrue,
      );
      expect(
        suggestions.any((s) => s.form.id == 'lengthwise_half'),
        isTrue,
      );
      expect(
        suggestions.any((s) => s.form.orientation == OmrLayoutOrientation.crosswise),
        isTrue,
      );
      // Nothing that fits should appear under blocked.
      final blocked = OmrLayoutProfile.blockedLayouts(
        itemCount: 10,
        optionsCount: 4,
      );
      expect(
        blocked.any((b) => b.form.id == 'lengthwise_half'),
        isFalse,
      );
    });

    test('suggestLayouts blocks only forms that cannot fit', () {
      final suggestions = OmrLayoutProfile.suggestLayouts(
        itemCount: 15,
        optionsCount: 5,
      );
      expect(suggestions, isNotEmpty);
      expect(
        suggestions.any((s) => s.form.pageFill == OmrLayoutPageFill.full),
        isTrue,
      );
    });

    test('suggestLayouts returns empty when nothing fits', () {
      final suggestions = OmrLayoutProfile.suggestLayouts(
        itemCount: 4,
        optionsCount: 5,
      );
      expect(suggestions, isEmpty);
    });
  });

  group('Custom sheet geometry quality', () {
    test('quarter sheet keeps OMR ID bubbles below title band', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      expect(g.qrCodeSize, greaterThanOrEqualTo(56.0));
      expect(g.omrIdFirstRowY, greaterThan(g.omrIdTop + 12.0));
      expect(g.omrIdBottom, lessThanOrEqualTo(g.answerGridTop));
      expect(g.omrIdHeight, greaterThan(90.0));
    });

    test('half and crosswise quarter keep scan-friendly QR size', () {
      for (final form in [
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.half,
        ),
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.crosswise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      ]) {
        final g = OmrSheetGeometry.forForm(form);
        expect(g.qrCodeSize, greaterThanOrEqualTo(56.0));
        expect(g.omrIdBottom, lessThanOrEqualTo(g.answerGridTop + 0.01));
      }
    });

    test('timing marks span the answer grid band', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      expect(g.timingMarkStartY, lessThan(g.answerRowsTop));
      expect(g.timingMarkEndY, greaterThan(g.answerRowsBottom));
    });
  });

  group('OmrSheetTiling', () {
    test('lengthwise quarter tiles 4 per bond page', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      final tiling = OmrSheetTiling.forGeometry(g);
      expect(tiling, isNotNull);
      expect(tiling!.columns, 2);
      expect(tiling.rows, 2);
      expect(tiling.sheetsPerPage, 4);
    });

    test('lengthwise half tiles 2 per bond page', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.half,
        ),
      );
      final tiling = OmrSheetTiling.forGeometry(g);
      expect(tiling, isNotNull);
      expect(tiling!.columns, 1);
      expect(tiling.rows, 2);
      expect(tiling.sheetsPerPage, 2);
    });

    test('crosswise half tiles 2 per landscape page', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.crosswise,
          pageFill: OmrLayoutPageFill.half,
        ),
      );
      final tiling = OmrSheetTiling.forGeometry(g);
      expect(tiling, isNotNull);
      expect(tiling!.sheetsPerPage, 2);
    });

    test('crosswise quarter tiles 4 per landscape page', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.crosswise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      final tiling = OmrSheetTiling.forGeometry(g);
      expect(tiling, isNotNull);
      expect(tiling!.sheetsPerPage, 4);
    });

    test('full page does not tile', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.full,
        ),
      );
      expect(OmrSheetTiling.forGeometry(g), isNull);
    });

    test('tile offsets cover each quadrant on quarter sheet', () {
      final g = OmrSheetGeometry.forForm(
        const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.quarter,
        ),
      );
      final tiling = OmrSheetTiling.forGeometry(g)!;
      expect(tiling.tileOffsetX(0, g), 0);
      expect(tiling.tileOffsetY(0, g), 0);
      expect(tiling.tileOffsetX(1, g), g.contentBlockWidth);
      expect(tiling.tileOffsetY(2, g), g.contentBlockHeight);
      expect(
        tiling.tileOffsetX(3, g) + g.contentBlockWidth,
        closeTo(g.pageWidth, 0.05),
      );
      expect(
        tiling.tileOffsetY(3, g) + g.contentBlockHeight,
        closeTo(g.pageHeight, 0.05),
      );
    });
  });
}
