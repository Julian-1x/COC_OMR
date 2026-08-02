/// Teacher-facing scan failure title, message, and next-step tip.
class OmrScanFailureMessage {
  const OmrScanFailureMessage({
    required this.title,
    required this.message,
    required this.helpTip,
  });

  final String title;
  final String message;
  final String helpTip;

  static OmrScanFailureMessage from({
    String? errorMessage,
    Map<String, dynamic>? debugInfo,
  }) {
    final info = debugInfo ?? const <String, dynamic>{};
    final reason =
        info['failureReason']?.toString() ?? _inferReason(errorMessage, info);

    switch (reason) {
      case 'NO_SHEET':
        return const OmrScanFailureMessage(
          title: 'No answer sheet detected',
          message:
              'The camera did not see an OMR answer sheet. Point at a printed answer page — not the desk, keyboard, or background.',
          helpTip:
              'Center the full sheet in the frame. All four black corner squares must be visible before you capture.',
        );
      case 'CORNERS_INCOMPLETE':
        return const OmrScanFailureMessage(
          title: 'Corner markers not fully visible',
          message:
              'Part of the answer sheet was found, but not all four corner squares are visible in the photo.',
          helpTip:
              'Move back slightly so the entire page fits inside the green frame, including every corner square.',
        );
      case 'TIMING_MARKS':
        return _timingMarksMessage(info, errorMessage);
      case 'TOO_BLURRY':
        return const OmrScanFailureMessage(
          title: 'Photo too blurry',
          message:
              'The image was too blurry to read the sheet. The scan engine could not lock onto the corner markers.',
          helpTip:
              'Hold the phone steady, tap the paper to focus, wait a moment, then capture again.',
        );
      case 'TOO_DARK':
        return const OmrScanFailureMessage(
          title: 'Too dark to scan',
          message:
              'The photo is too dark to read the sheet safely.',
          helpTip:
              'Tap the Light button on the scan screen, or move to a brighter area with even light over the page.',
        );
      case 'TOO_BRIGHT':
        return const OmrScanFailureMessage(
          title: 'Too much glare',
          message:
              'Bright glare washed out the sheet. The scanner could not read the marks reliably.',
          helpTip:
              'Tilt the page slightly or move the phone so light does not reflect off the bubbles.',
        );
      case 'LOW_CONTRAST':
        return const OmrScanFailureMessage(
          title: 'Sheet hard to see',
          message:
              'The scanner could not separate the paper from the background. The page may be partly out of frame or unevenly lit.',
          helpTip:
              'Lay the sheet flat on a plain surface with even light across the whole page.',
        );
      case 'NOISY_IMAGE':
        return const OmrScanFailureMessage(
          title: 'Image quality too low',
          message:
              'The photo was too noisy or grainy to scan safely.',
          helpTip:
              'Clean the camera lens and scan again in brighter, even light.',
        );
      case 'FOREIGN_SHEET':
        return OmrScanFailureMessage(
          title: 'Not a COC answer sheet',
          message: _nonEmpty(errorMessage) ??
              'This page does not look like a sheet printed from COC OMR. Sheets from other apps (for example EvalBee) cannot be graded here.',
          helpTip:
              'Print answer sheets from this app: Prepare → Print Sheets. Then scan the COC sheet for this exam.',
        );
      case 'WRONG_SECTION':
        return OmrScanFailureMessage(
          title: 'Wrong section',
          message: _nonEmpty(errorMessage) ??
              'This answer sheet is for a different class section than the one you are grading.',
          helpTip:
              'Print sheets for the section assigned to this answer key, or open the scanner for the matching section.',
        );
      case 'WRONG_SUBJECT':
        return OmrScanFailureMessage(
          title: 'Wrong subject',
          message: _nonEmpty(errorMessage) ??
              'This answer sheet is for a different subject than the one you opened in the scanner.',
          helpTip:
              'Print sheets for this exam, or open the scanner from the correct answer key before scanning.',
        );
      case 'WRONG_TEACHER':
        return OmrScanFailureMessage(
          title: 'Not your answer sheet',
          message: _nonEmpty(errorMessage) ??
              'This answer sheet was printed from another teacher\'s account.',
          helpTip:
              'Look at the teacher name/email in the message. Only that teacher should scan this sheet. Print your own sheets from Prepare → Print Sheets.',
        );
      case 'REPRINT_REQUIRED':
        return OmrScanFailureMessage(
          title: 'Reprint this answer sheet',
          message: _nonEmpty(errorMessage) ??
              'This sheet was printed before the security update and cannot be scanned anymore.',
          helpTip:
              'Open Prepare → Print Sheets, print a fresh copy for this exam, then scan the new sheet.',
        );
      case 'QR_REQUIRED':
        return OmrScanFailureMessage(
          title: 'Sheet QR not readable',
          message: _nonEmpty(errorMessage) ??
              'The sheet QR code could not be read, so this scan cannot be saved.',
          helpTip:
              'Reprint from Prepare → Print Sheets if this is an old sheet. '
              'Otherwise center the QR square in the frame and scan again.',
        );
      case 'OMR_ID':
        final notFilled = info['omrIdNotFilled'] == true;
        return OmrScanFailureMessage(
          title: notFilled ? 'OMR ID not filled' : 'Could not read OMR ID',
          message: notFilled
              ? 'The 4-digit student ID area looks empty.'
              : 'The 4-digit student ID bubbles were not clear enough.',
          helpTip: notFilled
              ? 'Shade each OMR ID digit with a dark pencil, or type the ID below.'
              : 'Darken the OMR ID bubbles, or type the 4-digit ID below.',
        );
      case 'GRID_MISALIGNED':
        return OmrScanFailureMessage(
          title: 'Answer bubbles not readable',
          message: _nonEmpty(errorMessage) ??
              'The sheet was found, but the answer grid did not line up with the printed bubbles.',
          helpTip:
              'Print at 100% / Actual size, keep the page flat, and align timing marks with the green ticks before capturing.',
        );
      case 'ENGINE_NOT_READY':
        return const OmrScanFailureMessage(
          title: 'Could not read answer sheet',
          message: 'The sheet could not be read from this photo.',
          helpTip:
              'Center the full sheet in the frame with all four corner squares visible, then capture again.',
        );
      case 'BUSY':
        return const OmrScanFailureMessage(
          title: 'Scanner still busy',
          message:
              'The last photo is still being read. A second capture cannot start yet.',
          helpTip: 'Wait a moment for the current scan to finish, then try again.',
        );
      case 'OUT_OF_MEMORY':
        return const OmrScanFailureMessage(
          title: 'Phone ran out of memory',
          message:
              'This device did not have enough free memory to finish reading the sheet.',
          helpTip:
              'Close other apps, wait a few seconds, then open Scan again. The app already uses a smaller camera size on low-memory phones — you do not need to change a photo setting.',
        );
      case 'TIMEOUT':
        return const OmrScanFailureMessage(
          title: 'Scan took too long',
          message:
              'Reading the sheet timed out before it could finish.',
          helpTip:
              'Hold steady, tap the paper to focus, and try again with good lighting.',
        );
      default:
        return OmrScanFailureMessage(
          title: 'Could not read answer sheet',
          message: _nonEmpty(errorMessage) ??
              'The scanner could not read this photo. Check that a printed answer sheet fills the frame.',
          helpTip:
              'Print at 100% scale, fill bubbles with dark pencil, and keep all four corner squares visible.',
        );
    }
  }

