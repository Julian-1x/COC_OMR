import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:omr_app/services/flutter_scanner_camera.dart';
import 'package:omr_app/services/native_scanner_camera.dart';
import 'package:omr_app/services/scanner_camera.dart';

/// Creates the scanner camera backend for the current platform.
class ScannerCameraFactory {
  /// Android: native CameraX only (no Flutter camera plugin fallback).
  /// iOS: Flutter camera plugin until a native AVFoundation backend exists.
  static Future<ScannerCamera> create({
    List<CameraDescription> cameras = const [],
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      final native = NativeScannerCamera();
      await native.initialize();
      debugPrint('Scanner camera: native Android CameraX');
      return native;
    }

    if (!kIsWeb && Platform.isIOS) {
      if (cameras.isEmpty) {
        throw StateError('No camera available on this device');
      }
      final flutter = FlutterScannerCamera(cameras: cameras);
      await flutter.initialize();
      debugPrint('Scanner camera: Flutter plugin (iOS)');
      return flutter;
    }

    throw UnsupportedError('In-app scanner requires Android or iOS');
  }
}
