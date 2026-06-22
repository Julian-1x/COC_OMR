import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/services/scanner_camera.dart';

/// Flutter `camera` plugin backend — fallback and iOS path.
class FlutterScannerCamera implements ScannerCamera {
  FlutterScannerCamera({required this.cameras});

  final List<CameraDescription> cameras;

  static const List<ResolutionPreset> resolutionFallbackChain = [
    ResolutionPreset.veryHigh,
    ResolutionPreset.high,
    ResolutionPreset.medium,
  ];

  CameraController? _controller;
  Offset _lastFocusPoint = const Offset(0.5, 0.55);

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
