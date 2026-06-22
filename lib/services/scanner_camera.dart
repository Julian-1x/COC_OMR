import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Abstraction over native Android CameraX (and iOS Flutter camera until native).
/// OMR pipeline only needs JPEG bytes from [capture].
abstract class ScannerCamera {
  bool get isInitialized;

  /// True when [capture] can run (native view may lag behind [isInitialized]).
  bool get isCaptureReady;

  /// Width / height of the live preview (for tap-to-focus mapping).
  double get previewAspectRatio;

  Future<void> initialize();

  Future<void> dispose();

  Future<void> configureForScanning();

  Future<void> setFocusPoint(Offset normalizedPoint);

  Future<void> prepareCaptureFocus(Duration settleDelay);

  Future<Uint8List> capture();

  /// Preview widget sized to [viewSize] (cover-fit inside caller's frame).
  Widget buildPreview({
    required Size viewSize,
    required void Function(TapDownDetails details, Size viewSize) onTapDown,
  });
}

/// Cover-fit tap mapping shared by Flutter and native preview layouts.
Offset tapToNormalizedFocusCover(
  Offset local,
  Size viewSize,
  double previewAspect,
) {
  if (previewAspect <= 0) {
    return Offset(
      (local.dx / viewSize.width).clamp(0.0, 1.0),
      (local.dy / viewSize.height).clamp(0.0, 1.0),
    );
  }

  final viewW = viewSize.width;
  final viewH = viewSize.height;
  final viewAspect = viewW / viewH;

  if (viewAspect > previewAspect) {
    final renderedH = viewW / previewAspect;
    final topCrop = (renderedH - viewH) / 2;
    return Offset(
      (local.dx / viewW).clamp(0.0, 1.0),
      ((local.dy + topCrop) / renderedH).clamp(0.0, 1.0),
    );
  }

  final renderedW = viewH * previewAspect;
  final leftCrop = (renderedW - viewW) / 2;
  return Offset(
    ((local.dx + leftCrop) / renderedW).clamp(0.0, 1.0),
    (local.dy / viewH).clamp(0.0, 1.0),
  );
}
