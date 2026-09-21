import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/scanner_session_layout.dart';

/// Exhaustive scannability contract for every teacher-selectable custom sheet.
void main() {
  const forms = OmrLayoutProfile.allCustomForms;

  group('Custom sheet scannability matrix', () {
    for (final form in forms) {
      for (var options = 2; options <= 6; options++) {
        test('${form.id} · $options choices · max capacity fits', () {
          final maxItems = OmrLayoutProfile.maxFitItems(
            form: form,
            optionsCount: options,
          );
          if (maxItems < OmrLayoutProfile.minCustomItems) {
            return;
          }

          final fit = OmrLayoutProfile.tryCompute(
            itemCount: maxItems,
            optionsCount: options,
            form: form,
          );
          expect(fit.isOk, isTrue, reason: fit.errorMessage);
          _assertScanFriendly(fit.profile!);
        });

        test('${form.id} · $options choices · blocked never overlaps suggestions',
            () {
          const probeCount = 15;
          final suggestions = OmrLayoutProfile.suggestLayouts(
            itemCount: probeCount,
            optionsCount: options,
          );
          final blocked = OmrLayoutProfile.blockedLayouts(
            itemCount: probeCount,
            optionsCount: options,
          );
          final suggestedIds = suggestions.map((s) => s.form.id).toSet();
          for (final option in blocked) {
            expect(suggestedIds, isNot(contains(option.form.id)));
          }
          for (final suggestion in suggestions) {
            _assertScanFriendly(suggestion.profile);
          }
        });
      }
    }

    test('counts in standard custom range stay scannable for 5 options', () {
      for (var count = OmrLayoutProfile.minCustomItems;
          count <= 100;
          count++) {
        final suggestions = OmrLayoutProfile.suggestLayouts(
          itemCount: count,
          optionsCount: 5,
        );
        expect(
          suggestions,
          isNotEmpty,
          reason: 'No scannable form for $count questions',
        );
      }
    });

    test('high counts that cannot fit are blocked instead of forced', () {
      for (var count = 101; count <= OmrLayoutProfile.maxCustomItems; count++) {
        final suggestions = OmrLayoutProfile.suggestLayouts(
          itemCount: count,
          optionsCount: 5,
        );
        if (suggestions.isNotEmpty) {
          for (final suggestion in suggestions) {
            _assertScanFriendly(suggestion.profile);
          }
          continue;
        }
        final blocked = OmrLayoutProfile.blockedLayouts(
          itemCount: count,
          optionsCount: 5,
        );
        expect(
          blocked,
          isNotEmpty,
          reason: 'Expected an explicit block reason for $count questions',
        );
      }
    });

    test('full-page custom capacity is honest and scan-safe through maxFit', () {
      for (final opts in [2, 3, 4, 5, 6]) {
        final maxFit = OmrLayoutProfile.maxFitItems(
          form: const OmrLayoutForm(
            orientation: OmrLayoutOrientation.lengthwise,
            pageFill: OmrLayoutPageFill.full,
          ),
          optionsCount: opts,
        );
        expect(maxFit, greaterThanOrEqualTo(OmrLayoutProfile.minCustomItems));
        expect(maxFit, lessThanOrEqualTo(OmrLayoutProfile.maxCustomItems));

        final atCap = OmrLayoutProfile.suggestLayouts(
          itemCount: maxFit,
          optionsCount: opts,
        );
        expect(atCap, isNotEmpty, reason: 'opts=$opts maxFit=$maxFit');
        for (final suggestion in atCap) {
          _assertScanFriendly(suggestion.profile);
          expect(
            suggestion.profile.grid.rows,
            lessThanOrEqualTo(OmrLayoutProfile.maxRowsPerColumn),
          );
          expect(
            suggestion.profile.grid.rowHeight,
            greaterThanOrEqualTo(
              suggestion.profile.geometry.answerBubbleDiameter +
                  OmrLayoutProfile.minBubbleVerticalClearance,
            ),
          );
        }

        if (maxFit < OmrLayoutProfile.maxCustomItems) {
          final over = OmrLayoutProfile.suggestLayouts(
            itemCount: maxFit + 1,
            optionsCount: opts,
          );
          expect(
            over.every((s) => s.form.id != 'lengthwise_full') || over.isEmpty,
            isTrue,
            reason: 'opts=$opts must not offer unsafe full-page over maxFit',
          );
        }
      }
    });

    test('explicit saved grid round-trips through exam-ready gate', () {
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 15,
        optionsCount: 4,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.full,
        ),
      );
      expect(fit.isOk, isTrue);

      final subject = Subject(
        name: 'Quiz',
        answerKey: const {},
        totalQuestions: 15,
        useCustomLayout: true,
        optionsCount: 4,
        layoutShape: 'lengthwise_full',
        customGridColumns: fit.profile!.grid.columns,
        customGridRows: fit.profile!.grid.rows,
      );

      expect(ScannerSessionLayout.examReadyScanErrorForSubject(subject), isNull);

      final session = ScannerSessionLayout.fromSubject(subject);
      final native = session.toNativeMap();
      expect(native['qrCodeX'], isNotNull);
      expect(native['qrCodeY'], isNotNull);
      expect(native['qrCodeSize'], greaterThanOrEqualTo(56.0));
      expect(native['answerBubbleDiameter'], greaterThanOrEqualTo(8.0));
      expect(native['isCustom'], isTrue);
      expect(native['cols'], fit.profile!.grid.columns);
      expect(native['rows'], fit.profile!.grid.rows);
    });

    test('custom subject without grid is blocked before scan', () {
      final subject = Subject(
        name: 'Quiz',
        answerKey: {},
        totalQuestions: 15,
        useCustomLayout: true,
        optionsCount: 5,
        layoutShape: 'lengthwise_half',
      );
      expect(
        ScannerSessionLayout.examReadyScanErrorForSubject(subject),
        isNotNull,
      );
    });
  });
}

