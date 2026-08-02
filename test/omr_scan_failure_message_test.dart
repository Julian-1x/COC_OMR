import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/utils/omr_scan_failure_message.dart';

void main() {
  group('OmrScanFailureMessage', () {
    test('maps no sheet from failureReason', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {'failureReason': 'NO_SHEET'},
      );
      expect(msg.title, 'No answer sheet detected');
      expect(msg.message, contains('OMR answer sheet'));
    });

    test('maps timing marks with score details', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {
          'failureReason': 'TIMING_MARKS',
          'timingMarkScore': 0.25,
          'timingMarksFound': 12,
          'timingMarksExpected': 48,
        },
      );
      expect(msg.title, 'Timing marks not clear');
      expect(msg.message, contains('25%'));
      expect(msg.message, contains('12 of 48'));
    });

    test('infers no sheet when corner detection finds nothing', () {
      final msg = OmrScanFailureMessage.from(
        errorMessage: 'Could not detect all 4 corner markers.',
        debugInfo: const {
          'cornerDetectionSucceededVia': 'none',
          'balancedCandidates': 0,
        },
      );
      expect(msg.title, 'No answer sheet detected');
    });

    test('maps engine not ready from platform error', () {
      final msg = OmrScanFailureMessage.from(
        errorMessage: 'OpenCV is not initialized yet',
        debugInfo: const {'platformError': 'OPENCV_NOT_READY'},
      );
      expect(msg.title, 'Could not read answer sheet');
    });

    test('maps grid misalignment from failureReason', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {'failureReason': 'GRID_MISALIGNED'},
      );
      expect(msg.title, 'Answer bubbles not readable');
    });

    test('OMR ID failure uses short teacher-facing copy', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {
          'failureReason': 'OMR_ID',
          'answersDetected': 5,
          'blankAnswersCount': 45,
        },
      );
      expect(msg.title, 'Could not read OMR ID');
      expect(msg.message, 'The 4-digit student ID bubbles were not clear enough.');
      expect(msg.helpTip.toLowerCase(), contains('type'));
    });

    test('OMR ID not filled uses distinct title', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {
          'failureReason': 'OMR_ID',
          'omrIdNotFilled': true,
        },
      );
      expect(msg.title, 'OMR ID not filled');
    });

    test('maps foreign sheet failure', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {'failureReason': 'FOREIGN_SHEET'},
      );
      expect(msg.title, 'Not a COC answer sheet');
      expect(msg.message.toLowerCase(), contains('other'));
    });

    test('maps wrong section failure', () {
      final msg = OmrScanFailureMessage.from(
        errorMessage:
            'This sheet is for BEED-II EWS, but you are grading BSIT-1A.',
        debugInfo: const {'failureReason': 'WRONG_SECTION'},
      );
      expect(msg.title, 'Wrong section');
      expect(msg.message, contains('BEED-II EWS'));
    });

    test('maps wrong subject failure', () {
      final msg = OmrScanFailureMessage.from(
        errorMessage:
            'This sheet is for HUM-232, but you opened the scanner for MATH-101.',
        debugInfo: const {'failureReason': 'WRONG_SUBJECT'},
      );
      expect(msg.title, 'Wrong subject');
      expect(msg.message, contains('HUM-232'));
    });

    test('maps wrong teacher failure', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {'failureReason': 'WRONG_TEACHER'},
      );
      expect(msg.title, 'Not your answer sheet');
      expect(msg.message.toLowerCase(), contains('another teacher'));
    });

    test('maps reprint required failure', () {
      final msg = OmrScanFailureMessage.from(
        debugInfo: const {'failureReason': 'REPRINT_REQUIRED'},
      );
      expect(msg.title, 'Reprint this answer sheet');
      expect(msg.helpTip.toLowerCase(), contains('print sheets'));
    });
  });
}
