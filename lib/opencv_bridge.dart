import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class OmrScanResult {
  final bool success;
  final String? omrId;
  final Map<int, String> answers;
  final double confidence;
  final String? qrData;
  final String? errorMessage;
  final Map<String, dynamic> debugInfo;

  OmrScanResult({
    required this.success,
    this.omrId,
    required this.answers,
    required this.confidence,
    this.qrData,
    this.errorMessage,
    required this.debugInfo,
  });

  factory OmrScanResult.fromJson(Map<String, dynamic> json) {
    final answersJson = json['answers'] as Map<String, dynamic>? ?? {};
    final answers = <int, String>{};
    answersJson.forEach((key, value) {
      final questionNum = int.tryParse(key);
      if (questionNum != null && value is String) {
        answers[questionNum] = value;
      }
    });

    return OmrScanResult(
      success: json['success'] as bool? ?? false,
      omrId: json['omrId'] as String?,
      answers: answers,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      qrData: json['qrData'] as String?,
      errorMessage: json['errorMessage'] as String?,
      debugInfo: json['debugInfo'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  String toString() {
    return 'OmrScanResult(success: $success, omrId: $omrId, answers: ${answers.length}, confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
  }
}

class OpenCVBridge {
  static const MethodChannel _channel = MethodChannel('opencv');

  /// Process an image and return raw bytes (legacy method)
  static Future<Uint8List> process(Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod('process', bytes);
      if (result == null) {
        throw Exception('No result from native side');
      }
      // If result is a string (JSON), we got the new format
      if (result is String) {
        // Return empty bytes to indicate structured result is available
        return Uint8List(0);
      }
      return result as Uint8List;
    } on PlatformException catch (e) {
      debugPrint('OpenCV bridge error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Unexpected error: $e');
      rethrow;
    }
  }

  static const Duration _processOmrTimeout = Duration(seconds: 22);

  /// Process an image and return structured OMR scan result
  static Future<OmrScanResult> processOmr(Uint8List bytes,
      {int totalQuestions = 50}) async {
    try {
      final result = await _channel
          .invokeMethod('processWithConfig', {
            'image': bytes,
            'totalQuestions': totalQuestions,
          })
          .timeout(_processOmrTimeout);

      if (result == null) {
        return OmrScanResult(
          success: false,
          answers: {},
          confidence: 0.0,
          errorMessage: 'No result from native side',
          debugInfo: {},
        );
      }

      final json = jsonDecode(result as String) as Map<String, dynamic>;
      return OmrScanResult.fromJson(json);
    } on TimeoutException {
      debugPrint('OpenCV processOmr timed out');
      return OmrScanResult(
        success: false,
        answers: {},
        confidence: 0.0,
        errorMessage:
            'Scan took too long. Hold steady, tap the paper to focus, and try again.',
        debugInfo: {'timeout': true},
      );
    } on PlatformException catch (e) {
      debugPrint('OpenCV bridge error: ${e.message}');
      return OmrScanResult(
        success: false,
        answers: {},
        confidence: 0.0,
        errorMessage: e.message ?? 'Platform error',
        debugInfo: {'platformError': e.code},
      );
    } catch (e) {
      debugPrint('Unexpected error: $e');
      return OmrScanResult(
        success: false,
        answers: {},
        confidence: 0.0,
        errorMessage: e.toString(),
        debugInfo: {},
      );
    }
  }

  /// Check if OpenCV is available and initialized
  static Future<bool> checkAvailability() async {
    try {
      final result = await _channel.invokeMethod('ping');
      return result == 'pong';
    } catch (e) {
      return false;
    }
  }

  /// Check if OpenCV is fully ready for processing
  static Future<bool> isReady() async {
    try {
      final result = await _channel.invokeMethod('isReady');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Ask Android to restart OpenCV native load (after a failed start).
  static Future<void> retryInit() async {
    try {
      await _channel.invokeMethod('retryInit');
    } catch (e) {
      debugPrint('OpenCV retryInit error: $e');
    }
  }

  /// Block until native OpenCV is loaded (or timeout). Call at app start.
  static Future<bool> ensureReady({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (await isReady()) {
      return true;
    }
    try {
      final result = await _channel
          .invokeMethod<bool>('ensureReady')
          .timeout(timeout);
      return result == true;
    } catch (e) {
      debugPrint('OpenCV ensureReady error: $e');
      return isReady();
    }
  }

  /// Get device info for adaptive processing decisions
  static Future<Map<String, dynamic>?> getDeviceInfo() async {
    try {
      final result = await _channel.invokeMethod('getDeviceInfo');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } catch (e) {
      debugPrint('getDeviceInfo error: $e');
      return null;
    }
  }

  /// Quick sheet detection for continuous scanning mode
  /// Returns detection result without full OMR processing
  static Future<SheetDetectionResult> detectSheet(Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod('detectSheet', bytes);

      if (result == null) {
        return SheetDetectionResult.notDetected();
      }

      if (result is Map) {
        return SheetDetectionResult.fromJson(Map<String, dynamic>.from(result));
      }

      final json = jsonDecode(result as String) as Map<String, dynamic>;
      return SheetDetectionResult.fromJson(json);
    } on MissingPluginException {
      // Fall back to lightweight Dart heuristics when native support is unavailable.
      return _simulateSheetDetection(bytes);
    } catch (e) {
      debugPrint('Sheet detection error: $e');
      return _simulateSheetDetection(bytes);
    }
  }

  /// Lightweight Dart fallback when native detection isn't available.
  /// Uses brightness, contrast, and edge heuristics from the current frame.
  static SheetDetectionResult _simulateSheetDetection(Uint8List bytes) {
    try {
      // Decode image
      final image = img.decodeImage(bytes);
      if (image == null) {
        return SheetDetectionResult.notDetected(hint: 'Invalid image');
      }

      // Analyze image for sheet detection
      final analysis = _analyzeImageForSheet(image);

      return SheetDetectionResult(
        sheetDetected: analysis['sheetDetected'] as bool,
        isAligned: analysis['isAligned'] as bool,
        hasGoodLighting: analysis['hasGoodLighting'] as bool,
        confidence: analysis['confidence'] as double,
        hint: analysis['hint'] as String?,
      );
    } catch (e) {
      debugPrint('Sheet detection analysis error: $e');
      return SheetDetectionResult.notDetected(hint: 'Analysis failed');
    }
  }

  /// Analyze image to detect if a sheet is present and properly positioned
  static Map<String, dynamic> _analyzeImageForSheet(img.Image image) {
    // Sample pixels for analysis (faster than checking every pixel)
    final width = image.width;
    final height = image.height;
    final sampleStep =
        math.max(1, (width * height) ~/ 10000); // Sample ~10000 pixels

    double totalBrightness = 0;
    int brightPixels = 0;
    int sampleCount = 0;

    // Calculate brightness histogram and statistics
    final brightnessValues = <int>[];

    for (int y = 0; y < height; y += sampleStep) {
      for (int x = 0; x < width; x += sampleStep) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // Calculate luminance
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b).round();
        brightnessValues.add(brightness);
        totalBrightness += brightness;
        sampleCount++;

        if (brightness > 200) brightPixels++;
      }
    }

    if (sampleCount == 0) {
      return {
        'sheetDetected': false,
        'isAligned': false,
        'hasGoodLighting': false,
        'confidence': 0.0,
        'hint': 'Could not analyze image',
      };
    }

    final avgBrightness = totalBrightness / sampleCount;
    final brightRatio = brightPixels / sampleCount;

    // Calculate contrast (standard deviation of brightness)
    double variance = 0;
    for (final b in brightnessValues) {
      variance += (b - avgBrightness) * (b - avgBrightness);
    }
    final stdDev = math.sqrt(variance / sampleCount);
    final contrast = (stdDev / 128).clamp(0.0, 1.0); // Normalize to 0-1

    // Detect edges in center region (indicates document presence)
    final edgeStrength = _detectEdgesInRegion(
        image, width ~/ 4, height ~/ 4, width * 3 ~/ 4, height * 3 ~/ 4);

    // Determine if conditions are good
    final isBrightnessGood = avgBrightness > 80 && avgBrightness < 220;
    final isContrastGood = contrast > 0.15;
    final hasWhiteArea =
        brightRatio > 0.3; // Paper should have significant white area
    final hasDefinedEdges = edgeStrength > 0.1;

    // Determine detection result
    String? hint;
    bool sheetDetected = false;
    bool isAligned = false;
    bool hasGoodLighting = isBrightnessGood;
    double confidence = 0.0;

    if (avgBrightness < 60) {
      hint = 'Too dark - improve lighting';
      hasGoodLighting = false;
    } else if (avgBrightness > 230) {
      hint = 'Too bright - reduce glare';
      hasGoodLighting = false;
    } else if (!hasWhiteArea) {
      hint = 'Position sheet in frame';
    } else if (!hasDefinedEdges) {
      hint = 'Move closer to sheet';
    } else if (contrast < 0.1) {
      hint = 'Image too flat - adjust angle';
    } else {
      // Sheet likely detected
      sheetDetected = true;

      // Check alignment by analyzing edge distribution
      final alignment = _checkAlignment(image);
      isAligned = alignment > 0.6;

      if (!isAligned) {
        hint = 'Align sheet edges with frame';
      }

      // Calculate overall confidence
      confidence = ((hasWhiteArea ? 0.25 : 0.0) +
              (hasDefinedEdges ? 0.25 : 0.0) +
              (isContrastGood ? 0.2 : 0.0) +
              (isBrightnessGood ? 0.15 : 0.0) +
              (isAligned ? 0.15 : 0.0))
          .clamp(0.0, 1.0);
    }

    return {
      'sheetDetected': sheetDetected,
      'isAligned': isAligned,
      'hasGoodLighting': hasGoodLighting,
      'confidence': confidence,
      'hint': hint,
    };
  }

  /// Detect edge strength in a region using simple gradient calculation
  static double _detectEdgesInRegion(
      img.Image image, int x1, int y1, int x2, int y2) {
    double edgeSum = 0;
    int count = 0;
    final step = math.max(1, ((x2 - x1) * (y2 - y1)) ~/ 2000);

    for (int y = y1 + 1; y < y2 - 1; y += step) {
      for (int x = x1 + 1; x < x2 - 1; x += step) {
        // Simple Sobel-like gradient
        final pLeft = _getGrayscale(image.getPixel(x - 1, y));
        final pRight = _getGrayscale(image.getPixel(x + 1, y));
        final pUp = _getGrayscale(image.getPixel(x, y - 1));
        final pDown = _getGrayscale(image.getPixel(x, y + 1));

        final gx = (pRight - pLeft).abs();
        final gy = (pDown - pUp).abs();
        final gradient = math.sqrt(gx * gx + gy * gy);

        edgeSum += gradient;
        count++;
      }
    }

    if (count == 0) return 0;
    return (edgeSum / count / 255).clamp(0.0, 1.0);
  }

  /// Check if document appears aligned (edges parallel to image borders)
  static double _checkAlignment(img.Image image) {
    // Check for strong vertical and horizontal edges near borders
    final width = image.width;
    final height = image.height;

    // Sample vertical edges on left and right margins
    double leftEdge = 0, rightEdge = 0;
    final marginX = width ~/ 10;

    for (int y = height ~/ 4; y < height * 3 ~/ 4; y += 10) {
      // Left margin
      for (int x = marginX ~/ 2; x < marginX * 2; x += 5) {
        final pLeft = _getGrayscale(image.getPixel(x - 1, y));
        final pRight = _getGrayscale(image.getPixel(x + 1, y));
        if ((pRight - pLeft).abs() > 50) leftEdge++;
      }
      // Right margin
      for (int x = width - marginX * 2; x < width - marginX ~/ 2; x += 5) {
        final pLeft = _getGrayscale(image.getPixel(x - 1, y));
        final pRight = _getGrayscale(image.getPixel(x + 1, y));
        if ((pRight - pLeft).abs() > 50) rightEdge++;
      }
    }

    // Sample horizontal edges on top and bottom margins
    double topEdge = 0, bottomEdge = 0;
    final marginY = height ~/ 10;

    for (int x = width ~/ 4; x < width * 3 ~/ 4; x += 10) {
      // Top margin
      for (int y = marginY ~/ 2; y < marginY * 2; y += 5) {
        final pUp = _getGrayscale(image.getPixel(x, y - 1));
        final pDown = _getGrayscale(image.getPixel(x, y + 1));
        if ((pDown - pUp).abs() > 50) topEdge++;
      }
      // Bottom margin
      for (int y = height - marginY * 2; y < height - marginY ~/ 2; y += 5) {
        final pUp = _getGrayscale(image.getPixel(x, y - 1));
        final pDown = _getGrayscale(image.getPixel(x, y + 1));
        if ((pDown - pUp).abs() > 50) bottomEdge++;
      }
    }

    // Normalize and combine scores
    final expectedSamples = (height ~/ 2 ~/ 10) * (marginX * 3 ~/ 2 ~/ 5);
    final verticalScore =
        ((leftEdge + rightEdge) / 2 / expectedSamples).clamp(0.0, 1.0);

    final expectedHSamples = (width ~/ 2 ~/ 10) * (marginY * 3 ~/ 2 ~/ 5);
    final horizontalScore =
        ((topEdge + bottomEdge) / 2 / expectedHSamples).clamp(0.0, 1.0);

    return (verticalScore + horizontalScore) / 2;
  }

  static int _getGrayscale(img.Pixel pixel) {
    return ((pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114)).round();
  }

  /// Analyze image quality for real-time feedback
  /// Returns brightness, contrast, sharpness metrics
  static Future<Map<String, double>?> analyzeImageQuality(
      Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod('analyzeImageQuality', bytes);

      if (result is Map) {
        return Map<String, double>.from(result
            .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())));
      }
      return null;
    } on MissingPluginException {
      // Fall back to Dart-based analysis when native support is unavailable.
      return _analyzeQualityWithDart(bytes);
    } catch (e) {
      debugPrint('Quality analysis error: $e');
      return _analyzeQualityWithDart(bytes);
    }
  }

  /// Real image quality analysis using the image package
  static Map<String, double>? _analyzeQualityWithDart(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      final width = image.width;
      final height = image.height;
      final sampleStep = math.max(1, (width * height) ~/ 5000);

      double totalBrightness = 0;
      double totalGradient = 0;
      final brightnessValues = <double>[];
      int sampleCount = 0;

      // Sample the image
      for (int y = 1; y < height - 1; y += sampleStep) {
        for (int x = 1; x < width - 1; x += sampleStep) {
          final pixel = image.getPixel(x, y);

          // Calculate brightness (luminance)
          final brightness =
              (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114) / 255;
          brightnessValues.add(brightness);
          totalBrightness += brightness;

          // Calculate local gradient (for sharpness)
          final pRight = image.getPixel(x + 1, y);
          final pDown = image.getPixel(x, y + 1);

          final gx = ((pRight.r - pixel.r).abs() +
                  (pRight.g - pixel.g).abs() +
                  (pRight.b - pixel.b).abs()) /
              3;
          final gy = ((pDown.r - pixel.r).abs() +
                  (pDown.g - pixel.g).abs() +
                  (pDown.b - pixel.b).abs()) /
              3;

          totalGradient += math.sqrt(gx * gx + gy * gy);
          sampleCount++;
        }
      }

      if (sampleCount == 0) return null;

      // Calculate average brightness (0-1 scale)
      final avgBrightness = totalBrightness / sampleCount;

      // Calculate contrast (standard deviation of brightness)
      double variance = 0;
      for (final b in brightnessValues) {
        variance += (b - avgBrightness) * (b - avgBrightness);
      }
      final contrast =
          math.sqrt(variance / sampleCount) * 3; // Scale up for visibility

      // Calculate sharpness from average gradient
      final sharpness = (totalGradient / sampleCount / 50).clamp(0.0, 1.0);

      return {
        'brightness': avgBrightness.clamp(0.0, 1.0),
        'contrast': contrast.clamp(0.0, 1.0),
        'sharpness': sharpness,
      };
    } catch (e) {
      debugPrint('Dart quality analysis error: $e');
      return null;
    }
  }
}

/// Result of quick sheet detection for continuous scanning
class SheetDetectionResult {
  final bool sheetDetected;
  final bool isAligned;
  final bool hasGoodLighting;
  final double confidence;
  final String? hint;

  SheetDetectionResult({
    required this.sheetDetected,
    required this.isAligned,
    required this.hasGoodLighting,
    required this.confidence,
    this.hint,
  });

  factory SheetDetectionResult.notDetected({String? hint}) {
    return SheetDetectionResult(
      sheetDetected: false,
      isAligned: false,
      hasGoodLighting: true,
      confidence: 0.0,
      hint: hint ?? 'Position sheet in frame',
    );
  }

  factory SheetDetectionResult.fromJson(Map<String, dynamic> json) {
    return SheetDetectionResult(
      sheetDetected: json['sheetDetected'] as bool? ?? false,
      isAligned: json['isAligned'] as bool? ?? false,
      hasGoodLighting: json['hasGoodLighting'] as bool? ?? true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      hint: json['hint'] as String?,
    );
  }

  /// Check if sheet is ready for capture
  bool get isReadyForCapture =>
      sheetDetected && isAligned && hasGoodLighting && confidence >= 0.7;
}
