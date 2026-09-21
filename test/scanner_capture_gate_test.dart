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
      expect(detection.isReadyForAutoCapture, isFalse);
    });

    test('auto-capture requires higher confidence than manual gate', () {
      final borderline = SheetDetectionResult(
        sheetDetected: true,
        isAligned: true,
        hasGoodLighting: true,
        confidence: 0.74,
      );
      final ready = SheetDetectionResult(
        sheetDetected: true,
        isAligned: true,
        hasGoodLighting: true,
        confidence: 0.75,
      );

      expect(borderline.isReadyForCapture, isTrue);
      expect(borderline.isReadyForAutoCapture, isFalse);
      expect(ready.isReadyForAutoCapture, isTrue);
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
      expect(lowConfidence.isReadyForAutoCapture, isFalse);
      expect(badLighting.isReadyForCapture, isFalse);
      expect(badLighting.isReadyForAutoCapture, isFalse);
    });
  });
}
