import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/opencv_bridge.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';
import 'package:omr_app/pages/scan_review_page.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:path_provider/path_provider.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_page_transitions.dart';
import 'package:omr_app/theme/app_shadows.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/theme/app_typography.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/services/native_scanner_camera.dart';
import 'package:omr_app/services/scanner_engine.dart';
import 'package:omr_app/services/scanner_camera.dart';
import 'package:omr_app/services/scanner_camera_factory.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerPage extends StatefulWidget {
  final List<CameraDescription> availableCameras;
  final Subject targetSubject;

  const ScannerPage({
    super.key,
    required this.availableCameras,
    required this.targetSubject,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  static const Color _scannerAccent = AppColors.brandGreen;
  static const Color _scannerAccentDark = AppColors.brandGreenDark;
  static const Color _scannerOverlay = AppColors.scannerOverlay;

  String? get _displayStatusHint {
    if (_isProcessing || !_opencvAvailable) {
      return null;
    }
    if (_isContinuousMode) {
      if (_sheetAligned) {
        return 'Keep all four corners inside the frame';
      }
      return 'Move closer until the sheet fills the guide';
    }
    if (_status == 'Align Answer Sheet' || _status == 'Ready to scan...') {
      return 'Tap the paper to focus, wait a moment, then capture';
    }
    return null;
  }

  bool get _showFrameGlow =>
      !_isProcessing &&
      _isContinuousMode &&
      _sheetDetected &&
      _sheetAligned;

  ScannerCamera? _scannerCamera;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _status = "Align Answer Sheet";
  bool _opencvAvailable = ScannerEngine.isReady;
  bool _opencvInitFailed = false;
  final List<ScanResult> _batchResults = [];

  // Device capability detection
  bool _isLowEndDevice = false;

  // Review mode - show answers for correction before saving
  bool _reviewBeforeSave = true;

  // Last tap-to-focus point (normalized 0–1)
  Offset _lastFocusPoint = const Offset(0.5, 0.55);
  static const Duration _preCaptureFocusDelay = Duration(milliseconds: 800);

  bool _cameraInitFailed = false;

  // Continuous scanning mode
  bool _isContinuousMode = false;
  bool _isStreamingFrames = false;
  bool _sheetDetected = false;
  bool _sheetAligned = false;
  int _stableFrameCount = 0;
  String? _lastScannedOmrId;
  DateTime? _lastScanTime;
  Timer? _cooldownTimer;
  Timer? _autoScanTimer;
  String _continuousHint = '';
  bool _isCheckingFrame = false;

  // Real-time quality feedback
  Timer? _qualityCheckTimer;
  final bool _qualityCheckEnabled = false;

  // Stability thresholds (tighter on low-end to reduce heat / OOM from burst captures)
  int get _requiredStableFrames => _isLowEndDevice ? 5 : 8;
  Duration get _scanCooldown => _isLowEndDevice
      ? const Duration(milliseconds: 2200)
      : const Duration(milliseconds: 1500);
  Duration get _continuousPollInterval => _isLowEndDevice
      ? const Duration(milliseconds: 650)
      : const Duration(milliseconds: 300);
  static const Duration _resultDisplayDuration = Duration(seconds: 2);

  bool get _isMobileNative => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// On Android, real scans are expected — do not steer users toward fake demo data.
  bool get _offerDemoMode => kIsWeb || (!Platform.isAndroid && !Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectDeviceCapabilities();
    _initCamera();
    if (!_opencvAvailable) {
      unawaited(_bootstrapScannerEngine());
    }
  }

  Future<void> _bootstrapScannerEngine() async {
    final ready = await ScannerEngine.warmUp();
    if (!mounted) {
      return;
    }
    setState(() {
      _opencvAvailable = ready;
      _opencvInitFailed = !ready;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopContinuousScanning();
    _stopQualityCheck();
    _cooldownTimer?.cancel();
    _autoScanTimer?.cancel();
    _scannerCamera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_releaseCameraForBackground());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeCameraAfterBackground());
    }
  }

  Future<void> _releaseCameraForBackground() async {
    _stopContinuousScanning();
    _stopQualityCheck();
    final camera = _scannerCamera;
    _scannerCamera = null;
    if (mounted) {
      setState(() => _isInitialized = false);
    }
    await camera?.dispose();
  }

  Future<void> _resumeCameraAfterBackground() async {
    await _initCamera();
    if (!ScannerEngine.isReady) {
      await _bootstrapScannerEngine();
    } else if (mounted) {
      setState(() => _opencvAvailable = true);
    }
    _resumeContinuousPollingIfNeeded();
  }

  /// Detect device capabilities to optimize for low-end devices
  Future<void> _detectDeviceCapabilities() async {
    try {
      final deviceInfo = await OpenCVBridge.getDeviceInfo();
      if (deviceInfo != null && mounted) {
        final maxMemoryMB = (deviceInfo['maxMemoryMB'] as int?) ?? 256;
        final freeMemoryMB = (deviceInfo['freeMemoryMB'] as int?) ?? 100;

        setState(() {
          // Consider low-end if max heap < 256MB or free memory < 100MB
          _isLowEndDevice = maxMemoryMB < 256 || freeMemoryMB < 100;
        });

        debugPrint(
            "Device: maxMem=${maxMemoryMB}MB, freeMem=${freeMemoryMB}MB, lowEnd=$_isLowEndDevice");
      }
    } catch (e) {
      debugPrint("Device detection failed: $e");
      // Assume mid-range device on failure
      _isLowEndDevice = false;
    }
  }

  Future<void> _applyFocusAtPoint(Offset normalizedPoint) async {
    _lastFocusPoint = normalizedPoint;
    await _scannerCamera?.setFocusPoint(normalizedPoint);
  }

  Future<void> _prepareCaptureFocus() async {
    await _scannerCamera?.prepareCaptureFocus(_preCaptureFocusDelay);
  }

  Future<void> _configureCameraForScanning() async {
    await _scannerCamera?.configureForScanning();
  }

  Future<void> _handlePreviewTap(TapDownDetails details, Size previewSize) async {
    final camera = _scannerCamera;
    if (camera == null || !camera.isCaptureReady || _isProcessing) {
      return;
    }

    final point = tapToNormalizedFocusCover(
      details.localPosition,
      previewSize,
      camera.previewAspectRatio,
    );

    if (mounted && !_isProcessing) {
      setState(() {
        _status = 'Focusing… hold steady, then capture';
      });
    }

    await _applyFocusAtPoint(point);
  }

  Future<bool> _waitForOpenCvReady({bool forceRetry = false}) async {
    if (_opencvAvailable || ScannerEngine.isReady) {
      if (mounted && !_opencvAvailable) {
        setState(() => _opencvAvailable = true);
      }
      return true;
    }
    if (forceRetry) {
      await OpenCVBridge.retryInit();
    }
    final ready = await OpenCVBridge.ensureReady(
      timeout: const Duration(seconds: 8),
    );
    if (mounted) {
      setState(() {
        _opencvAvailable = ready;
        _opencvInitFailed = !ready;
      });
    }
    return ready;
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Camera permission needed'),
          content: const Text(
            'To scan answer sheets, allow camera access.\n\n'
            'Go to Settings → Apps → OMR Scanner → Permissions and turn Camera on.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      return false;
    }

    status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera permission is required. Allow it in Settings, then open the scanner again.',
          ),
        ),
      );
    }
    return false;
  }

  String _userMessageForProcessingError(Object error) {
    final s = error.toString();
    if (s.contains('OUT_OF_MEMORY') ||
        s.contains('OutOfMemory') ||
        s.contains('out of memory')) {
      return 'The phone ran low on memory. Close other apps, wait a few seconds, and scan again.';
    }
    if (s.contains('BUSY') || s.contains('Already processing')) {
      return 'The scanner is still finishing the last image. Wait a moment, then try again.';
    }
    if (s.contains('IMAGE_TOO_LARGE') || s.contains('too large')) {
      return 'Photo is too large. Move slightly farther from the sheet or use a lower camera resolution, then try again.';
    }
    if (s.contains('LOW_MEMORY')) {
      return 'Free some memory (close other apps), then try again.';
    }
    if (s.contains('OPENCV_NOT_READY')) {
      return 'Scanner engine is still starting. Wait a few seconds and tap capture again.';
    }
    if (s.contains('OpenCV not available')) {
      return 'Scanner engine is not ready yet. Wait a few seconds, or fully close and reopen the app.';
    }
    final friendly = UserErrorMessages.friendlyError(error);
    if (friendly != 'Something went wrong. Try again.') {
      return friendly;
    }
    return 'Something went wrong while reading the sheet. Check lighting, hold steady, and try again.';
  }

  String get _displayStatusLine {
    if (_opencvInitFailed && !_isProcessing) {
      return 'Scan engine failed — open Settings → Retry';
    }
    if (_isProcessing) {
      return _status;
    }
    if (_isContinuousMode) {
      if (_continuousHint.isNotEmpty) {
        return _continuousHint;
      }
      if (_sheetAligned) {
        return 'Hold steady — auto capture';
      }
      return 'Auto-scanning… align sheet';
    }
    if (_status == 'Align Answer Sheet' || _status == 'Ready to scan...') {
      return 'Fit full sheet — corners + timing marks aligned';
    }
    return _status;
  }

  String? get _scanSectionLabel {
    final sections = widget.targetSubject.sectionNames;
    if (sections == null || sections.isEmpty) {
      return null;
    }
    if (sections.length == 1) {
      return sections.first;
    }
    return '${sections.length} sections';
  }

  Color get _frameAccentColor {
    if (_isProcessing) {
      return Colors.white54;
    }
    if (_isContinuousMode && _sheetDetected) {
      return _sheetAligned ? _scannerAccent : AppColors.cautionAccent;
    }
    if (_isContinuousMode) {
      return _scannerAccentDark;
    }
    return _scannerAccent;
  }

  double get _frameAccentStrokeWidth {
    if (_isContinuousMode && _sheetDetected && _sheetAligned && !_isProcessing) {
      return 4;
    }
    return 3;
  }

  /// 3:4 viewfinder aligned to the camera sensor — centered, nudged down for reach.
  _ViewfinderGeometry _scanAreaGeometry(
    BoxConstraints constraints,
    BuildContext context,
  ) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const bottomBarReserve = 16 + 88;
    const topReserve = 16.0;
    const downwardNudge = 40.0;
    final maxWidth = constraints.maxWidth;
    final maxHeight =
        constraints.maxHeight - bottomBarReserve - bottomInset - topReserve;

    var width = maxWidth;
    var height = width * 4 / 3;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * 3 / 4;
    }

    final left = (maxWidth - width) / 2;
    var top = topReserve + (maxHeight - height) / 2 + downwardNudge;
    final maxTop = topReserve + maxHeight - height;
    if (top > maxTop) {
      top = maxTop;
    }

    return _ViewfinderGeometry(
      top: top,
      left: left,
      width: width,
      height: height,
    );
  }

  /// Phone-shaped preview via [ScannerCamera] (native CameraX on Android when available).
  Widget _buildCameraPreview() {
    final camera = _scannerCamera!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _scanAreaGeometry(constraints, context);
        final viewSize = Size(geometry.width, geometry.height);

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fromRect(
              rect: geometry.rect,
              child: camera.buildPreview(
                viewSize: viewSize,
                onTapDown: _handlePreviewTap,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScanViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _scanAreaGeometry(constraints, context);
        final accent = _frameAccentColor;

        return Stack(
          children: [
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _ViewfinderDimPainter(
                cutout: geometry.rect,
                dimColor: Colors.black.withValues(alpha: 0.38),
                cornerRadius: 20,
              ),
            ),
            Positioned.fromRect(
              rect: geometry.rect,
              child: _buildScanFrame(
                accentColor: accent,
                strokeWidth: _frameAccentStrokeWidth,
                showGlow: _showFrameGlow,
              ),
            ),
          ],
        );
      },
    );
  }

  PreferredSizeWidget _buildScannerAppBar(ColorScheme colorScheme) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.targetSubject.displayName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_scanSectionLabel != null)
            Text(
              _scanSectionLabel!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
        ],
      ),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      actions: [
        TextButton(
          onPressed: _showSessionProgressSheet,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(
            '$_sessionScannedCount/${_sessionRoster.length}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          onPressed: _showScannerHelpSheet,
          icon: const Icon(Icons.help_outline_rounded),
          tooltip: 'Scanning tips',
        ),
        IconButton(
          onPressed: _showScannerSettingsSheet,
          icon: Badge(
            isLabelVisible: _opencvInitFailed,
            backgroundColor: Colors.amber.shade700,
            smallSize: 8,
            child: const Icon(Icons.tune_rounded),
          ),
          tooltip: 'Scanner settings',
        ),
      ],
    );
  }

  void _showScannerSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scanner settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 8),
              if (_opencvInitFailed)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded,
                          color: Colors.amber.shade800, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          Platform.isAndroid
                              ? 'Scanner engine could not start. Tap Retry, or fully close and reopen the app.'
                              : 'Demo mode — real scanning needs a phone build.',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                      TextButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            unawaited(_bootstrapScannerEngine());
                          },
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Review before save',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandText,
                  ),
                ),
                subtitle: const Text(
                  'Check answers on screen before saving each scan.',
                  style: TextStyle(color: AppColors.brandMuted, fontSize: 12),
                ),
                value: _reviewBeforeSave,
                activeThumbColor: AppColors.brandGreen,
                onChanged: _isContinuousMode
                    ? null
                    : (value) {
                        setState(() => _reviewBeforeSave = value);
                      },
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan mode',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Manual'),
                    icon: Icon(Icons.touch_app_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Auto'),
                    icon: Icon(Icons.autorenew_rounded, size: 18),
                  ),
                ],
                selected: {_isContinuousMode},
                onSelectionChanged: _isProcessing
                    ? null
                    : (selection) {
                        final next = selection.first;
                        if (next == _isContinuousMode) {
                          return;
                        }
                        Navigator.pop(sheetContext);
                        _toggleContinuousMode();
                      },
              ),
              const SizedBox(height: 6),
              Text(
                _isContinuousMode
                    ? 'Auto captures when the sheet is aligned and steady.'
                    : 'You tap capture when the frame looks good.',
                style: const TextStyle(
                  color: AppColors.brandMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              if (_isMobileNative) ...[
                const Divider(height: 24),
                const Text(
                  'Advanced',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Only if the in-app camera will not start or you are troubleshooting.',
                  style: TextStyle(
                    color: AppColors.brandMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            unawaited(_captureFromNativeCamera());
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Try system camera'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandGreenDark,
                      side: const BorderSide(color: AppColors.brandGreen),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final cameraReady = _scannerCamera?.isCaptureReady ?? false;
    final captureReady = !_isProcessing && cameraReady;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + bottomInset,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.scannerGlass,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: captureReady && !_isContinuousMode
                  ? AppShadows.glow(_scannerAccent, alpha: 0.22)
                  : AppShadows.floatingBar,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _displayStatusLine,
                        style: AppTypography.scannerStatus,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_displayStatusHint != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _displayStatusHint!,
                          style: AppTypography.scannerHint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!_isContinuousMode) ...[
                  const SizedBox(width: 12),
                  _buildCaptureButton(
                    colorScheme: colorScheme,
                    captureReady: captureReady,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureButton({
    required ColorScheme colorScheme,
    required bool captureReady,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: captureReady ? 1.04 : 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      onEnd: () {
        if (mounted && captureReady && !_isProcessing) {
          setState(() {});
        }
      },
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: captureReady
              ? Border.all(
                  color: _scannerAccent.withValues(alpha: 0.85),
                  width: 2.5,
                )
              : null,
          boxShadow: captureReady
              ? AppShadows.glow(_scannerAccent, alpha: 0.28)
              : null,
        ),
        child: Material(
          color: _isProcessing
              ? AppColors.neutralMuted
              : captureReady
                  ? colorScheme.primary
                  : Colors.white24,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            onTap: _isProcessing || !captureReady ? null : _captureAndProcess,
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              width: 56,
              height: 56,
              child: _isProcessing
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _showScannerHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Scanning tips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 12),
              ...[
                'Lay the sheet flat on a table with even lighting.',
                'Hold the phone about 30–40 cm above the sheet (seated or standing).',
                'Tap the preview on the paper to focus, wait a second, then capture.',
                'Match the printed timing marks on the sheet to the green ticks on each edge.',
                'Keep all four corner squares inside the green brackets.',
                'One scan reads the QR code, student ID bubbles, and all answers.',
                'Use a dark pencil (HB or 2B) and fill bubbles completely.',
                'In auto mode, wait for the green border, then hold steady.',
                if (_isLowEndDevice)
                  'On slower phones, auto-scan runs less often to stay cool.',
              ].map(
                (tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: AppColors.brandGreen,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tip,
                          style: const TextStyle(
                            color: AppColors.brandMuted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleScanPersistenceError(Object error) {
    final detail = error is _ScanPersistenceException ? error.cause : error;
    debugPrint("Scan persistence error: $detail");
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _status = "Save failed - try again";
    });
    _resumeQualityCheckIfNeeded();
    _showAndroidStyleFailureDialog(
      title: 'Could not save scan',
      message: UserErrorMessages.friendlySaveError(detail),
      debugDetail: detail.toString(),
    );
  }

  void _showAndroidStyleFailureDialog({
    required String title,
    required String message,
    String? debugDetail,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 14),
              _scanTipBullet(
                'Lay the sheet flat and fill the frame (about arm\'s length).',
              ),
              _scanTipBullet(
                'Use bright, even light — no harsh shadow across bubbles.',
              ),
              _scanTipBullet(
                'Fill bubbles with dark pencil (HB or 2B); OMR ID must be clearly marked.',
              ),
              if (debugDetail != null && debugDetail.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  debugDetail,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _scanTipBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ==================== CONTINUOUS SCANNING MODE ====================

  void _toggleContinuousMode() {
    setState(() {
      _isContinuousMode = !_isContinuousMode;
      if (_isContinuousMode) {
        _startContinuousScanning();
      } else {
        _stopContinuousScanning();
      }
    });
  }

  void _startContinuousScanning() {
    if (!_isInitialized || _scannerCamera == null || _isStreamingFrames) return;

    setState(() {
      _isStreamingFrames = true;
      _status = "Auto-scan active - position sheet";
      _stableFrameCount = 0;
      _sheetDetected = false;
      _sheetAligned = false;
    });

    _autoScanTimer = Timer.periodic(_continuousPollInterval, (_) {
      _checkForSheet();
    });
  }

  void _stopContinuousScanning() {
    _autoScanTimer?.cancel();
    _autoScanTimer = null;

    if (mounted) {
      setState(() {
        _isStreamingFrames = false;
        _sheetDetected = false;
        _sheetAligned = false;
        _stableFrameCount = 0;
        _continuousHint = '';
        if (!_isProcessing) {
          _status = "Ready to scan...";
        }
      });
    }
  }

  void _resumeContinuousPollingIfNeeded() {
    if (!_isContinuousMode ||
        !_isInitialized ||
        _scannerCamera == null ||
        !_scannerCamera!.isCaptureReady ||
        _isProcessing ||
        _autoScanTimer != null) {
      return;
    }
    setState(() {
      _isStreamingFrames = true;
      _stableFrameCount = 0;
      _sheetDetected = false;
      _sheetAligned = false;
      _status = "Auto-scan active - position sheet";
    });
    _autoScanTimer = Timer.periodic(_continuousPollInterval, (_) {
      _checkForSheet();
    });
  }

  Future<void> _checkForSheet() async {
    if (!mounted ||
        _isProcessing ||
        _isCheckingFrame ||
        _scannerCamera == null ||
        !_scannerCamera!.isCaptureReady) {
      return;
    }

    _isCheckingFrame = true;
    try {
      if (_lastScanTime != null) {
        final elapsed = DateTime.now().difference(_lastScanTime!);
        if (elapsed < _scanCooldown) {
          return;
        }
      }

      // Take a quick picture for detection
      await _prepareCaptureFocus();
      final bytes = await _scannerCamera!.capture();

      // Quick sheet detection
      final detection = await OpenCVBridge.detectSheet(bytes);

      if (!mounted) return;

      setState(() {
        _sheetDetected = detection.sheetDetected;
        _sheetAligned = detection.isAligned;
        _continuousHint = detection.hint ?? '';
      });

      if (detection.isReadyForCapture) {
        _stableFrameCount++;

        if (mounted) {
          setState(() {
            _status =
                "Hold steady... ($_stableFrameCount/$_requiredStableFrames)";
          });
        }

        // If stable for enough frames, trigger capture
        if (_stableFrameCount >= _requiredStableFrames) {
          _stableFrameCount = 0;
          _triggerAutoCapture(bytes);
        }
      } else {
        _stableFrameCount = 0;
        if (mounted && !_isProcessing) {
          String hint = detection.hint ?? '';
          if (!detection.sheetDetected) {
            hint = "Position sheet in frame";
          } else if (!detection.isAligned) {
            hint = "Align sheet edges";
          } else if (!detection.hasGoodLighting) {
            hint = "Improve lighting";
          }
          setState(() {
            _status = hint.isNotEmpty ? hint : "Auto-scan active";
            _continuousHint = hint;
          });
        }
      }

    } catch (e) {
      debugPrint("Sheet detection error: $e");
      _stableFrameCount = 0;
    } finally {
      _isCheckingFrame = false;
    }
  }

  Future<void> _triggerAutoCapture(Uint8List bytes) async {
    if (_isProcessing || !mounted) return;

    setState(() {
      _isProcessing = true;
      _status = "Processing...";
    });

    try {
      // Optimize image if needed
      var processBytes = bytes;
      if (_isLowEndDevice) {
        processBytes = await _optimizeImageForProcessing(bytes);
      }

      if (!_opencvAvailable) {
        await _waitForOpenCvReady(forceRetry: true);
      }
      if (!_opencvAvailable) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = 'Align sheet';
          });
        }
        return;
      }

      final omrResult = await OpenCVBridge.processOmr(
        processBytes,
        totalQuestions: widget.targetSubject.totalQuestions,
      );

      if (!omrResult.success || omrResult.omrId == null) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = omrResult.errorMessage ?? "Scan failed - try again";
          });
        }
        return;
      }

      // Check if this is a repeat scan of the same sheet
      if (omrResult.omrId == _lastScannedOmrId) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = "Same sheet - place next one";
          });
        }
        return;
      }

      final student = _resolveStudentFromOmrId(omrResult.omrId!);
      if (student == null) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = "Unknown OMR ID: ${omrResult.omrId}";
          });
        }
        return;
      }

      // Resolve subject from QR if available
      Subject resolvedSubject = widget.targetSubject;
      String? sheetId;
      SubjectSheetQrPayload? qrPayload;

      if (omrResult.qrData != null) {
        try {
          qrPayload = _parseQrPayload(omrResult.qrData!);
          if (qrPayload != null) {
            sheetId = qrPayload.sheetId;
            final qrSubject = qrPayload.resolveSubject();
            if (qrSubject != null) {
              resolvedSubject = qrSubject;
            }
          }
        } catch (_) {}
      }

      final scanSafety = _assessScanSafety(
        omrResult: omrResult,
        student: student,
        subject: resolvedSubject,
        targetSubject: widget.targetSubject,
        sheetId: sheetId,
        qrPayload: qrPayload,
      );

      // Check for existing scan
      final existingScan = _findExistingScan(student, resolvedSubject);
      if (existingScan != null) {
        final duplicateSafety = scanSafety.withAdditionalReason(
          'Rescan detected for an already-scanned student and subject.',
        );
        await _recordScanContinuous(
          student: student,
          subject: resolvedSubject,
          answers: omrResult.answers,
          confidence: omrResult.confidence,
          sheetId: sheetId,
          scanSafety: duplicateSafety,
          sourceBytes: processBytes,
          replaceExisting: existingScan,
        );
        if (mounted) {
          setState(() {
            _status = '${student.name} rescan queued for review';
          });
        }
        _lastScannedOmrId = omrResult.omrId;
        _lastScanTime = DateTime.now();
        return;
      }

      // Record the scan
      await _recordScanContinuous(
        student: student,
        subject: resolvedSubject,
        answers: omrResult.answers,
        confidence: omrResult.confidence,
        sheetId: sheetId,
        scanSafety: scanSafety,
        sourceBytes: processBytes,
      );

      _lastScannedOmrId = omrResult.omrId;
      _lastScanTime = DateTime.now();
    } on _ScanPersistenceException catch (e) {
      _handleScanPersistenceError(e);
    } catch (e) {
      debugPrint("Auto-capture error: $e");
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = "Scan failed — try again";
        });
        if (Platform.isAndroid) {
          _showAndroidStyleFailureDialog(
            title: 'Could not read sheet',
            message: _userMessageForProcessingError(e),
            debugDetail: e.toString(),
          );
        }
      }
    }
  }

  /// Saves a small JPEG of a flagged sheet locally for later review/disputes.
  /// Local-only — never uploaded. Returns null on any failure.
  Future<String?> _saveReviewSnapshot(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return null;
      }
      final resized = decoded.width > 1000
          ? img.copyResize(decoded, width: 1000)
          : decoded;
      final jpg = img.encodeJpg(resized, quality: 70);
      final dir = await getApplicationDocumentsDirectory();
      final snapDir = Directory('${dir.path}/scan_snapshots');
      if (!await snapDir.exists()) {
        await snapDir.create(recursive: true);
      }
      final path =
          '${snapDir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(jpg, flush: true);
      return path;
    } catch (e) {
      debugPrint('Review snapshot save failed: $e');
      return null;
    }
  }

  Future<void> _recordScanContinuous({
    required Student student,
    required Subject subject,
    required Map<int, String> answers,
    required double confidence,
    String? sheetId,
    required _ScanSafetyAssessment scanSafety,
    Uint8List? sourceBytes,
    ScanResult? replaceExisting,
  }) async {
    final score = subject.calculateSmartScore(answers);
    final scanTime = DateTime.now();
    final pendingReview = scanSafety.requiresReview;
    final updatedStudent = student.copyWith(
      score: pendingReview ? student.score : score,
      answers: pendingReview ? student.answers : answers,
      scanDate: pendingReview ? student.scanDate : scanTime,
      confidence: pendingReview ? student.confidence : confidence,
    );

    final snapshotPath = scanSafety.requiresReview
        ? await _saveReviewSnapshot(sourceBytes)
        : null;

    final result = ScanResult(
      studentOmrId: student.omrId,
      subjectId: subject.id,
      subjectName: subject.name,
      sheetId: sheetId,
      detectedAnswers: answers,
      correctnessMap: _generateCorrectnessMap(answers, subject),
      score: score,
      totalQuestions: subject.totalQuestions,
      confidence: confidence,
      scanTime: scanTime,
      scannedImagePath: snapshotPath,
      reviewReasons: scanSafety.reviewReasons,
      flaggedQuestions: scanSafety.flaggedQuestions,
      needsReview: pendingReview,
    );

    try {
      if (replaceExisting != null) {
        await LocalDataStore.instance.replaceAcceptedScan(
          updatedStudent: updatedStudent,
          previousResult: replaceExisting,
          replacementResult: result,
        );
      } else {
        await LocalDataStore.instance.saveAcceptedScan(
          updatedStudent: updatedStudent,
          result: result,
        );
      }
    } catch (error) {
      throw _ScanPersistenceException(error);
    }
    _batchResults.add(result);
    HapticFeedback.heavyImpact();

    // Format score display (show decimals only if partial credit)
    final scoreDisplay = '${formatScoreValue(score)}/${subject.totalQuestions}';

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = pendingReview
            ? '${student.name}: queued for review'
            : "✓ ${student.name}: $scoreDisplay";
      });

      // Show quick toast instead of modal in continuous mode
      _showQuickResultToast(
        updatedStudent,
        subject,
        score,
        pendingReview: pendingReview,
      );
    }
  }

  void _showQuickResultToast(
    Student student,
    Subject subject,
    double score, {
    bool pendingReview = false,
  }) {
    final percentageValue = (score / subject.totalQuestions) * 100;
    final percentage = percentageValue.toStringAsFixed(0);
    final passed = percentageValue >= 60;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              pendingReview
                  ? Icons.rate_review
                  : passed
                      ? Icons.check_circle
                      : Icons.error_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    pendingReview
                        ? 'Queued for review before saving final score'
                        : "${student.scoreDisplay}/${subject.totalQuestions} ($percentage%)",
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "#${_batchResults.length}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: passed ? _scannerAccent : Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: _resultDisplayDuration,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ==================== END CONTINUOUS SCANNING ====================

  // ==================== REAL-TIME QUALITY FEEDBACK ====================

  void _startQualityCheck() {
    if (_qualityCheckTimer != null) return;

    final interval = _isLowEndDevice
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 500);
    _qualityCheckTimer = Timer.periodic(
      interval,
      (_) => _checkImageQuality(),
    );
  }

  void _stopQualityCheck() {
    _qualityCheckTimer?.cancel();
    _qualityCheckTimer = null;
  }

  Future<void> _checkImageQuality() async {
    if (!mounted || !_isInitialized || _isProcessing || !_qualityCheckEnabled) {
      return;
    }

    // Don't check quality in continuous mode (it has its own feedback)
    if (_isContinuousMode && _isStreamingFrames) {
      return;
    }

    try {
      final camera = _scannerCamera;
      if (camera == null || !camera.isCaptureReady) return;

      final bytes = await camera.capture();
      await _analyzeImageQuality(bytes);

      if (!mounted) return;
    } catch (e) {
      // Silently ignore quality check errors
      debugPrint("Quality check error: $e");
    }
  }

  /// Called after processing completes to resume quality checks
  void _resumeQualityCheckIfNeeded() {
    if (!_isContinuousMode && _qualityCheckTimer == null && mounted) {
      _startQualityCheck();
    }
  }

  Future<_QualityAnalysis> _analyzeImageQuality(Uint8List bytes) async {
    // Try to use OpenCV for quality analysis
    try {
      final result = await OpenCVBridge.analyzeImageQuality(bytes);
      if (result != null) {
        final brightness = (result['brightness'] as num?)?.toDouble() ?? 0.5;
        final contrast = (result['contrast'] as num?)?.toDouble() ?? 0.5;
        final sharpness = (result['sharpness'] as num?)?.toDouble() ?? 0.5;

        return _evaluateQuality(brightness, contrast, sharpness);
      }
    } catch (e) {
      debugPrint("OpenCV quality analysis failed: $e");
    }

    // Fallback: estimate from file size (larger = more detail = sharper)
    final sizeKB = bytes.length / 1024;
    final estimatedSharpness = (sizeKB / 500).clamp(0.3, 1.0);

    // Can't estimate brightness without image analysis, assume OK
    return _evaluateQuality(0.5, 0.5, estimatedSharpness);
  }

  _QualityAnalysis _evaluateQuality(
      double brightness, double contrast, double sharpness) {
    // Brightness: 0 = black, 1 = white, ideal ~0.4-0.6
    // Contrast: 0 = flat, 1 = high contrast, ideal > 0.3
    // Sharpness: 0 = blurry, 1 = sharp, ideal > 0.5

    // Check for issues in priority order
    if (brightness < 0.25) {
      return _QualityAnalysis(
        brightness: brightness,
        sharpness: sharpness,
        isGood: false,
        hint: "Too dark — add more light",
        icon: Icons.brightness_low,
        color: Colors.orange,
      );
    }

    if (brightness > 0.85) {
      return _QualityAnalysis(
        brightness: brightness,
        sharpness: sharpness,
        isGood: false,
        hint: "Too bright — reduce glare",
        icon: Icons.brightness_high,
        color: Colors.orange,
      );
    }

    if (sharpness < 0.4) {
      return _QualityAnalysis(
        brightness: brightness,
        sharpness: sharpness,
        isGood: false,
        hint: "Blurry — hold steady",
        icon: Icons.blur_on,
        color: Colors.orange,
      );
    }

    if (contrast < 0.25) {
      return _QualityAnalysis(
        brightness: brightness,
        sharpness: sharpness,
        isGood: false,
        hint: "Low contrast — improve lighting",
        icon: Icons.contrast,
        color: Colors.amber,
      );
    }

    // All good!
    return _QualityAnalysis(
      brightness: brightness,
      sharpness: sharpness,
      isGood: true,
      hint: "Good quality ✓",
      icon: Icons.check_circle,
      color: _scannerAccent,
    );
  }

  // ==================== END REAL-TIME QUALITY ====================

  Future<void> _handleNativeCameraBindFailed(String message) async {
    debugPrint('Native camera bind failed: $message');
    if (!mounted) {
      return;
    }
    setState(() {
      _isInitialized = false;
      _cameraInitFailed = true;
      _status = 'Camera could not start';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Camera failed: $message'),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => unawaited(_initCamera()),
        ),
      ),
    );
  }

  Future<void> _initCamera() async {
    if (!Platform.isAndroid && widget.availableCameras.isEmpty) {
      if (mounted) {
        setState(() {
          _status = 'No camera available';
          _cameraInitFailed = true;
        });
      }
      return;
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final allowed = await _ensureCameraPermission();
      if (!allowed) {
        if (mounted) {
          setState(() {
            _status = 'Allow camera in Settings to scan';
            _cameraInitFailed = true;
          });
        }
        return;
      }
    }

    await _scannerCamera?.dispose();
    _scannerCamera = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _cameraInitFailed = false;
      });
    }

    try {
      _scannerCamera = await ScannerCameraFactory.create(
        cameras: widget.availableCameras,
      );
      if (_scannerCamera is NativeScannerCamera) {
        final native = _scannerCamera as NativeScannerCamera;
        native.onViewReady = () {
          if (mounted) {
            setState(() {});
          }
        };
        native.onBindFailed = (message) {
          unawaited(_handleNativeCameraBindFailed(message));
        };
      }
      await _scannerCamera!.configureForScanning();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _cameraInitFailed = false;
        });
        _startQualityCheck();
      }
      return;
    } catch (error) {
      debugPrint('Camera init failed: $error');
    }

    if (mounted) {
      setState(() {
        _isInitialized = false;
        _cameraInitFailed = true;
        _status = 'Camera could not start';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'In-app camera could not start. You can try the system camera instead.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'System camera',
            textColor: Colors.white,
            onPressed: () => unawaited(_captureFromNativeCamera()),
          ),
        ),
      );
    }
  }

  /// Compress and optimize image for processing (runs in isolate for UI responsiveness)
  Future<Uint8List> _optimizeImageForProcessing(Uint8List bytes) async {
    if (bytes.length < 2.5 * 1024 * 1024) {
      return bytes;
    }

    debugPrint("Optimizing image: ${bytes.length ~/ 1024}KB");

    try {
      // Use compute to run in separate isolate (prevents UI jank)
      final optimized = await compute(_compressImageIsolate, bytes);
      debugPrint("Optimized to: ${optimized.length ~/ 1024}KB");
      return optimized;
    } catch (e) {
      debugPrint("Image optimization failed: $e");
      return bytes; // Return original on failure
    }
  }

  /// Static function for isolate - compresses image
  static Uint8List _compressImageIsolate(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Keep enough detail for bubble detection on high-res phone captures.
    const maxDim = 2400;
    img.Image resized;

    if (image.width > maxDim || image.height > maxDim) {
      if (image.width > image.height) {
        resized = img.copyResize(image, width: maxDim);
      } else {
        resized = img.copyResize(image, height: maxDim);
      }
    } else {
      resized = image;
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 92));
  }

  /// Static function for isolate - reads file bytes
  static Future<Uint8List> _readBytesInIsolate(String path) async {
    return await File(path).readAsBytes();
  }

  Future<void> _captureFromNativeCamera() async {
    if (_isProcessing || !mounted) {
      return;
    }

    _stopQualityCheck();
    setState(() {
      _isProcessing = true;
      _status = 'Opening camera…';
    });

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (!mounted) {
        return;
      }
      if (picked == null) {
        setState(() {
          _isProcessing = false;
          _status = 'Ready to scan...';
        });
        _resumeQualityCheckIfNeeded();
        return;
      }

      final bytes = await picked.readAsBytes();
      await _processCapturedBytes(bytes);
    } catch (error) {
      debugPrint('Native camera capture failed: $error');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Camera cancelled';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserErrorMessages.friendlyError(error)),
            backgroundColor: Colors.red,
          ),
        );
        _resumeQualityCheckIfNeeded();
      }
    }
  }

  Future<void> _processCapturedBytes(Uint8List rawBytes) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = 'Reading image...';
    });

    try {
      var bytes = rawBytes;

      if (_isLowEndDevice || bytes.length > 2 * 1024 * 1024) {
        setState(() => _status = 'Optimizing...');
        bytes = await _optimizeImageForProcessing(bytes);
      }

      if (!_opencvAvailable) {
        setState(() => _status = 'Starting scan engine...');
      } else {
        setState(() => _status = 'Processing with OpenCV...');
      }

      final engineReady = await _waitForOpenCvReady(forceRetry: true);
      if (!engineReady) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = 'Align sheet';
          });
          if (Platform.isAndroid) {
            _showAndroidStyleFailureDialog(
              title: 'Scanner still starting',
              message:
                  'The scan engine was not ready yet. Wait a few seconds and capture again. '
                  'If this keeps happening, close the app completely and reopen it.',
            );
          } else if (_offerDemoMode) {
            _showDemoModeDialog();
          }
        }
        return;
      }

      if (mounted) {
        setState(() => _status = 'Processing with OpenCV...');
      }

      final omrResult = await OpenCVBridge.processOmr(
        bytes,
        totalQuestions: widget.targetSubject.totalQuestions,
      );

      debugPrint('OMR Result: $omrResult');

      if (omrResult.debugInfo.isNotEmpty) {
        final blurScore = omrResult.debugInfo['blurScore'];
        final contrastScore = omrResult.debugInfo['contrastScore'];
        final qualityIssues = omrResult.debugInfo['qualityIssues'];
        if (blurScore != null) {
          debugPrint(
              'Image quality - blur: $blurScore, contrast: $contrastScore, issues: $qualityIssues');
        }
      }

      if (!omrResult.success) {
        if (mounted) {
          final errorMsg = omrResult.errorMessage ?? 'Scan failed';
          final helpTip = _getQualityHelpTip(omrResult.debugInfo);
          setState(() {
            _status = errorMsg;
            _isProcessing = false;
          });
          _showScanErrorWithTips(errorMsg, helpTip);
        }
        return;
      }

      if (omrResult.omrId == null) {
        if (mounted) {
          setState(() {
            _status = 'Could not read OMR ID';
            _isProcessing = false;
          });
          _showScanError('Could not read the 4-digit OMR ID.\n\n'
              'Fill those bubbles with a dark pencil (HB or 2B), one digit per column, '
              'then try again with good light and the ID area in focus.');
        }
        return;
      }

      final student = _resolveStudentFromOmrId(omrResult.omrId!);
      if (student == null) {
        if (mounted) {
          setState(() {
            _status = 'Student not found: ${omrResult.omrId}';
            _isProcessing = false;
          });
          _showScanError(
              "OMR ID '${omrResult.omrId}' does not match any imported student.");
        }
        return;
      }

      Subject resolvedSubject = widget.targetSubject;
      String? sheetId;
      SubjectSheetQrPayload? qrPayload;

      if (omrResult.qrData != null) {
        try {
          qrPayload = _parseQrPayload(omrResult.qrData!);
          if (qrPayload != null) {
            sheetId = qrPayload.sheetId;
            final qrSubject = qrPayload.resolveSubject();
            if (qrSubject != null) {
              resolvedSubject = qrSubject;
              debugPrint(
                  'Subject resolved from QR: ${resolvedSubject.displayName}');
            }
          }
        } catch (e) {
          debugPrint('QR parsing error: $e');
        }
      }

      final scanSafety = _assessScanSafety(
        omrResult: omrResult,
        student: student,
        subject: resolvedSubject,
        targetSubject: widget.targetSubject,
        sheetId: sheetId,
        qrPayload: qrPayload,
      );

      final existingScan = _findExistingScan(student, resolvedSubject);
      if (existingScan != null) {
        if (mounted) {
          setState(() {
            _status = 'Already scanned: ${student.name}';
            _isProcessing = false;
          });
          _showRescanDialog(
            student: student,
            subject: resolvedSubject,
            existingScan: existingScan,
            newAnswers: omrResult.answers,
            newConfidence: omrResult.confidence,
            sheetId: sheetId,
            scanSafety: scanSafety.withAdditionalReason(
              'Rescan detected for an already-scanned student and subject.',
            ),
          );
        }
        return;
      }

      await _recordScan(
        student: student,
        subject: resolvedSubject,
        answers: omrResult.answers,
        confidence: omrResult.confidence,
        sheetId: sheetId,
        scanSafety: scanSafety,
        sourceBytes: bytes,
      );
    } on _ScanPersistenceException catch (e) {
      _handleScanPersistenceError(e);
    } on PlatformException catch (e) {
      debugPrint('OpenCV platform error: ${e.message}');

      if (mounted) {
        setState(() {
          _status = 'Scan failed — see message';
          _isProcessing = false;
        });

        _showOpenCVErrorDialog(e.message ?? 'Unknown error');
      }
    } catch (e) {
      debugPrint('Processing error: $e');

      if (mounted) {
        setState(() {
          _status = 'Scan failed — try again';
          _isProcessing = false;
        });

        if (Platform.isAndroid) {
          _showAndroidStyleFailureDialog(
            title: 'Could not process scan',
            message: _userMessageForProcessingError(e),
            debugDetail: e.toString(),
          );
        } else if (_offerDemoMode) {
          _showDemoModeDialog();
        } else {
          _showAndroidStyleFailureDialog(
            title: 'Could not process scan',
            message: _userMessageForProcessingError(e),
            debugDetail: e.toString(),
          );
        }
      }
    } finally {
      _resumeQualityCheckIfNeeded();
    }
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing ||
        _scannerCamera == null ||
        !_scannerCamera!.isCaptureReady) {
      return;
    }

    _stopQualityCheck();

    setState(() {
      _isProcessing = true;
      _status = 'Capturing...';
    });

    try {
      await _prepareCaptureFocus();
      final bytes = await _scannerCamera!.capture();
      await _processCapturedBytes(bytes);
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Capture failed — try again';
        });
        _resumeQualityCheckIfNeeded();
      }
    }
  }

  SubjectSheetQrPayload? _parseQrPayload(String qrData) {
    try {
      final decoded = jsonDecode(qrData);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return SubjectSheetQrPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Subject? _resolveSubjectFromQr(String qrData) {
    final payload = _parseQrPayload(qrData);
    return payload?.resolveSubject();
  }

  Student? _resolveStudentFromOmrId(String omrId) {
    final normalizedOmrId = omrId.trim();
    if (normalizedOmrId.isEmpty) {
      return null;
    }
    // O(1) lookup using index
    return findStudentByOmrId(normalizedOmrId);
  }

  bool _hasScanForSubject(Student student, Subject subject) {
    // Use indexed lookup for better performance
    final studentScans = findScansByStudent(student.omrId);
    return studentScans.any(
      (result) =>
          result.subjectId == subject.id ||
          (result.subjectId == null &&
              result.subjectName.trim().toUpperCase() ==
                  subject.name.trim().toUpperCase()),
    );
  }

  /// Students expected for this exam session: those in the target subject's
  /// sections. Falls back to the whole roster when no sections are assigned.
  List<Student> get _sessionRoster {
    final sections = (widget.targetSubject.sectionNames ?? const <String>[])
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (sections.isEmpty) {
      return globalStudentDatabase;
    }
    return globalStudentDatabase
        .where((s) => sections.contains(s.section.trim().toUpperCase()))
        .toList();
  }

  List<Student> get _sessionPendingStudents => _sessionRoster
      .where((student) => !_hasScanForSubject(student, widget.targetSubject))
      .toList();

  int get _sessionScannedCount =>
      _sessionRoster.length - _sessionPendingStudents.length;

  void _showSessionProgressSheet() {
    final pending = _sessionPendingStudents
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final roster = _sessionRoster;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session progress',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_sessionScannedCount} of ${roster.length} scanned for ${widget.targetSubject.name}',
                style: const TextStyle(color: AppColors.brandMuted),
              ),
              const SizedBox(height: 14),
              if (pending.isEmpty)
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.brandGreen),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Everyone in this class has been scanned.',
                        style: TextStyle(
                          color: AppColors.brandText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                Text(
                  'Still pending (${pending.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pending.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final student = pending[index];
                      return Row(
                        children: [
                          const Icon(Icons.radio_button_unchecked,
                              size: 18, color: AppColors.brandMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              student.name,
                              style: const TextStyle(
                                color: AppColors.brandText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            'ID ${student.omrId}',
                            style: const TextStyle(
                              color: AppColors.brandMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ScanResult? _findExistingScan(Student student, Subject subject) {
    final studentScans = findScansByStudent(student.omrId);
    for (final result in studentScans) {
      if (result.subjectId == subject.id ||
          (result.subjectId == null &&
              result.subjectName.trim().toUpperCase() ==
                  subject.name.trim().toUpperCase())) {
        return result;
      }
    }
    return null;
  }

  _ScanSafetyAssessment _assessScanSafety({
    required OmrScanResult omrResult,
    required Student student,
    required Subject subject,
    required Subject targetSubject,
    required String? sheetId,
    SubjectSheetQrPayload? qrPayload,
  }) {
    final reasons = <String>[];
    final flaggedQuestions = <int>{};
    final debugInfo = omrResult.debugInfo;

    if (omrResult.confidence < 0.7) {
      reasons.add(
        'Low scan confidence (${(omrResult.confidence * 100).round()}%).',
      );
    }

    if (subject.id != targetSubject.id) {
      reasons.add(
        'Sheet QR is for ${subject.displayName}, but this scanner is set to ${targetSubject.displayName}.',
      );
    }

    final assignedSections = subject.sectionNames ?? const <String>[];
    if (assignedSections.isEmpty) {
      reasons.add('Subject has no assigned section.');
    } else {
      final normalizedStudentSection = _normalizeScanSection(student.section);
      final sectionMatches = assignedSections.any(
        (section) => _normalizeScanSection(section) == normalizedStudentSection,
      );
      if (!sectionMatches) {
        reasons.add(
          '${student.name} belongs to ${student.section}, which is not assigned to ${subject.displayName}.',
        );
      }
    }

    if (omrResult.qrData == null) {
      reasons.add('Template QR was not found.');
    } else if (qrPayload == null) {
      reasons.add('Template QR could not be read.');
    } else {
      if (sheetId == null || sheetId.trim().isEmpty) {
        reasons.add('Template QR is missing a sheet ID.');
      }
      if (qrPayload.subjectId.isNotEmpty && qrPayload.subjectId != subject.id) {
        reasons.add('Template QR subject does not match the saved answer key.');
      }
      if (qrPayload.totalQuestions != 0 &&
          qrPayload.totalQuestions != subject.totalQuestions) {
        reasons.add(
          'Template QR expects ${qrPayload.totalQuestions} questions, but ${subject.displayName} has ${subject.totalQuestions}.',
        );
      }
      final qrSection = qrPayload.sectionName?.trim();
      if (qrSection != null &&
          qrSection.isNotEmpty &&
          _normalizeScanSection(qrSection) !=
              _normalizeScanSection(student.section)) {
        reasons.add(
          'Sheet section is $qrSection, but student is in ${student.section}.',
        );
      }
    }

    final invalidAnswerQuestions = <int>[];
    for (final entry in omrResult.answers.entries) {
      final question = entry.key;
      if (question < 1 || question > subject.totalQuestions) {
        invalidAnswerQuestions.add(question);
        continue;
      }

      final selections = parseStoredAnswerSelections(entry.value);
      if (selections.isEmpty ||
          selections.any((answer) => answer.length != 1)) {
        invalidAnswerQuestions.add(question);
      }
    }
    if (invalidAnswerQuestions.isNotEmpty) {
      invalidAnswerQuestions.sort();
      reasons.add(
        'Invalid answer data on question(s): ${invalidAnswerQuestions.take(8).join(', ')}${invalidAnswerQuestions.length > 8 ? '...' : ''}.',
      );
      flaggedQuestions.addAll(
        invalidAnswerQuestions.where(
          (question) => question >= 1 && question <= subject.totalQuestions,
        ),
      );
    }

    final multipleMarks = _readDebugInt(debugInfo, 'multipleSelectionsLayout') +
        _readDebugInt(debugInfo, 'multipleSelections');
    if (multipleMarks > 0) {
      reasons.add('$multipleMarks question(s) appear to have multiple marks.');
    }

    for (final question in _readDebugIntList(debugInfo, 'ambiguousQuestions')) {
      if (question >= 1 && question <= subject.totalQuestions) {
        flaggedQuestions.add(question);
      }
    }

    final missingQuestions = <int>[
      for (int question = 1; question <= subject.totalQuestions; question++)
        if (!omrResult.answers.containsKey(question)) question,
    ];
    if (missingQuestions.isNotEmpty) {
      reasons.add(
        'Unread answer(s): ${missingQuestions.take(8).join(', ')}${missingQuestions.length > 8 ? '...' : ''}.',
      );
      flaggedQuestions.addAll(missingQuestions);
    }

    final layoutFromQr = debugInfo['layoutFromQr'] == true;
    if (!layoutFromQr) {
      reasons.add('Template layout could not be confirmed from QR.');
    }

    return _ScanSafetyAssessment(
      reviewReasons: <String>{...reasons}.toList(),
      flaggedQuestions: flaggedQuestions.toList()..sort(),
    );
  }

  String _normalizeScanSection(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  int _readDebugInt(Map<String, dynamic> debugInfo, String key) {
    final value = debugInfo[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<int> _readDebugIntList(Map<String, dynamic> debugInfo, String key) {
    final value = debugInfo[key];
    if (value is! List) {
      return const <int>[];
    }
    return value
        .map((entry) => entry is int ? entry : int.tryParse(entry.toString()))
        .whereType<int>()
        .toList();
  }

  Future<void> _recordScan({
    required Student student,
    required Subject subject,
    required Map<int, String> answers,
    required double confidence,
    String? sheetId,
    bool skipReview = false,
    _ScanSafetyAssessment? scanSafety,
    Uint8List? sourceBytes,
  }) async {
    final safety = scanSafety ?? _ScanSafetyAssessment.safe();

    // Risky scans are reviewed even when the optional review toggle is off.
    if ((_reviewBeforeSave && !skipReview) || safety.requiresReview) {
      final wasContinuous = _isContinuousMode;
      if (wasContinuous && safety.requiresReview) {
        _stopContinuousScanning();
      }
      await _showScanReview(
        student: student,
        subject: subject,
        answers: answers,
        confidence: confidence,
        sheetId: sheetId,
        scanSafety: safety,
        sourceBytes: sourceBytes,
      );
      if (wasContinuous && mounted) {
        _startContinuousScanning();
      }
      return;
    }

    await _saveScanResult(
      student: student,
      subject: subject,
      answers: answers,
      confidence: confidence,
      sheetId: sheetId,
      scanSafety: safety,
      sourceBytes: sourceBytes,
    );
  }

  /// Shows the scan review page for answer correction
  Future<void> _showScanReview({
    required Student student,
    required Subject subject,
    required Map<int, String> answers,
    required double confidence,
    String? sheetId,
    required _ScanSafetyAssessment scanSafety,
    Uint8List? sourceBytes,
  }) async {
    if (!mounted) return;

    final result = await Navigator.push<ScanReviewResult>(
      context,
      AppPageTransitions.fadeSlide(
        ScanReviewPage(
          student: student,
          subject: subject,
          detectedAnswers: answers,
          confidence: confidence,
          sheetId: sheetId,
          reviewReasons: scanSafety.reviewReasons,
          flaggedQuestions: scanSafety.flaggedQuestions,
          requireExitConfirmation: scanSafety.requiresReview,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      // User confirmed - save with potentially edited answers
      await _saveScanResult(
        student: student,
        subject: subject,
        answers: result.editedAnswers,
        confidence: confidence,
        sheetId: sheetId,
        wasEdited: result.wasEdited,
        scanSafety: scanSafety,
        wasManuallyReviewed: true,
        sourceBytes: sourceBytes,
      );
    } else {
      // User discarded
      setState(() {
        _isProcessing = false;
        _status = "Scan discarded";
      });
      // Resume quality checking after discard
      _resumeQualityCheckIfNeeded();
    }
  }

  /// Actually saves the scan result to the database
  Future<void> _saveScanResult({
    required Student student,
    required Subject subject,
    required Map<int, String> answers,
    required double confidence,
    String? sheetId,
    bool wasEdited = false,
    required _ScanSafetyAssessment scanSafety,
    bool wasManuallyReviewed = false,
    Uint8List? sourceBytes,
  }) async {
    final score = subject.calculateSmartScore(answers);
    final scanTime = DateTime.now();
    final pendingReview = scanSafety.requiresReview && !wasManuallyReviewed;
    final updatedStudent = student.copyWith(
      score: pendingReview ? student.score : score,
      answers: pendingReview ? student.answers : answers,
      scanDate: pendingReview ? student.scanDate : scanTime,
      confidence: pendingReview ? student.confidence : confidence,
    );

    // Keep a local snapshot for flagged/reviewed sheets so scores can be
    // disputed later. Local-only; never uploaded.
    final snapshotPath = scanSafety.requiresReview
        ? await _saveReviewSnapshot(sourceBytes)
        : null;

    final result = ScanResult(
      studentOmrId: student.omrId,
      subjectId: subject.id,
      subjectName: subject.name,
      sheetId: sheetId,
      detectedAnswers: answers,
      correctnessMap: _generateCorrectnessMap(answers, subject),
      score: score,
      totalQuestions: subject.totalQuestions,
      confidence: confidence,
      scanTime: scanTime,
      scannedImagePath: snapshotPath,
      reviewReasons: scanSafety.reviewReasons,
      flaggedQuestions: scanSafety.flaggedQuestions,
      manuallyConfirmed: wasManuallyReviewed,
      needsReview: pendingReview,
    );

    try {
      await LocalDataStore.instance.saveAcceptedScan(
        updatedStudent: updatedStudent,
        result: result,
      );
    } catch (error) {
      throw _ScanPersistenceException(error);
    }
    _batchResults.add(result);
    HapticFeedback.heavyImpact();

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = pendingReview
            ? "Queued for review: ${student.name}"
            : wasEdited
                ? "Saved (edited): ${updatedStudent.name}"
                : "Scanned: ${updatedStudent.name} - ${subject.displayName}";
      });

      if (pendingReview) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan queued for review before final score is saved'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        _showResultOverlay(updatedStudent, subject);
      }
    }
  }

  void _showRescanDialog({
    required Student student,
    required Subject subject,
    required ScanResult existingScan,
    required Map<int, String> newAnswers,
    required double newConfidence,
    String? sheetId,
    required _ScanSafetyAssessment scanSafety,
  }) {
    final newScore = subject.calculateSmartScore(newAnswers);
    final scoreDiff = newScore - existingScan.score;
    final diffText = scoreDiff > 0
        ? '+${scoreDiff.toStringAsFixed(scoreDiff == scoreDiff.floorToDouble() ? 0 : 1)}'
        : scoreDiff
            .toStringAsFixed(scoreDiff == scoreDiff.floorToDouble() ? 0 : 1);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Already Scanned"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                "${student.name} already has a scan for ${subject.displayName}."),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text("Previous",
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                            "${existingScan.scoreDisplay}/${existingScan.totalQuestions}",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                  Expanded(
                    child: Column(
                      children: [
                        const Text("New Scan",
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                            "${formatScoreValue(newScore)}/${subject.totalQuestions}",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scoreDiff >= 0
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(diffText,
                        style: TextStyle(
                          color: scoreDiff >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text("Do you want to update with the new scan?",
                style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Keep Previous"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _reviewAndUpdateExistingScan(
                  student: student,
                  subject: subject,
                  existingScan: existingScan,
                  newAnswers: newAnswers,
                  newConfidence: newConfidence,
                  sheetId: sheetId,
                  scanSafety: scanSafety,
                );
              } catch (error) {
                _handleScanPersistenceError(error);
              }
            },
            child: const Text("Update Scan"),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewAndUpdateExistingScan({
    required Student student,
    required Subject subject,
    required ScanResult existingScan,
    required Map<int, String> newAnswers,
    required double newConfidence,
    String? sheetId,
    required _ScanSafetyAssessment scanSafety,
  }) async {
    if (!mounted) return;

    final reviewResult = await Navigator.push<ScanReviewResult>(
      context,
      AppPageTransitions.fadeSlide(
        ScanReviewPage(
          student: student,
          subject: subject,
          detectedAnswers: newAnswers,
          confidence: newConfidence,
          sheetId: sheetId,
          reviewReasons: scanSafety.reviewReasons,
          flaggedQuestions: scanSafety.flaggedQuestions,
          requireExitConfirmation: scanSafety.requiresReview,
        ),
      ),
    );

    if (reviewResult == null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Rescan discarded';
        });
      }
      return;
    }

    await _updateExistingScan(
      student: student,
      subject: subject,
      existingScan: existingScan,
      newAnswers: reviewResult.editedAnswers,
      newConfidence: newConfidence,
      sheetId: sheetId,
      scanSafety: scanSafety,
      wasManuallyReviewed: true,
    );
  }

  Future<void> _updateExistingScan({
    required Student student,
    required Subject subject,
    required ScanResult existingScan,
    required Map<int, String> newAnswers,
    required double newConfidence,
    String? sheetId,
    required _ScanSafetyAssessment scanSafety,
    bool wasManuallyReviewed = false,
  }) async {
    final score = subject.calculateSmartScore(newAnswers);
    final scanTime = DateTime.now();

    // Update student record
    final updatedStudent = student.copyWith(
      score: score,
      answers: newAnswers,
      scanDate: scanTime,
      confidence: newConfidence,
    );

    // Add new scan result
    final newResult = ScanResult(
      studentOmrId: student.omrId,
      subjectId: subject.id,
      subjectName: subject.name,
      sheetId: sheetId,
      detectedAnswers: newAnswers,
      correctnessMap: _generateCorrectnessMap(newAnswers, subject),
      score: score,
      totalQuestions: subject.totalQuestions,
      confidence: newConfidence,
      scanTime: scanTime,
      reviewReasons: scanSafety.reviewReasons,
      flaggedQuestions: scanSafety.flaggedQuestions,
      manuallyConfirmed: wasManuallyReviewed,
      needsReview: scanSafety.requiresReview && !wasManuallyReviewed,
    );

    try {
      await LocalDataStore.instance.replaceAcceptedScan(
        updatedStudent: updatedStudent,
        previousResult: existingScan,
        replacementResult: newResult,
      );
    } catch (error) {
      throw _ScanPersistenceException(error);
    }
    _batchResults.add(newResult);
    HapticFeedback.heavyImpact();

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = "Updated: ${updatedStudent.name} - ${subject.displayName}";
      });
      _showResultOverlay(updatedStudent, subject);
    }
  }

  void _showOpenCVErrorDialog(String error) {
    final isAndroid = Platform.isAndroid;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isAndroid ? "Scan error" : "OpenCV Error"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAndroid
                    ? "The scanner could not finish this image."
                    : "Failed to process image with OpenCV.",
              ),
              const SizedBox(height: 10),
              Text(
                error,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 12),
              if (isAndroid) ...[
                _scanTipBullet(
                  'Move to even lighting; avoid shadow on the answer grid.',
                ),
                _scanTipBullet(
                  'Hold the phone steady and keep the whole page in frame.',
                ),
                _scanTipBullet(
                  'Use a dark pencil fill for bubbles and the 4-digit OMR ID.',
                ),
              ] else
                const Text(
                  "If this persists, you can use DEMO MODE to explore the app without a real scan.",
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
          if (!isAndroid && _offerDemoMode)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _simulateSuccessfulScan();
                } catch (error) {
                  _handleScanPersistenceError(error);
                }
              },
              child: const Text("Demo scan"),
            ),
        ],
      ),
    );
  }

  void _showDemoModeDialog() {
    if (!_offerDemoMode) {
      _showAndroidStyleFailureDialog(
        title: 'Scanner unavailable',
        message:
            'This build cannot run the camera scanner. Use the mobile app on Android or iOS.',
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Practice mode"),
        content: const Text(
          "OpenCV is not available on this platform yet.\n\n"
          "You can run a simulated scan to try scores and review — it does not read a real sheet.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isProcessing = false;
                _status = "Ready to scan...";
              });
            },
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _simulateSuccessfulScan();
              } catch (error) {
                _handleScanPersistenceError(error);
              }
            },
            child: const Text("Simulated scan"),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateSuccessfulScan() async {
    final qrData =
        AnswerSheetGenerator.buildSheetQrCodeData(widget.targetSubject);
    final qrPayload = _parseQrPayload(qrData);
    final resolvedSubject =
        qrPayload == null ? null : _resolveSubjectFromQr(qrData);

    if (resolvedSubject == null || qrPayload == null) {
      _showScanError(
        'The sheet QR code could not be resolved to a saved subject.',
      );
      setState(() {
        _isProcessing = false;
        _status = "Unable to resolve subject QR";
      });
      return;
    }

    final unscannedStudents = globalStudentDatabase
        .where((student) => !_hasScanForSubject(student, resolvedSubject))
        .toList();

    if (unscannedStudents.isEmpty) {
      _showNoStudentsDialog();
      setState(() {
        _isProcessing = false;
        _status = "No students to scan";
      });
      return;
    }

    final resolvedStudent =
        _resolveStudentFromOmrId(unscannedStudents.first.omrId);
    if (resolvedStudent == null) {
      _showScanError('The shaded OMR ID does not match any imported student.');
      setState(() {
        _isProcessing = false;
        _status = "Student OMR ID not found";
      });
      return;
    }

    final mockAnswers = _generateMockAnswers(resolvedSubject);
    await _recordScan(
      student: resolvedStudent,
      subject: resolvedSubject,
      answers: mockAnswers,
      confidence: 0.95,
      sheetId: qrPayload.sheetId,
    );
  }

  Map<int, String> _generateMockAnswers(Subject subject) {
    final answers = <int, String>{};
    final letters = ['A', 'B', 'C', 'D', 'E'];

    for (int i = 1; i <= subject.totalQuestions; i++) {
      if (i % 5 == 0) {
        answers[i] = letters[i % letters.length];
      } else {
        final acceptedAnswers = subject.answerKey[i];
        answers[i] = acceptedAnswers == null || acceptedAnswers.isEmpty
            ? 'A'
            : acceptedAnswers.first;
      }
    }
    return answers;
  }

  Map<int, double> _generateCorrectnessMap(
    Map<int, String> answers,
    Subject subject,
  ) {
    final correctness = <int, double>{};
    answers.forEach((q, answer) {
      correctness[q] = subject.calculateQuestionScore(q, answer);
    });
    return correctness;
  }

  void _showScanError(String message) {
    _showScanErrorWithTips(
      message,
      'Use a dark pencil (HB/2B), lay the sheet flat, and keep all four corner squares in frame.',
    );
  }

  /// Get helpful tip based on quality issues
  String _getQualityHelpTip(Map<String, dynamic> debugInfo) {
    final blurScore = (debugInfo['blurScore'] as num?)?.toDouble();
    final contrastScore = (debugInfo['contrastScore'] as num?)?.toDouble();
    final brightnessScore = (debugInfo['brightnessScore'] as num?)?.toDouble();
    final qualityIssues = debugInfo['qualityIssues'] as List?;

    // Check for specific issues
    if (blurScore != null && blurScore < 50) {
      return "Hold steady, tap the screen to focus, then capture.";
    }
    if (brightnessScore != null && brightnessScore < 60) {
      return "Too dark — move to brighter light or turn on a lamp.";
    }
    if (brightnessScore != null && brightnessScore > 220) {
      return "Too bright — tilt the page to remove glare from bubbles.";
    }
    if (contrastScore != null && contrastScore < 0.25) {
      return "Low contrast — lay the sheet flat with even light across it.";
    }
    if (qualityIssues != null && qualityIssues.isNotEmpty) {
      return "${qualityIssues.first}";
    }

    return "Fill bubbles and OMR ID with a dark pencil; keep the sheet flat and fully in frame.";
  }

  /// Show scan error with quality improvement tips
  void _showScanErrorWithTips(String message, String helpTip) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text("Scan Failed"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.brandGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.tips_and_updates,
                    color: AppColors.brandGreenDark,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      helpTip,
                      style: const TextStyle(
                        color: AppColors.brandGreenDark,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              _scanTipBullet(
                  'Corner squares must be visible — don’t crop the page.'),
              _scanTipBullet(
                  'Re-scan with darker marks if bubbles were light or smudged.'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("TRY AGAIN"),
          ),
        ],
      ),
    );
  }

  void _showNoStudentsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("No Students"),
        content: const Text(
          "All students for this subject have been scanned already.\n\n"
          "Import more students or start a new section.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showResultOverlay(Student student, Subject subject) {
    final score = student.score ?? 0;
    final total = subject.totalQuestions;
    final percentage =
        total > 0 ? (score / total * 100).toStringAsFixed(1) : '0.0';

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.brandBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.brandGreen,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                student.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${student.section} · OMR ${student.omrId}',
                style: const TextStyle(
                  color: AppColors.brandMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.brandBorder),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Score',
                      style: TextStyle(
                        color: AppColors.brandMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          student.scoreDisplay,
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: AppColors.brandGreen,
                            height: 1,
                          ),
                        ),
                        Text(
                          ' / $total',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        color: AppColors.brandMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_batchResults.length > 1) ...[
                const SizedBox(height: 10),
                Text(
                  '${_batchResults.length} scanned this session',
                  style: const TextStyle(
                    color: AppColors.brandMuted,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandText,
                        side: const BorderSide(color: AppColors.brandBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Finish'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _isProcessing = false;
                          _status = 'Ready to scan...';
                        });
                        _resumeQualityCheckIfNeeded();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Scan next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isInitialized) {
      if (_cameraInitFailed) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _buildScannerAppBar(colorScheme),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scanning stays in the app when the camera starts normally.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  if (_isMobileNative)
                    FilledButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => unawaited(_captureFromNativeCamera()),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Try system camera'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => unawaited(_initCamera()),
                    child: const Text(
                      'Retry in-app camera',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.brandGreen),
              SizedBox(height: 20),
              Text(
                'Starting camera…',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildScannerAppBar(colorScheme),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_scannerCamera != null && _scannerCamera!.isInitialized)
            _buildCameraPreview()
          else
            const Center(
              child: Text(
                'Camera not available',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          _buildScanViewport(),
          _buildBottomBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildScanFrame({
    required Color accentColor,
    required double strokeWidth,
    required bool showGlow,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _CornerBracketPainter(
            color: accentColor,
            strokeWidth: strokeWidth,
            bracketLength: 36,
            showGlow: showGlow,
            showEdgeGuides: true,
          ),
        ),
        if (_isContinuousMode && _stableFrameCount > 0)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: _stableFrameCount / _requiredStableFrames,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_scannerAccent),
                  minHeight: 4,
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Align timing marks to green ticks',
                  style: TextStyle(
                    color: accentColor.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Four corner squares visible · tap paper to focus',
                  style: TextStyle(
                    color: accentColor.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _ViewfinderGeometry {
  const _ViewfinderGeometry({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });

  final double top;
  final double left;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(left, top, width, height);
}

class _ViewfinderDimPainter extends CustomPainter {
  _ViewfinderDimPainter({
    required this.cutout,
    required this.dimColor,
    required this.cornerRadius,
  });

  final Rect cutout;
  final Color dimColor;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(
        RRect.fromRectAndRadius(cutout, Radius.circular(cornerRadius)),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlay,
      Paint()..color = dimColor,
    );

    final edgeVignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.18),
        ],
        stops: const [0.62, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), edgeVignette);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderDimPainter oldDelegate) {
    return oldDelegate.cutout != cutout ||
        oldDelegate.dimColor != dimColor ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({
    required this.color,
    required this.strokeWidth,
    required this.bracketLength,
    this.showGlow = false,
    this.showEdgeGuides = false,
  });

  final Color color;
  final double strokeWidth;
  final double bracketLength;
  final bool showGlow;
  final bool showEdgeGuides;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGlow) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.28)
        ..strokeWidth = strokeWidth + 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      _drawCorners(canvas, size, glowPaint);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawCorners(canvas, size, paint);

    if (showEdgeGuides) {
      _drawTimingMarkGuides(canvas, size, paint);
    }
  }

  /// Green ticks on all four edges — align with printed timing marks on the sheet.
  void _drawTimingMarkGuides(Canvas canvas, Size size, Paint basePaint) {
    const pageW = OmrPageConstants.pageWidth;
    const pageH = OmrPageConstants.pageHeight;
    const startX = OmrPageConstants.timingMarkStartX;
    const endX = OmrPageConstants.timingMarkEndX;
    const startY = OmrPageConstants.timingMarkStartY;
    const endY = OmrPageConstants.timingMarkEndY;
    const spacing = OmrPageConstants.timingMarkSpacing;
    const edgeInset = 6.0;
    const tickLen = 11.0;

    final guidePaint = Paint()
      ..color = basePaint.color.withValues(alpha: 0.75)
      ..strokeWidth = basePaint.strokeWidth * 0.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    var x = startX;
    while (x <= endX + 0.5) {
      final fx = size.width * (x / pageW);
      canvas.drawLine(
        Offset(fx, edgeInset),
        Offset(fx, edgeInset + tickLen),
        guidePaint,
      );
      canvas.drawLine(
        Offset(fx, size.height - edgeInset),
        Offset(fx, size.height - edgeInset - tickLen),
        guidePaint,
      );
      x += spacing;
    }

    var y = startY;
    while (y <= endY + 0.5) {
      final fy = size.height * (y / pageH);
      canvas.drawLine(
        Offset(edgeInset, fy),
        Offset(edgeInset + tickLen, fy),
        guidePaint,
      );
      canvas.drawLine(
        Offset(size.width - edgeInset, fy),
        Offset(size.width - edgeInset - tickLen, fy),
        guidePaint,
      );
      y += spacing;
    }
  }

  void _drawCorners(Canvas canvas, Size size, Paint paint) {
    void drawCorner({
      required Offset origin,
      required double dx,
      required double dy,
    }) {
      final path = Path()
        ..moveTo(origin.dx, origin.dy + dy * bracketLength)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + dx * bracketLength, origin.dy);
      canvas.drawPath(path, paint);
    }

    drawCorner(origin: Offset.zero, dx: 1, dy: 1);
    drawCorner(origin: Offset(size.width, 0), dx: -1, dy: 1);
    drawCorner(origin: Offset(0, size.height), dx: 1, dy: -1);
    drawCorner(origin: Offset(size.width, size.height), dx: -1, dy: -1);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.bracketLength != bracketLength ||
        oldDelegate.showGlow != showGlow ||
        oldDelegate.showEdgeGuides != showEdgeGuides;
  }
}

