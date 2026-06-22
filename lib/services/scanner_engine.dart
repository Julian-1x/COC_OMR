import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omr_app/opencv_bridge.dart';

/// Pre-warms the native OMR scan engine so the scanner is ready immediately.
class ScannerEngine {
  static bool _ready = false;

  static bool get isReady => _ready;

  /// Load OpenCV at app start (Android). Safe to call multiple times.
  static Future<bool> warmUp() async {
    if (_ready) {
      return true;
    }
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    _ready = await OpenCVBridge.ensureReady();
    return _ready;
  }
}