  static OmrScanFailureMessage _timingMarksMessage(
    Map<String, dynamic> info,
    String? errorMessage,
  ) {
    final timing = _asDouble(info['timingMarkScore']);
    final found = info['timingMarksFound'];
    final expected = info['timingMarksExpected'];
    final pct = timing != null ? (timing * 100).round() : null;

    String message;
    if (pct != null && found is num && expected is num && expected > 0) {
      message =
          'The sheet was found, but the edge timing marks are only $pct% visible ($found of $expected). The page is likely crooked, cropped, or not printed at 100% scale.';
    } else if (_nonEmpty(errorMessage) != null) {
      message = errorMessage!;
    } else {
      message =
          'The sheet was found, but the edge timing marks are not clear enough. Align the page with the green tick guides.';
    }

    return OmrScanFailureMessage(
      title: 'Timing marks not clear',
      message: message,
      helpTip:
          'Lay the sheet flat and line up the edges with the green tick marks on screen. Re-print at 100% / Actual size if the sheet was scaled.',
    );
  }

  static String? _inferReason(
    String? errorMessage,
    Map<String, dynamic> info,
  ) {
    if (info['timeout'] == true) {
      return 'TIMEOUT';
    }
    final platformError = info['platformError']?.toString();
    if (platformError == 'OPENCV_NOT_READY') {
      return 'ENGINE_NOT_READY';
    }

    final explicit = info['failureReason']?.toString();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    final msg = (errorMessage ?? '').toLowerCase();
    if (msg.contains('no answer sheet') || msg.contains('no sheet detected')) {
      return 'NO_SHEET';
    }
    if (msg.contains('timing mark')) {
      return 'TIMING_MARKS';
    }
    if (msg.contains('corner marker') || msg.contains('corner square')) {
      final missing = info['missingQuadrants'];
      if (missing is List && missing.isNotEmpty) {
        return 'CORNERS_INCOMPLETE';
      }
      final candidates = info['balancedCandidates'];
      if (candidates is num && candidates < 2) {
        return 'NO_SHEET';
      }
      return 'CORNERS_INCOMPLETE';
    }
    if (msg.contains('answer bubbles could not be read') ||
        (msg.contains('grid') && msg.contains('line up'))) {
      return 'GRID_MISALIGNED';
    }
    if (msg.contains('not a coc') ||
        msg.contains('does not look like a coc') ||
        msg.contains('other omr') ||
        msg.contains('evalbee')) {
      return 'FOREIGN_SHEET';
    }
    if (msg.contains('wrong section') ||
        msg.contains('different section') ||
        msg.contains('not assigned to')) {
      return 'WRONG_SECTION';
    }
    if (msg.contains('wrong subject') ||
        msg.contains('different subject') ||
        msg.contains('opened the scanner for')) {
      return 'WRONG_SUBJECT';
    }
    if (msg.contains('security update') || msg.contains('reprint')) {
      return 'REPRINT_REQUIRED';
    }
    if (msg.contains('qr code could not be read') ||
        msg.contains('qr square')) {
      return 'QR_REQUIRED';
    }
    if (msg.contains('another teacher') ||
        msg.contains('not linked to your classes') ||
        msg.contains('not your answer sheet')) {
      return 'WRONG_TEACHER';
    }
    if (msg.contains('omr id')) return 'OMR_ID';
    if (msg.contains('blurry')) return 'TOO_BLURRY';
    if (msg.contains('too dark')) return 'TOO_DARK';
    if (msg.contains('overexposed') || msg.contains('too bright')) {
      return 'TOO_BRIGHT';
    }
    if (msg.contains('cannot distinguish') || msg.contains('contrast')) {
      return 'LOW_CONTRAST';
    }
    if (msg.contains('noisy')) return 'NOISY_IMAGE';
    if (msg.contains('opencv') || msg.contains('not ready')) {
      return 'ENGINE_NOT_READY';
    }

    final cornerVia = info['cornerDetectionSucceededVia']?.toString();
    if (cornerVia == 'none') {
      final candidates = info['balancedCandidates'];
      if (candidates is num && candidates < 2) {
        return 'NO_SHEET';
      }
      final missing = info['missingQuadrants'];
      if (missing is List && missing.isNotEmpty) {
        return 'CORNERS_INCOMPLETE';
      }
      return 'CORNERS_INCOMPLETE';
    }

    final timing = _asDouble(info['timingMarkScore']);
    if (timing != null && timing < 0.4 && info['cornersDetected'] == true) {
      return 'TIMING_MARKS';
    }

    return 'UNKNOWN';
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
