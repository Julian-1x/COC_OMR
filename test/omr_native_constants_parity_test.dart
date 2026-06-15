import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:path/path.dart' as p;

/// Ensures Android [OmrProcessor.kt] and iOS [OmrNativeBridge.mm] use the same
/// layout numbers as [OmrPageConstants] (single source of truth in Dart).
///
/// Run: `flutter test test/omr_native_constants_parity_test.dart`
void main() {
  late String repoRoot;

  setUpAll(() {
    repoRoot = _findPackageRoot();
  });

  group('OMR native layout parity', () {
    test('Kotlin OmrProcessor matches OmrPageConstants', () {
      final ktPath = p.join(
        repoRoot,
        'android',
        'app',
        'src',
        'main',
        'kotlin',
        'edu',
        'coc',
        'omr',
        'OmrProcessor.kt',
      );
      final kt = File(ktPath);
      expect(kt.existsSync(), isTrue,
          reason: 'Expected OmrProcessor.kt at $ktPath (run from project root)');
      final kotlin = _parseKotlinConstVals(kt.readAsStringSync());

      for (final e in _kotlinExpectations.entries) {
        final parsed = kotlin[e.key];
        expect(
          parsed,
          isNotNull,
          reason: 'Missing `private const val ${e.key} = ...` in OmrProcessor.kt',
        );
        _expectNumClose(parsed!, e.value, e.key, 'Kotlin');
      }
    });

    test('iOS OmrNativeBridge matches OmrPageConstants', () {
      final mmPath = p.join(repoRoot, 'ios', 'Runner', 'OmrNativeBridge.mm');
      final mm = File(mmPath);
      expect(mm.existsSync(), isTrue,
          reason: 'Expected OmrNativeBridge.mm at $mmPath');
      final ios = _parseObjCppConstexprs(mm.readAsStringSync());

      for (final e in _iosExpectations.entries) {
        final parsed = ios[e.key];
        expect(
          parsed,
          isNotNull,
          reason: 'Missing `constexpr ... ${e.key} = ...` in OmrNativeBridge.mm',
        );
        _expectNumClose(parsed!, e.value, e.key, 'iOS');
      }
    });
  });
}

String _findPackageRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Could not find pubspec.yaml above ${Directory.current.path}');
    }
    dir = parent;
  }
}

/// `private const val NAME = 123` or `123.0` (optional trailing comment).
final _kotlinConst = RegExp(
  r'^\s*private const val ([A-Z0-9_]+)\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*(//.*)?$',
  multiLine: true,
);

Map<String, num> _parseKotlinConstVals(String source) {
  final out = <String, num>{};
  for (final m in _kotlinConst.allMatches(source)) {
    out[m.group(1)!] = num.parse(m.group(2)!);
  }
  return out;
}

/// `constexpr int kFoo = 595;` or `constexpr double kBar = 1.2;`
final _objCppConstexpr = RegExp(
  r'^\s*constexpr (?:int|double) ([a-zA-Z0-9_]+)\s*=\s*([0-9.]+)\s*;',
  multiLine: true,
);

Map<String, num> _parseObjCppConstexprs(String source) {
  final out = <String, num>{};
  for (final m in _objCppConstexpr.allMatches(source)) {
    out[m.group(1)!] = num.parse(m.group(2)!);
  }
  return out;
}

void _expectNumClose(num actual, num expected, String name, String platform) {
  if (expected is int && actual is int) {
    expect(actual, expected,
        reason: '$platform $name: expected $expected, got $actual');
    return;
  }
  final da = actual.toDouble();
  final de = expected.toDouble();
  expect(
    (da - de).abs(),
    lessThan(1e-6),
    reason: '$platform $name: expected $expected, got $actual',
  );
}

