/// Lighting guidance for the OMR scanner (teacher-facing).
enum ScanLightingLevel {
  good,
  dim,
  tooDark,
}

class ScanLightingGuard {
  const ScanLightingGuard._();

  /// Normalized brightness from native analyzeImageQuality (0–1).
  static const double hardBlockBrightness = 0.18;

  /// Soft warning threshold — capture allowed but quality may suffer.
  static const double dimWarningBrightness = 0.30;

  static ScanLightingLevel levelFromNormalizedBrightness(double brightness) {
    if (brightness < hardBlockBrightness) {
      return ScanLightingLevel.tooDark;
    }
    if (brightness < dimWarningBrightness) {
      return ScanLightingLevel.dim;
    }
    return ScanLightingLevel.good;
  }

  static String? overlayHint(
    ScanLightingLevel level, {
    required bool torchOn,
  }) {
    switch (level) {
      case ScanLightingLevel.tooDark:
        return torchOn
            ? 'Still too dark — move to a brighter spot'
            : 'Too dark — tap Light or add a lamp';
      case ScanLightingLevel.dim:
        return torchOn
            ? 'Dim light — hold steady'
            : 'Dim light — tap Light for better scanning';
      case ScanLightingLevel.good:
        return null;
    }
  }

  static String hardBlockMessage({required bool torchOn}) {
    if (torchOn) {
      return 'Too dark to scan safely — turn on a light or move to a brighter area.';
    }
    return 'Too dark to scan safely — turn on a light or use the flashlight '
        '(tap Light above the camera).';
  }
}