void _assertScanFriendly(OmrLayoutProfile profile) {
  expect(
    profile.grid.rowHeight,
    greaterThanOrEqualTo(OmrLayoutProfile.scanMinRowHeight(profile.geometry)),
  );
  expect(
    profile.grid.bubbleSpacingX,
    greaterThanOrEqualTo(
      OmrLayoutProfile.scanMinBubbleSpacing(profile.form, profile.geometry),
    ),
  );
  expect(profile.geometry.qrCodeSize, greaterThanOrEqualTo(56.0));
  expect(profile.geometry.answerBubbleDiameter, greaterThanOrEqualTo(8.0));
  expect(profile.geometry.omrIdBottom, lessThanOrEqualTo(profile.geometry.answerGridTop + 0.01));
  // Full portrait uses proven 30–100 row-mark X; half/¼ keep the stricter clearance.
  if (!(profile.form.pageFill == OmrLayoutPageFill.full &&
      profile.form.orientation == OmrLayoutOrientation.lengthwise)) {
    final sampleHalf = profile.geometry.rowMarkSize.clamp(3.0, 6.0);
    expect(
      profile.geometry.rowMarkX,
      greaterThanOrEqualTo(
        profile.geometry.timingMarkEdgeOffset +
            profile.geometry.timingMarkSize +
            sampleHalf +
            1.0 -
            0.01,
      ),
    );
  }
  expect(profile.bubblesFitInsideColumns(), isTrue);
  expect(profile.hasAdequateTimingMarks(), isTrue);
  final minOmrRow = profile.form.pageFill == OmrLayoutPageFill.full &&
          profile.form.orientation == OmrLayoutOrientation.lengthwise
      ? profile.geometry.omrIdBubbleDiameter
      : profile.geometry.omrIdBubbleDiameter + 3.0;
  expect(
    profile.geometry.omrIdRowSpacing,
    greaterThanOrEqualTo(minOmrRow - 0.01),
  );
  if (!(profile.form.pageFill == OmrLayoutPageFill.full &&
      profile.form.orientation == OmrLayoutOrientation.lengthwise)) {
    expect(
      profile.geometry.calibrationY +
          profile.geometry.calibrationBubbleSize / 2 +
          4.0,
      lessThanOrEqualTo(
        profile.geometry.contentBlockHeight -
            profile.geometry.marginBottom +
            0.5,
      ),
    );
  }
  expect(profile.itemCount, greaterThanOrEqualTo(OmrLayoutProfile.minCustomItems));
  expect(profile.itemCount, lessThanOrEqualTo(OmrLayoutProfile.maxCustomItems));
}
