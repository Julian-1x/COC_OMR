import 'dart:async';

import 'dart:io';

import 'dart:typed_data';



import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:omr_app/services/scanner_camera.dart';



/// Android CameraX backend — sharp preview matched to view pixels.

class NativeScannerCamera implements ScannerCamera {

  static const MethodChannel _channel =

      MethodChannel('edu.coc.omr/scanner_camera');

  static const String viewType = 'edu.coc.omr/scanner_camera';



  int? _viewId;

  double _previewAspectRatio = 3 / 4;

  bool _initialized = false;

  Offset _lastFocusPoint = const Offset(0.5, 0.55);



  /// Called when the platform view is bound and capture is ready.

  VoidCallback? onViewReady;



  /// Called when CameraX bind fails — UI should offer retry.

  void Function(String message)? onBindFailed;



  @override

  bool get isInitialized => _initialized;



  @override

  bool get isCaptureReady => _initialized && _viewId != null;



  @override

  double get previewAspectRatio => _previewAspectRatio;



  int? get viewId => _viewId;



  @override

  Future<void> initialize() async {

    if (!Platform.isAndroid) {

      throw UnsupportedError('Native scanner camera is Android-only');

    }

    final aspect = await _channel.invokeMethod<num>('getPreviewAspect');

    if (aspect != null && aspect > 0) {

      _previewAspectRatio = aspect.toDouble();

    }

    _initialized = true;

  }



  Future<void> onViewCreated(int viewId, Size viewSize) async {

    _viewId = viewId;

    try {

      final aspect = await _channel.invokeMethod<num>(

        'bindView',

        {

          'viewId': viewId,

          'width': viewSize.width.round(),

          'height': viewSize.height.round(),

        },

      );

      if (aspect != null && aspect > 0) {

        _previewAspectRatio = aspect.toDouble();

      }

      onViewReady?.call();

    } on PlatformException catch (error) {

      debugPrint('Native camera bind failed: ${error.code} ${error.message}');

      onBindFailed?.call(error.message ?? error.code);

      rethrow;

    }

  }



  @override

  Future<void> dispose() async {

    final viewId = _viewId;

    _viewId = null;

    _initialized = false;

    if (viewId != null) {

      try {

        await _channel.invokeMethod<void>('disposeView', {'viewId': viewId});

      } catch (error) {

        debugPrint('Native camera dispose failed: $error');

      }

    }

  }



  @override

  Future<void> configureForScanning() async {

    final viewId = _viewId;

    if (viewId == null) {

      return;

    }

    try {

      await _channel.invokeMethod<void>('configureForScanning', {

        'viewId': viewId,

      });

      await setFocusPoint(_lastFocusPoint);

    } catch (error) {

      debugPrint('Native camera configure failed: $error');

    }

  }



  @override

  Future<void> setFocusPoint(Offset normalizedPoint) async {

    final viewId = _viewId;

    if (viewId == null) {

      return;

    }

    _lastFocusPoint = normalizedPoint;

    try {

      await _channel.invokeMethod<void>('setFocusPoint', {

        'viewId': viewId,

        'x': normalizedPoint.dx,

        'y': normalizedPoint.dy,

      });

    } catch (error) {

      debugPrint('Native focus failed: $error');

    }

  }



  @override

  Future<void> prepareCaptureFocus(Duration settleDelay) async {

    await setFocusPoint(_lastFocusPoint);

    await Future<void>.delayed(settleDelay);

  }



  @override

  Future<Uint8List> capture() async {

    final viewId = _viewId;

    if (viewId == null) {

      throw StateError('Native camera view not ready');

    }

    final bytes = await _channel.invokeMethod<Uint8List>(

      'capture',

      {'viewId': viewId},

    );

    if (bytes == null || bytes.isEmpty) {

      throw StateError('Native capture returned empty image');

    }

    return bytes;

  }



  @override

  Widget buildPreview({

    required Size viewSize,

    required void Function(TapDownDetails details, Size viewSize) onTapDown,

  }) {

    return GestureDetector(

      onTapDown: (details) {

        final point = tapToNormalizedFocusCover(

          details.localPosition,

          viewSize,

          previewAspectRatio,

        );

        unawaited(setFocusPoint(point));

        onTapDown(details, viewSize);

      },

      child: ClipRRect(

        borderRadius: BorderRadius.circular(12),

        clipBehavior: Clip.hardEdge,

        child: SizedBox(

          width: viewSize.width,

          height: viewSize.height,

          child: AndroidView(

            viewType: viewType,

            layoutDirection: TextDirection.ltr,

            creationParams: <String, dynamic>{

              'width': viewSize.width.round(),

              'height': viewSize.height.round(),

            },

            creationParamsCodec: const StandardMessageCodec(),

            onPlatformViewCreated: (viewId) {

              unawaited(

                onViewCreated(viewId, viewSize).then((_) async {

                  await configureForScanning();

                }).catchError((Object error) {

                  debugPrint('Native preview setup failed: $error');

                }),

              );

            },

          ),

        ),

      ),

    );

  }

}


