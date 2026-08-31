import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/scanner_session_layout.dart';

/// Exhaustive scannability contract for every teacher-selectable custom sheet.
void main() {
  const forms = OmrLayoutProfile.allCustomForms;

  group('Custom sheet scannability matrix', () {
    for (final form in forms) {
      for (var options = 2; options <= 5; options++) {
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

    test('every count in range has at least one scannable form for 5 options', () {
      for (var count = OmrLayoutProfile.minCustomItems;
          count <= OmrLayoutProfile.maxCustomItems;
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
  expect(profile.grid.rowHeight, greaterThanOrEqualTo(OmrLayoutProfile.minRowHeight));
  expect(
    profile.grid.bubbleSpacingX,
    greaterThanOrEqualTo(OmrLayoutProfile.minBubbleSpacingX),
  );
  expect(profile.geometry.qrCodeSize, greaterThanOrEqualTo(56.0));
  expect(profile.geometry.answerBubbleDiameter, greaterThanOrEqualTo(8.0));
  expect(profile.geometry.omrIdBottom, lessThanOrEqualTo(profile.geometry.answerGridTop + 0.01));
  expect(profile.itemCount, greaterThanOrEqualTo(OmrLayoutProfile.minCustomItems));
  expect(profile.itemCount, lessThanOrEqualTo(OmrLayoutProfile.maxCustomItems));
}
