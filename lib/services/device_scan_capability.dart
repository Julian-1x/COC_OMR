import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omr_app/opencv_bridge.dart';
import 'package:omr_app/services/device_scan_tier.dart';

/// App-wide scan capability, warmed at launch — not when the scanner opens.
class DeviceScanCapability {
  static DeviceScanTier _tier = DeviceScanTier.mid;
  static bool _warmed = false;
  static Future<void>? _warmInFlight;
  static int? heapClassMb;
  static int? captureWidth;
  static int? captureHeight;
  static int? decodeMaxDimension;
  static int? remainingMemoryMB;

  static DeviceScanTier get tier => _tier;

  static bool get isWarmed => _warmed;

  static bool get isConstrained => _tier.isConstrained;

  static bool get _isNativeMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Call from [main] so tier is known before PIN / dashboard / scanner.
  static Future<void> warmUp() async {
    if (!_isNativeMobile) {
      _warmed = true;
      return;
    }
    if (_warmed) {
      return;
    }
    final inFlight = _warmInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _warmUpImpl();
    _warmInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_warmInFlight, future)) {
        _warmInFlight = null;
      }
    }
  }

  static Future<void> _warmUpImpl() async {
    try {
      final deviceInfo = await OpenCVBridge.getDeviceInfo();
      if (deviceInfo != null) {
        _tier = DeviceScanTier.fromName(deviceInfo['scanTier'] as String?);
        heapClassMb = deviceInfo['heapClassMb'] as int?;
        captureWidth = deviceInfo['captureWidth'] as int?;
        captureHeight = deviceInfo['captureHeight'] as int?;
        decodeMaxDimension = deviceInfo['decodeMaxDimension'] as int?;
        remainingMemoryMB = (deviceInfo['remainingMemoryMB'] as int?) ??
            (deviceInfo['freeMemoryMB'] as int?);
        debugPrint(
          'DeviceScanCapability: tier=${_tier.name} '
          'heapClassMb=$heapClassMb '
          'capture=${captureWidth}x$captureHeight '
          'decodeMax=$decodeMaxDimension '
          'remaining=${remainingMemoryMB}MB',
        );
      }
    } catch (e) {
      debugPrint('DeviceScanCapability warmUp failed: $e');
    } finally {
      _warmed = true;
    }
  }
}