/// Helper class for quality analysis results
class _QualityAnalysis {
  final double brightness;
  final double sharpness;
  final bool isGood;
  final String hint;
  final IconData icon;
  final Color color;

  _QualityAnalysis({
    required this.brightness,
    required this.sharpness,
    required this.isGood,
    required this.hint,
    required this.icon,
    required this.color,
  });
}

class _ScanSafetyAssessment {
  const _ScanSafetyAssessment({
    required this.reviewReasons,
    required this.flaggedQuestions,
  });

  factory _ScanSafetyAssessment.safe() {
    return const _ScanSafetyAssessment(
      reviewReasons: <String>[],
      flaggedQuestions: <int>[],
    );
  }

  final List<String> reviewReasons;
  final List<int> flaggedQuestions;

  bool get requiresReview => reviewReasons.isNotEmpty;

  _ScanSafetyAssessment withAdditionalReason(String reason) {
    final reasons = <String>{
      ...reviewReasons,
      reason,
    }.toList();
    return _ScanSafetyAssessment(
      reviewReasons: reasons,
      flaggedQuestions: flaggedQuestions,
    );
  }
}

class _ScanPersistenceException implements Exception {
  const _ScanPersistenceException(this.cause);

  final Object cause;

  @override
  String toString() => 'ScanPersistenceException($cause)';
}
