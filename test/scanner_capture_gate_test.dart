import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/opencv_bridge.dart';

void main() {
  group('Scanner pre-capture gate', () {
    test('allows aligned readable sheets before perfect confidence', () {
      final detection = SheetDetectionResult(
        sheetDetected: true,
        isAligned: true,
        hasGoodLighting: true,
        confidence: 0.63,
      );

      expect(detection.isReadyForCapture, isTrue);
    });

    test('still blocks low confidence and bad lighting', () {
      final lowConfidence = SheetDetectionResult(
        sheetDetected: true,
        isAligned: true,
        hasGoodLighting: true,
        confidence: 0.61,
      );
      final badLighting = SheetDetectionResult(
        sheetDetected: true,
        isAligned: true,
        hasGoodLighting: false,
        confidence: 0.90,
      );

      expect(lowConfidence.isReadyForCapture, isFalse);
      expect(badLighting.isReadyForCapture, isFalse);
    });
  });
}
