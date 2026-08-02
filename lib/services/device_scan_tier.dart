/// Device scan performance tier — mirrors Android [DeviceScanTier].
enum DeviceScanTier {
  low,
  mid,
  high,
  veryHigh;

  static DeviceScanTier fromName(String? name) {
    switch ((name ?? '').toUpperCase()) {
      case 'LOW':
        return DeviceScanTier.low;
      case 'MID':
        return DeviceScanTier.mid;
      case 'HIGH':
        return DeviceScanTier.high;
      case 'VERY_HIGH':
        return DeviceScanTier.veryHigh;
      default:
        return DeviceScanTier.mid;
    }
  }

  /// Longest edge for Dart-side JPEG pre-compress before native OpenCV.
  int get dartOptimizeMaxDimension => switch (this) {
        DeviceScanTier.low => 1600,
        DeviceScanTier.mid => 1800,
        DeviceScanTier.high => 2000,
        DeviceScanTier.veryHigh => 2400,
      };

  int get dartJpegQuality => switch (this) {
        DeviceScanTier.low => 82,
        DeviceScanTier.mid => 88,
        DeviceScanTier.high || DeviceScanTier.veryHigh => 90,
      };

  /// Trigger Dart compress earlier on constrained phones.
  int get dartOptimizeMinBytes => switch (this) {
        DeviceScanTier.low => 700 * 1024,
        DeviceScanTier.mid => 1200 * 1024,
        DeviceScanTier.high => 2 * 1024 * 1024,
        DeviceScanTier.veryHigh => 3 * 1024 * 1024,
      };

  bool get isConstrained =>
      this == DeviceScanTier.low || this == DeviceScanTier.mid;
}
