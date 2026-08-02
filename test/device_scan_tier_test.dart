import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/services/device_scan_tier.dart';

void main() {
  group('DeviceScanTier', () {
    test('fromName maps Android enum names', () {
      expect(DeviceScanTier.fromName('LOW'), DeviceScanTier.low);
      expect(DeviceScanTier.fromName('MID'), DeviceScanTier.mid);
      expect(DeviceScanTier.fromName('HIGH'), DeviceScanTier.high);
      expect(DeviceScanTier.fromName('VERY_HIGH'), DeviceScanTier.veryHigh);
      expect(DeviceScanTier.fromName(null), DeviceScanTier.mid);
      expect(DeviceScanTier.fromName('unknown'), DeviceScanTier.mid);
    });

    test('optimize ceilings rise with capability', () {
      expect(DeviceScanTier.low.dartOptimizeMaxDimension, 1600);
      expect(DeviceScanTier.mid.dartOptimizeMaxDimension, 1800);
      expect(DeviceScanTier.high.dartOptimizeMaxDimension, 2000);
      expect(DeviceScanTier.veryHigh.dartOptimizeMaxDimension, 2400);
      expect(
        DeviceScanTier.low.dartOptimizeMinBytes <
            DeviceScanTier.veryHigh.dartOptimizeMinBytes,
        isTrue,
      );
    });

    test('low and mid are constrained', () {
      expect(DeviceScanTier.low.isConstrained, isTrue);
      expect(DeviceScanTier.mid.isConstrained, isTrue);
      expect(DeviceScanTier.high.isConstrained, isFalse);
      expect(DeviceScanTier.veryHigh.isConstrained, isFalse);
    });
  });
}
