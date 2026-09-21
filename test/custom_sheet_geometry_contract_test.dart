import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/scanner_session_layout.dart';

/// Professional scan-contract invariants for every teacher-selectable custom form.
void main() {
  group('Custom geometry scan contract', () {
    for (final form in OmrLayoutProfile.allCustomForms) {
      for (var opts = 2; opts <= 6; opts++) {
        test('${form.id} · $opts choices · max capacity is scan-safe', () {
          final maxFit = OmrLayoutProfile.maxFitItems(
            form: form,
            optionsCount: opts,
          );
          if (maxFit < OmrLayoutProfile.minCustomItems) {
            // Honest: this form+choice combo is too tight — nothing to pack.
            return;
          }

          final fit = OmrLayoutProfile.tryCompute(
            itemCount: maxFit,
            optionsCount: opts,
            form: form,
          );
          expect(fit.isOk, isTrue, reason: fit.errorMessage);
          final profile = fit.profile!;
          _assertFullContract(profile);
        });
      }
    }

    test('saved custom grid that no longer fits fails closed (no substitute)',
        () {
      final subject = Subject(
        id: 'SUB-BAD-GRID',
        name: 'Broken save',
        answerKey: {for (int i = 1; i <= 80; i++) i: 'A'},
        totalQuestions: 80,
        useCustomLayout: true,
        optionsCount: 6,
        layoutShape: 'lengthwise_quarter',
        customGridColumns: 8,
        customGridRows: 10,
      );
      expect(subject.scannableCustomLayoutProfile, isNull);
      expect(
        ScannerSessionLayout.examReadyScanErrorForSubject(subject),
        isNotNull,
      );
      expect(
        () => ScannerSessionLayout.fromSubject(subject),
        throwsA(isA<StateError>()),
      );
    });

    test('session native map carries complete custom geometry keys', () {
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 20,
        optionsCount: 5,
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.half,
        ),
      );
      expect(fit.isOk, isTrue);
      final subject = Subject(
        id: 'SUB-HALF-KEYS',
        name: 'Half keys',
        answerKey: {for (int i = 1; i <= 20; i++) i: 'A'},
        totalQuestions: 20,
        useCustomLayout: true,
        optionsCount: 5,
        layoutShape: 'lengthwise_half',
        customGridColumns: fit.profile!.grid.columns,
        customGridRows: fit.profile!.grid.rows,
      );
      final native = ScannerSessionLayout.fromSubject(subject).toNativeMap();
      const required = [
        'gridTop',
        'gridBottom',
        'colWidth',
        'bubbleSpacingX',
        'contentBlockWidth',
        'contentBlockHeight',
        'answerGridLeft',
        'answerColumnInset',
        'answerBubbleDiameter',
        'timingMarkStartX',
        'timingMarkEndY',
        'rowMarkX',
        'omrIdFirstColumnX',
        'calibrationY',
        'qrCodeSize',
        'subjectId',
        'useFrozenRegistrationMarks',
      ];
      for (final key in required) {
        expect(native.containsKey(key), isTrue, reason: 'missing $key');
        expect(native[key], isNotNull, reason: 'null $key');
      }
      expect(native['useFrozenRegistrationMarks'], isFalse);
      expect(native['isCustom'], isTrue);
      expect(native['subjectId'], 'SUB-HALF-KEYS');
    });

    test('Sample 15 A–E print centers match session native grid (3×5)', () {
      const form = OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      );
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: 15,
        optionsCount: 5,
        form: form,
      );
      expect(fit.isOk, isTrue);
      final profile = fit.profile!;
      expect(profile.grid.columns, 3);
      expect(profile.grid.rows, 5);
      expect(profile.grid.rowHeight, greaterThanOrEqualTo(40));
      expect(profile.grid.bubbleSpacingX, greaterThanOrEqualTo(14));

      final subject = Subject(
        id: 'SUB-15',
        name: 'Sample 15',
        answerKey: {for (int i = 1; i <= 15; i++) i: 'A'},
        totalQuestions: 15,
        useCustomLayout: true,
        optionsCount: 5,
        layoutShape: 'lengthwise_full',
        customGridColumns: profile.grid.columns,
        customGridRows: profile.grid.rows,
      );
      expect(ScannerSessionLayout.examReadyScanErrorForSubject(subject), isNull);
      final native = ScannerSessionLayout.fromSubject(subject).toNativeMap();
      expect(native['cols'], 3);
      expect(native['rows'], 5);
      expect(
        (native['gridTop'] as num).toDouble(),
        closeTo(profile.geometry.answerRowsTop, 0.01),
      );
      expect(
        (native['rowHeight'] as num).toDouble(),
        closeTo(profile.grid.rowHeight, 0.01),
      );
      expect(
        (native['bubbleSpacingX'] as num).toDouble(),
        closeTo(profile.grid.bubbleSpacingX, 0.01),
      );
      final lastX = profile.bubbleCenterX(2, 4);
      expect(lastX, lessThan(profile.geometry.answerGridRight));
      expect(lastX, greaterThan(profile.geometry.answerGridLeft));
    });
  });
}

