import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/utils/omr_scan_diagnostics.dart';

void main() {
  test('formats corner and alignment diagnostics for teachers', () {
    final lines = OmrScanDiagnostics.fromDebugInfo({
      'cornerDetectionSucceededVia': 'balanced',
      'timingMarkScore': 0.92,
      'timingMarksFound': 23,
      'timingMarksExpected': 25,
      'calibrationSuccess': true,
      'fillThreshold': 0.31,
      'layoutTemplate': '50',
      'layoutFromSession': true,
      'rejectAreaLow': 12,
      'rejectAreaHigh': 1,
      'rejectAspect': 3,
      'balancedCandidates': 6,
      'processingTimeMs': 840,
    }).lines;

    expect(lines, isNotEmpty);
    expect(lines.any((l) => l.contains('Corner detection')), isTrue);
    expect(lines.any((l) => l.contains('Alignment marks')), isTrue);
    expect(lines.any((l) => l.contains('Fill calibration')), isTrue);
    expect(lines.any((l) => l.contains('Corner filter rejects')), isTrue);
  });

  test('returns empty for null debug info', () {
    expect(OmrScanDiagnostics.fromDebugInfo(null).isEmpty, isTrue);
  });

  test('surfaces OMR ID column fills and blank answer counts', () {
    final lines = OmrScanDiagnostics.fromDebugInfo({
      'failureReason': 'OMR_ID',
      'omrIdColumn0': {
        'bestDigit': 0,
        'bestFill': 0.38,
        'status': 'ambiguous',
      },
      'omrIdColumn1': {
        'bestDigit': 0,
        'bestFill': 0.41,
        'status': 'ok',
      },
      'answersDetected': 5,
      'blankAnswersCount': 45,
    }).lines;

    expect(lines.any((l) => l.contains('OMR ID col 1')), isTrue);
    expect(lines.any((l) => l.contains('Blank (no shade): 45')), isTrue);
  });
}
