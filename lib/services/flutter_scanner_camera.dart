import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/services/device_scan_tier.dart';
import 'package:omr_app/services/scanner_camera.dart';

/// Flutter `camera` plugin backend — fallback and iOS path.
class FlutterScannerCamera implements ScannerCamera {
  FlutterScannerCamera({
    required this.cameras,
    this.scanTier = DeviceScanTier.mid,
  });

  final List<CameraDescription> cameras;
  final DeviceScanTier scanTier;

  /// Start high enough for accuracy when the device can handle it; never jump
  /// straight to max on constrained phones.
  List<ResolutionPreset> get resolutionFallbackChain => switch (scanTier) {
        DeviceScanTier.low => const [
          ResolutionPreset.medium,
          ResolutionPreset.low,
        ],
        DeviceScanTier.mid => const [
          ResolutionPreset.high,
          ResolutionPreset.medium,
          ResolutionPreset.low,
        ],
        DeviceScanTier.high => const [
          ResolutionPreset.veryHigh,
          ResolutionPreset.high,
          ResolutionPreset.medium,
          ResolutionPreset.low,
        ],
        DeviceScanTier.veryHigh => const [
          ResolutionPreset.ultraHigh,
          ResolutionPreset.veryHigh,
          ResolutionPreset.high,
          ResolutionPreset.medium,
          ResolutionPreset.low,
        ],
      };

  CameraController? _controller;
  Offset _lastFocusPoint = const Offset(0.5, 0.55);
  bool _torchEnabled = false;

  @override
  bool get torchSupported {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || kIsWeb) {
      return false;
    }
    // The camera plugin does not expose supported flash modes on all versions;
    // rear cameras on phones used for scanning virtually always support torch.
    return cameras.isNotEmpty &&
        cameras.first.lensDirection == CameraLensDirection.back;
  }

  @override
  bool get torchEnabled => _torchEnabled;

  @override
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;

  @override
  bool get isCaptureReady => isInitialized;

  @override
  double get previewAspectRatio {
    final aspect = _controller?.value.aspectRatio ?? 0;
    return aspect > 0 ? aspect : 3 / 4;
  }

  CameraController? get controller => _controller;

  ImageFormatGroup _imageFormatGroup() {
    if (kIsWeb) {
      return ImageFormatGroup.bgra8888;
    }
    if (Platform.isAndroid) {
      return ImageFormatGroup.jpeg;
    }
    return ImageFormatGroup.bgra8888;
  }

  @override
  Future<void> initialize() async {
    if (cameras.isEmpty) {
      throw StateError('No camera available');
    }

    Object? lastError;
    for (final preset in resolutionFallbackChain) {
      try {
        await _controller?.dispose();
        _controller = CameraController(
          cameras.first,
          preset,
          enableAudio: false,
          imageFormatGroup: _imageFormatGroup(),
        );
        await _controller!.initialize();
        return;
      } catch (error) {
        lastError = error;
        debugPrint('Flutter camera init failed at $preset: $error');
      }
    }

    throw StateError('Camera could not start: $lastError');
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  @override
  Future<void> configureForScanning() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      final minZoom = await controller.getMinZoomLevel();
      await controller.setZoomLevel(minZoom);
    } catch (error) {
      debugPrint('Zoom reset failed: $error');
    }
    await setFocusPoint(_lastFocusPoint);
  }

  @override
  Future<void> setFocusPoint(Offset normalizedPoint) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    _lastFocusPoint = normalizedPoint;

    try {
      if (controller.value.focusPointSupported) {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(normalizedPoint);
      } else {
        await controller.setFocusMode(FocusMode.auto);
      }
      if (controller.value.exposurePointSupported) {
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setExposurePoint(normalizedPoint);
      } else {
        await controller.setExposureMode(ExposureMode.auto);
      }
    } catch (error) {
      debugPrint('Camera focus setup failed: $error');
    }
  }

  @override
  Future<void> prepareCaptureFocus(Duration settleDelay) async {
    await setFocusPoint(_lastFocusPoint);
    await Future<void>.delayed(settleDelay);
  }

  @override
  Future<Uint8List> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not initialized');
    }
    final file = await controller.takePicture();
    return File(file.path).readAsBytes();
  }

  @override
  Future<void> setTorchEnabled(bool enabled) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      _torchEnabled = enabled;
    } catch (error) {
      debugPrint('Flutter torch toggle failed: $error');
    }
  }

  @override
  Future<bool> toggleTorch() async {
    await setTorchEnabled(!_torchEnabled);
    return _torchEnabled;
  }

  @override
  Widget buildPreview({
    required Size viewSize,
    required void Function(TapDownDetails details, Size viewSize) onTapDown,
  }) {
    final controller = _controller!;
    final previewAspect = previewAspectRatio;

    final Widget preview;
    if (previewAspect <= 0) {
      preview = CameraPreview(controller);
    } else {
      preview = ClipRect(
        child: SizedBox(
          width: viewSize.width,
          height: viewSize.height,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: viewSize.width,
              height: viewSize.width / previewAspect,
              child: CameraPreview(controller),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTapDown: (details) => onTapDown(details, viewSize),
      child: preview,
    );
  }
}