void _assertFullContract(OmrLayoutProfile profile) {
  final g = profile.geometry;

  expect(profile.bubblesFitInsideColumns(), isTrue);
  expect(profile.hasAdequateTimingMarks(), isTrue);
  expect(
    profile.grid.rowHeight,
    greaterThanOrEqualTo(OmrLayoutProfile.scanMinRowHeight(g)),
  );
  expect(
    profile.grid.bubbleSpacingX,
    greaterThanOrEqualTo(
      OmrLayoutProfile.scanMinBubbleSpacing(profile.form, g),
    ),
  );

  // Outer bubble edge stays inside column (radius-aware).
  final opts = profile.optionsCount;
  for (var col = 0; col < profile.grid.columns; col++) {
    final left =
        profile.bubbleCenterX(col, 0) - g.answerBubbleDiameter / 2;
    final right = profile.bubbleCenterX(col, opts - 1) +
        g.answerBubbleDiameter / 2;
    final columnLeft = g.answerGridLeft + col * profile.grid.columnWidth;
    final columnRight = columnLeft + profile.grid.columnWidth;
    expect(left, greaterThanOrEqualTo(columnLeft - 0.05));
    expect(right, lessThanOrEqualTo(columnRight + 0.05));
  }

  // Vertical stack: header → OMR ID → answers → calibration inside block.
  expect(g.omrIdTop, greaterThanOrEqualTo(g.headerTop + g.headerHeight - 0.5));
  expect(g.omrIdBottom, lessThanOrEqualTo(g.answerGridTop + 0.05));
  // Full portrait matches proven 30–100 spacing (12pt with 11.5 bubbles).
  // Half/¼ keep a stricter clearance so scaled digits do not merge.
  final minOmrRow = profile.form.pageFill == OmrLayoutPageFill.full &&
          profile.form.orientation == OmrLayoutOrientation.lengthwise
      ? g.omrIdBubbleDiameter
      : g.omrIdBubbleDiameter + 3.0;
  expect(g.omrIdRowSpacing, greaterThanOrEqualTo(minOmrRow - 0.05));
  // Proven full-page calibration sits at y=810 (inside A4 printable area).
  // Half/¼ geometries keep a stricter content-bottom clearance.
  if (!(profile.form.pageFill == OmrLayoutPageFill.full &&
      profile.form.orientation == OmrLayoutOrientation.lengthwise)) {
    expect(
      g.calibrationY + g.calibrationBubbleSize / 2 + 4.0,
      lessThanOrEqualTo(g.contentBlockHeight - g.marginBottom + 0.5),
    );
  } else {
    expect(g.calibrationY, OmrPageConstants.calibrationY);
  }

  // Row marks clear timing-mark sample windows (half/¼). Full page uses
  // the frozen 30–100 mark X.
  if (!(profile.form.pageFill == OmrLayoutPageFill.full &&
      profile.form.orientation == OmrLayoutOrientation.lengthwise)) {
    final sampleHalf = g.rowMarkSize.clamp(3.0, 6.0);
    expect(
      g.rowMarkX,
      greaterThanOrEqualTo(
        g.timingMarkEdgeOffset + g.timingMarkSize + sampleHalf + 1.0 - 0.05,
      ),
    );
  } else {
    expect(g.rowMarkX, OmrRowMarks.markX);
  }

  // Column inset covers bubble radius.
  expect(g.answerColumnInset, greaterThanOrEqualTo(g.answerBubbleDiameter / 2));

  expect(g.qrCodeSize, greaterThanOrEqualTo(56.0));
  expect(g.answerBubbleDiameter, greaterThanOrEqualTo(8.0));
}
