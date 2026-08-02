import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/utils/scan_lighting_guard.dart';

void main() {
  group('ScanLightingGuard', () {
    test('classifies brightness into good, dim, and too dark', () {
      expect(
        ScanLightingGuard.levelFromNormalizedBrightness(0.40),
        ScanLightingLevel.good,
      );
      expect(
        ScanLightingGuard.levelFromNormalizedBrightness(0.25),
        ScanLightingLevel.dim,
      );
      expect(
        ScanLightingGuard.levelFromNormalizedBrightness(0.10),
        ScanLightingLevel.tooDark,
      );
    });

    test('overlay hints mention the light button when torch is off', () {
      expect(
        ScanLightingGuard.overlayHint(
          ScanLightingLevel.dim,
          torchOn: false,
        ),
        contains('Light'),
      );
      expect(
        ScanLightingGuard.overlayHint(
          ScanLightingLevel.tooDark,
          torchOn: false,
        ),
        contains('Light'),
      );
    });

    test('hard block message mentions flashlight when torch is off', () {
      final message = ScanLightingGuard.hardBlockMessage(torchOn: false);
      expect(message.toLowerCase(), contains('flashlight'));
      expect(message, contains('Light'));
    });
  });
}
