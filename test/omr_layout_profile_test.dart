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
        itemCount: 10,
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
          lessThanOrEqualTo(OmrLayoutProfile.maxCustomItems));
      expect(OmrLayoutProfile.maxFitItems(form: half, optionsCount: 5),
          greaterThanOrEqualTo(OmrLayoutProfile.minCustomItems));
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
        lessThanOrEqualTo(OmrLayoutProfile.maxCustomItems),
      );
      expect(
        OmrLayoutProfile.maxFitItems(form: fullCross, optionsCount: 5),
        greaterThanOrEqualTo(OmrLayoutProfile.minCustomItems),
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

    test('packs even columns whenever a scan-safe divisor exists', () {
      // Applies to every count — not a special case for 50.
      const sampleCounts = <int>[
        5, 6, 7, 8, 9, 10, 12, 15, 16, 18, 20, 21, 24, 25, 30, 32, 35, 36,
        40, 42, 45, 48, 50, 51, 54, 55, 60, 63, 64, 70, 72, 75, 80, 90, 100,
      ];
      for (final form in OmrLayoutProfile.allCustomForms) {
        for (var opts = 2; opts <= 6; opts++) {
          final maxFit = OmrLayoutProfile.maxFitItems(
            form: form,
            optionsCount: opts,
          );
          if (maxFit < OmrLayoutProfile.minCustomItems) continue;

          for (final items in sampleCounts) {
            if (items > maxFit) continue;
            final fit = OmrLayoutProfile.tryCompute(
              itemCount: items,
              optionsCount: opts,
              form: form,
            );
            if (!fit.isOk) continue;
            final profile = fit.profile!;
            final grid = profile.grid;

            // Always column-major.
            expect(grid.questionPosition(1), (0, 0));
            if (grid.rows >= 2 && items >= 2) {
              expect(grid.questionPosition(2), (0, 1));
            }

            // If any scan-safe column count divides [items], packer must use one.
            var divisorFits = false;
            for (var columns = 1; columns <= 10; columns++) {
              if (items % columns != 0) continue;
              final rows = items ~/ columns;
              final explicit = OmrLayoutProfile.tryComputeExplicitGrid(
                columns: columns,
                rows: rows,
                optionsCount: opts,
                form: form,
              );
              if (explicit.isOk) {
                divisorFits = true;
                break;
              }
            }
            if (divisorFits) {
              expect(
                items % grid.columns,
                0,
                reason: '${form.id} · $items Q · $opts opts should pack evenly',
              );
              expect(grid.columns * grid.rows, items);
            }
          }
        }
      }
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

    test('suggestLayouts offers full portrait only (no half, quarter, or landscape)',
        () {
      final suggestions = OmrLayoutProfile.suggestLayouts(
        itemCount: 10,
        optionsCount: 4,
      );
      expect(suggestions, isNotEmpty);
      expect(
        suggestions.every((s) => s.form.id == 'lengthwise_full'),
        isTrue,
      );
      expect(
        suggestions.any((s) => s.form.id == 'lengthwise_half'),
        isFalse,
      );
      expect(
        suggestions.any((s) => s.form.id == 'lengthwise_quarter'),
        isFalse,
      );
      expect(
        suggestions.any((s) => s.form.orientation == OmrLayoutOrientation.crosswise),
        isFalse,
      );
      expect(
        OmrLayoutProfile.teacherSelectableCustomForms,
        hasLength(1),
      );
      expect(
        OmrLayoutProfile.teacherSelectableCustomForms.single.id,
        'lengthwise_full',
      );
      final blocked = OmrLayoutProfile.blockedLayouts(
        itemCount: 10,
        optionsCount: 4,
      );
      expect(
        blocked.any((b) => b.form.pageFill != OmrLayoutPageFill.full),
        isFalse,
      );
    });

    test('suggestExplicitGridLayouts keeps A–F and even capacity', () {
      final suggestions = OmrLayoutProfile.suggestExplicitGridLayouts(
        columns: 2,
        rows: 13,
        optionsCount: 6,
      );
      expect(suggestions, isNotEmpty);
      expect(suggestions.first.profile.itemCount, 26);
      expect(suggestions.first.profile.optionLabels, ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(
        suggestions.every(
          (s) => s.form.orientation == OmrLayoutOrientation.lengthwise,
        ),
        isTrue,
      );
      final blocked = OmrLayoutProfile.blockedExplicitGridLayouts(
        columns: 2,
        rows: 13,
        optionsCount: 6,
      );
      expect(
        blocked.any((b) => suggestions.any((s) => s.form.id == b.form.id)),
        isFalse,
      );
    });

    test('availableGridSizes lists only even scan-safe splits', () {
      final grids = OmrLayoutProfile.availableGridSizes(
        itemCount: 20,
        optionsCount: 5,
      );
      expect(grids, isNotEmpty);
      expect(grids.every((g) => g.columns * g.rows == 20), isTrue);
      expect(grids.any((g) => g.columns == 5 && g.rows == 4), isTrue);
      expect(grids.any((g) => g.columns == 4 && g.rows == 5), isTrue);
      // Non-divisor grids must not appear.
      expect(grids.any((g) => g.columns == 3), isFalse);
      // Wide pancake packs (6+ columns) are never offered.
      expect(
        grids.every((g) => g.columns <= OmrLayoutProfile.maxColumnsLengthwise),
        isTrue,
      );
    });

    test('200-question A–D uneven 7×29 grid prints (empty last-column slots OK)',
        () {
      const form = OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
      final auto = OmrLayoutProfile.tryCompute(
        itemCount: 200,
        optionsCount: 4,
        form: form,
      );
      expect(auto.isOk, isTrue);
      expect(auto.profile!.grid.columns, 7);
      expect(auto.profile!.grid.rows, 29);

      // Capacity 203 > 200 — must still accept with itemCount=200.
      final explicit = OmrLayoutProfile.tryComputeExplicitGrid(
        columns: 7,
        rows: 29,
        optionsCount: 4,
        form: form,
        itemCount: 200,
      );
      expect(explicit.isOk, isTrue, reason: explicit.errorMessage);
      expect(explicit.profile!.itemCount, 200);

      final withoutItemCount = OmrLayoutProfile.tryComputeExplicitGrid(
        columns: 7,
        rows: 29,
        optionsCount: 4,
        form: form,
      );
      expect(withoutItemCount.isOk, isFalse);

      final tooManyOpts = OmrLayoutProfile.tryCompute(
        itemCount: 200,
        optionsCount: 6,
        form: form,
      );
      expect(tooManyOpts.isOk, isFalse);
      expect(tooManyOpts.errorMessage, contains('at most'));
    });

    test('50-question full sheet packs tall like standard (5×10), not wide', () {
      const form = OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 50,
        optionsCount: 4,
        form: form,
      );
      expect(fit.isOk, isTrue);
      expect(fit.profile!.grid.columns, 5);
      expect(fit.profile!.grid.rows, 10);

      final wide = OmrLayoutProfile.tryComputeExplicitGrid(
        columns: 8,
        rows: 7,
        optionsCount: 4,
        form: form,
      );
      expect(wide.isOk, isFalse);
      expect(wide.errorMessage, contains('too wide'));
    });

    test('every full-page Automatic pack from 5–200 stays vertically balanced', () {
      const form = OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
      for (var opts = 2; opts <= 6; opts++) {
        final maxFit = OmrLayoutProfile.maxFitItems(form: form, optionsCount: opts);
        for (var q = OmrLayoutProfile.minCustomItems; q <= maxFit; q++) {
          final fit = OmrLayoutProfile.tryCompute(
            itemCount: q,
            optionsCount: opts,
            form: form,
          );
          expect(fit.isOk, isTrue, reason: 'q=$q opts=$opts should pack');
          final cols = fit.profile!.grid.columns;
          final rows = fit.profile!.grid.rows;
          final maxCols =
              OmrLayoutProfile.maxColumnsFor(form, itemCount: q);
          expect(cols, lessThanOrEqualTo(maxCols),
              reason: 'q=$q opts=$opts cols=$cols');
          expect(cols, lessThanOrEqualTo(OmrLayoutProfile.absoluteMaxColumnsLengthwise));
          if (q >= 18) {
            // Prefer tall packs; 5×5 for Q=25 is acceptable (no taller even split).
            expect(rows, greaterThanOrEqualTo(5),
                reason: 'q=$q opts=$opts too shallow (${cols}x$rows)');
          }
          // Never a wide shallow strip like the old 8×7.
          expect(cols < 6 || rows >= 10, isTrue,
              reason: 'q=$q opts=$opts pancake ${cols}x$rows');
          // Through preferred capacity, stay within 5 columns.
          if (q <= OmrLayoutProfile.maxColumnsLengthwise *
              OmrLayoutProfile.maxRowsPerColumn) {
            expect(cols, lessThanOrEqualTo(OmrLayoutProfile.maxColumnsLengthwise),
                reason: 'q=$q should stay ≤5 cols');
          }
        }
        if (maxFit < OmrLayoutProfile.maxCustomItems) {
          final over = OmrLayoutProfile.tryCompute(
            itemCount: maxFit + 1,
            optionsCount: opts,
            form: form,
          );
          expect(over.isOk, isFalse, reason: 'opts=$opts over maxFit');
        }
      }
    });

    test('20 questions prefers 4×5 (taller) over shallow 5×4', () {
      const form = OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 20,
        optionsCount: 4,
        form: form,
      );
      expect(fit.isOk, isTrue);
      expect(fit.profile!.grid.columns, 4);
      expect(fit.profile!.grid.rows, 5);
    });

    test('small quizzes pack tall (not a single wide row)', () {
      const form = OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
      final five = OmrLayoutProfile.tryCompute(
        itemCount: 5,
        optionsCount: 4,
        form: form,
      );
      expect(five.isOk, isTrue);
      expect(five.profile!.grid.columns, lessThanOrEqualTo(2));
      expect(five.profile!.grid.rows, greaterThanOrEqualTo(3));
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