/// Maps [OmrProcessor.kt] constant names to values from [OmrPageConstants].
Map<String, num> get _kotlinExpectations => {
      'OUTPUT_WIDTH': OmrPageConstants.pageWidth,
      'OUTPUT_HEIGHT': OmrPageConstants.pageHeight,
      'CORNER_MARKER_SIZE': OmrPageConstants.cornerMarkerSize,
      'CORNER_OFFSET': OmrPageConstants.cornerMarkerOffset,
      'TIMING_MARK_SIZE': OmrPageConstants.timingMarkSize,
      'TIMING_MARK_SPACING': OmrPageConstants.timingMarkSpacing,
      'TIMING_MARK_EDGE_OFFSET': OmrPageConstants.timingMarkEdgeOffset,
      'MARGIN_LEFT': OmrPageConstants.marginLeft,
      'MARGIN_RIGHT': OmrPageConstants.marginRight,
      'MARGIN_TOP': OmrPageConstants.marginTop,
      'MARGIN_BOTTOM': OmrPageConstants.marginBottom,
      'BUBBLE_DIAMETER': OmrPageConstants.answerBubbleDiameter,
      'BUBBLE_BORDER': OmrPageConstants.answerBubbleBorder,
      'OMR_ID_COLUMNS': OmrPageConstants.omrIdColumns,
      'OMR_ID_ROWS': OmrPageConstants.omrIdRows,
      'OMR_ID_TOP': OmrPageConstants.omrIdTop,
      'OMR_ID_HEIGHT': OmrPageConstants.omrIdHeight,
      'OMR_ID_COLUMN_SPACING': OmrPageConstants.omrIdColumnSpacing,
      'OMR_ID_ROW_SPACING': OmrPageConstants.omrIdRowSpacing,
      'OMR_ID_FIRST_COLUMN_X': OmrPageConstants.omrIdFirstColumnX,
      'OMR_ID_FIRST_ROW_Y': OmrPageConstants.omrIdFirstRowY,
      'CALIBRATION_Y': OmrPageConstants.calibrationY,
      'CALIBRATION_FILLED_X': OmrPageConstants.calibrationFilledX,
      'CALIBRATION_EMPTY_X': OmrPageConstants.calibrationEmptyX,
      'CALIBRATION_BUBBLE_SIZE': OmrPageConstants.calibrationBubbleSize,
      'ANSWER_OPTIONS': OmrPageConstants.answerOptionsCount,
      // Native "answer grid" = bubble row band (not the full PDF block incl. A–E strip).
      'ANSWER_GRID_TOP': OmrPageConstants.answerRowsTop,
      'ANSWER_GRID_BOTTOM': OmrPageConstants.answerRowsBottom,
      'ANSWER_GRID_LEFT': OmrPageConstants.answerGridLeft,
      'ANSWER_GRID_RIGHT': OmrPageConstants.answerGridRight,
      'QUESTION_NUMBER_WIDTH': OmrPageConstants.questionNumberWidth,
      'ANSWER_COLUMN_INSET': OmrPageConstants.answerColumnInset,
      'ANSWER_NUMBER_BUBBLE_GAP': OmrPageConstants.answerNumberBubbleGap,
      'ROW_MARK_X': OmrRowMarks.markX,
      'ROW_MARK_SIZE': OmrRowMarks.markSize,
    };

/// Maps [OmrNativeBridge.mm] constexpr names to [OmrPageConstants] (or shared literals).
Map<String, num> get _iosExpectations => {
      'kOutputW': OmrPageConstants.pageWidth,
      'kOutputH': OmrPageConstants.pageHeight,
      'kCornerMarkerSize': OmrPageConstants.cornerMarkerSize,
      'kTimingMarkSize': OmrPageConstants.timingMarkSize,
      'kTimingSpacing': OmrPageConstants.timingMarkSpacing,
      'kTimingEdge': OmrPageConstants.timingMarkEdgeOffset,
      'kMarginTop': OmrPageConstants.marginTop,
      'kBubbleD': OmrPageConstants.answerBubbleDiameter,
      'kBubbleBorder': OmrPageConstants.answerBubbleBorder,
      'kOmrCols': OmrPageConstants.omrIdColumns,
      'kOmrRows': OmrPageConstants.omrIdRows,
      'kOmrIdTop': OmrPageConstants.omrIdTop,
      'kOmrColSpc': OmrPageConstants.omrIdColumnSpacing,
      'kOmrRowSpc': OmrPageConstants.omrIdRowSpacing,
      'kOmrFirstColX': OmrPageConstants.omrIdFirstColumnX,
      'kOmrFirstRowY': OmrPageConstants.omrIdFirstRowY,
      'kCalY': OmrPageConstants.calibrationY,
      'kCalFillX': OmrPageConstants.calibrationFilledX,
      'kCalEmptyX': OmrPageConstants.calibrationEmptyX,
      'kAnswerOpts': OmrPageConstants.answerOptionsCount,
      'kAnsGridTop': OmrPageConstants.answerRowsTop,
      'kAnsGridBot': OmrPageConstants.answerRowsBottom,
      'kAnsGridL': OmrPageConstants.answerGridLeft,
      'kAnsGridR': OmrPageConstants.answerGridRight,
      'kQNumW': OmrPageConstants.questionNumberWidth,
      'kAnsInset': OmrPageConstants.answerColumnInset,
      'kAnsGap': OmrPageConstants.answerNumberBubbleGap,
      'kRowMarkX': OmrRowMarks.markX,
      'kRowMarkSz': OmrRowMarks.markSize,
    };
