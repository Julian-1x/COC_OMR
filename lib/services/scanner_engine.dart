import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omr_app/opencv_bridge.dart';

/// Pre-warms the native OMR scan engine so the scanner is ready immediately.
class ScannerEngine {
  static bool _ready = false;
  static Future<bool>? _warmUpInFlight;
  static String? _lastError;

  static bool get isReady => _ready;

  static String? get lastError => _lastError;

  static bool get _isNativeMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Sync cached ready flag with native (call after timeouts or on resume).
  /// Fast — does not block on load.
  static Future<bool> checkReady() async {
    if (!_isNativeMobile) {
      return false;
    }
    try {
      _ready = await OpenCVBridge.isReady();
      if (_ready) {
        _lastError = null;
      }
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Last native init error (empty if none / ready).
  static Future<String?> fetchInitError() async {
    if (!_isNativeMobile) {
      return null;
    }
    try {
      final info = await OpenCVBridge.getInitStatus();
      final err = (info?['error'] as String?)?.trim();
      _lastError = (err == null || err.isEmpty) ? null : err;
      final ready = info?['ready'] == true;
      if (ready) {
        _ready = true;
        _lastError = null;
      }
      return _lastError;
    } catch (_) {
      return _lastError;
    }
  }

  /// Load OpenCV at app start. Safe to call multiple times — shares one in-flight load.
  static Future<bool> warmUp({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    if (!_isNativeMobile) {
      return false;
    }

    if (_ready) {
      return true;
    }

    final inFlight = _warmUpInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _warmUpImpl(timeout);
    _warmUpInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_warmUpInFlight, future)) {
        _warmUpInFlight = null;
      }
    }
  }

  static Future<bool> _warmUpImpl(Duration timeout) async {
    if (_ready || await OpenCVBridge.isReady()) {
      _ready = true;
      _lastError = null;
      return true;
    }

    _ready = await OpenCVBridge.ensureReady(timeout: timeout);
    if (_ready) {
      _lastError = null;
      return true;
    }

    _ready = await OpenCVBridge.isReady();
    if (!_ready) {
      await fetchInitError();
    } else {
      _lastError = null;
    }
    return _ready;
  }

  /// Teacher Retry — force a fresh native load cycle.
  static Future<bool> retryLoad({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!_isNativeMobile) {
      return false;
    }
    invalidate();
    try {
      _ready = await OpenCVBridge.retryInit().timeout(timeout);
    } catch (e) {
      debugPrint('ScannerEngine.retryLoad error: $e');
      _ready = false;
    }
    if (_ready) {
      _lastError = null;
    } else {
      await fetchInitError();
    }
    return _ready;
  }

  /// Keeps loading until native reports ready or [shouldContinue] returns false.
  static Future<bool> loadUntilReady({
    bool Function()? shouldContinue,
  }) async {
    if (!_isNativeMobile) {
      return false;
    }

    while (shouldContinue?.call() ?? true) {
      if (_ready || await OpenCVBridge.isReady()) {
        _ready = true;
        _lastError = null;
        return true;
      }

      _ready = await OpenCVBridge.ensureReady(
        timeout: const Duration(seconds: 90),
      );
      if (_ready) {
        _lastError = null;
        return true;
      }

      _ready = await OpenCVBridge.isReady();
      if (_ready) {
        _lastError = null;
        return true;
      }

      await fetchInitError();

      if (!(shouldContinue?.call() ?? true)) {
        break;
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return _ready;
  }

  /// Clears cached state so the next warmUp re-checks native.
  static void invalidate() {
    _ready = false;
  }
}
