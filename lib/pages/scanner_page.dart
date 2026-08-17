import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
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
import 'package:omr_app/utils/omr_scan_diagnostics.dart';
import 'package:omr_app/utils/omr_scan_failure_message.dart';
import 'package:omr_app/services/scanner_preferences_service.dart';
import 'package:omr_app/services/native_scanner_camera.dart';
import 'package:omr_app/services/scanner_engine.dart';
import 'package:omr_app/services/scanner_camera.dart';
import 'package:omr_app/services/scanner_camera_factory.dart';
import 'package:omr_app/services/scanner_session_layout.dart';
import 'package:omr_app/services/device_scan_tier.dart';
import 'package:omr_app/services/device_scan_capability.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/utils/scan_sheet_identity.dart';
import 'package:omr_app/utils/scan_lighting_guard.dart';
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

  bool _examTurboMode = true;
  bool _cameraBindFailed = false;

  String? get _displayStatusHint {
    if (_isProcessing) {
      return null;
    }
    if (_opencvLoadFailed) {
      return 'Tap Retry below, or close and reopen the scanner';
    }
    if (!_opencvAvailable) {
      return 'Loading the grading engine — capture unlocks when ready';
    }
    if (_cameraBindFailed) {
      return 'Tap Retry to restart the camera';
    }
    if (_scannerCamera != null &&
        _scannerCamera!.isInitialized &&
        !_scannerCamera!.isCaptureReady) {
      return 'Wait until the capture button turns green';
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
    final lightingHint = ScanLightingGuard.overlayHint(
      _lightingLevel,
      torchOn: _torchEnabled,
    );
    if (lightingHint != null && _lightingLevel == ScanLightingLevel.dim) {
      return lightingHint;
    }
    return null;
  }

  bool get _showFrameGlow =>
      !_isProcessing && _isContinuousMode && _sheetDetected && _sheetAligned;

  ScannerCamera? _scannerCamera;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _status = "Align Answer Sheet";
  bool _opencvAvailable = ScannerEngine.isReady;
  bool _opencvLoadFailed = false;
  bool _engineRetryInFlight = false;
  Timer? _openCvPollTimer;
  final List<ScanResult> _batchResults = [];

  // Device capability — primed at app launch via [DeviceScanCapability].
  bool _isLowEndDevice = DeviceScanCapability.isConstrained;
  DeviceScanTier _scanTier = DeviceScanCapability.tier;

  // Review mode - show answers for correction before saving
  bool _reviewBeforeSave = true;

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
  late final ScannerSessionLayout _sessionLayout;

  // Live lighting feedback + torch
  Timer? _lightingMonitorTimer;
  ScanLightingLevel _lightingLevel = ScanLightingLevel.good;
  bool _torchEnabled = false;

  // Stability thresholds — turbo mode captures sooner when sheet is aligned.
  int get _requiredStableFrames {
    if (_examTurboMode) {
      return _sheetAligned ? 2 : (_isLowEndDevice ? 3 : 3);
    }
    return _isLowEndDevice ? 5 : 8;
  }

  Duration get _scanCooldown => _examTurboMode
      ? (_isLowEndDevice
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 600))
      : (_isLowEndDevice
          ? const Duration(milliseconds: 2200)
          : const Duration(milliseconds: 1500));

  Duration get _continuousPollInterval => _examTurboMode
      ? (_isLowEndDevice
          ? const Duration(milliseconds: 400)
          : const Duration(milliseconds: 250))
      : (_isLowEndDevice
          ? const Duration(milliseconds: 650)
          : const Duration(milliseconds: 300));
  static const Duration _resultDisplayDuration = Duration(seconds: 2);

  bool get _isMobileNative => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// On Android, real scans are expected — do not steer users toward fake demo data.
  bool get _offerDemoMode => kIsWeb || (!Platform.isAndroid && !Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _opencvAvailable = ScannerEngine.isReady;
    _sessionLayout = ScannerSessionLayout.fromSubject(widget.targetSubject);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadScannerPreferences());
    unawaited(_bootstrapScannerEngine());
    unawaited(_detectCapabilitiesThenInitCamera());
  }

  Future<void> _detectCapabilitiesThenInitCamera() async {
    await _detectDeviceCapabilities();
    if (!mounted) return;
    await _initCamera();
  }

  Future<void> _loadScannerPreferences() async {
    final turbo = await ScannerPreferencesService.getExamTurboMode();
    if (mounted) {
      setState(() => _examTurboMode = turbo);
    }
  }

  Future<void> _bootstrapScannerEngine({bool forceRetry = false}) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _opencvLoadFailed = false;
      if (!_opencvAvailable) {
        _status = 'Loading scan engine…';
      }
    });

    final ready = forceRetry
        ? await ScannerEngine.retryLoad()
        : await ScannerEngine.warmUp(
            timeout: const Duration(seconds: 60),
          );
    if (!mounted) {
      return;
    }
    if (ready) {
      setState(() {
        _opencvAvailable = true;
        _opencvLoadFailed = false;
        if (_status == 'Loading scan engine…' ||
            _status == 'Scanner engine failed to load') {
          _status = 'Ready to scan...';
        }
      });
      _openCvPollTimer?.cancel();
      _resumeContinuousPollingIfNeeded();
      debugPrint('SCAN_ENGINE ready=true');
      return;
    }

    debugPrint(
      'SCAN_ENGINE warmUp failed; error=${ScannerEngine.lastError}',
    );
    _startOpenCvReadyPolling();
  }

  void _markOpenCvFailed() {
    if (!mounted || _opencvAvailable) {
      return;
    }
    unawaited(ScannerEngine.fetchInitError());
    setState(() {
      _opencvLoadFailed = true;
      _status = 'Scanner engine failed to load';
    });
  }

  void _startOpenCvReadyPolling() {
    _openCvPollTimer?.cancel();
    var ticks = 0;
    var checkInFlight = false;
    // Fail visibly after ~20s of background wait (warmUp already waited).
    const failAfterTicks = 8;

    _openCvPollTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_opencvAvailable || checkInFlight || _engineRetryInFlight) {
        return;
      }
      ticks++;
      checkInFlight = true;
      try {
        final ready = await ScannerEngine.checkReady();
        if (!mounted) {
          return;
        }
        if (ready) {
          timer.cancel();
          setState(() {
            _opencvAvailable = true;
            _opencvLoadFailed = false;
            _status = 'Ready to scan...';
          });
          _resumeContinuousPollingIfNeeded();
          return;
        }

        // Occasional ensureReady while background job may still be loading.
        if (ticks == 3 || ticks == 6) {
          final recovered = await ScannerEngine.warmUp(
            timeout: const Duration(seconds: 20),
          );
          if (!mounted) {
            return;
          }
          if (recovered) {
            timer.cancel();
            setState(() {
              _opencvAvailable = true;
              _opencvLoadFailed = false;
              _status = 'Ready to scan...';
            });
            _resumeContinuousPollingIfNeeded();
            return;
          }
        }

        if (ticks >= failAfterTicks) {
          timer.cancel();
          _markOpenCvFailed();
        }
      } finally {
        checkInFlight = false;
      }
    });
  }

  Future<void> _retryScannerEngine() async {
    if (_engineRetryInFlight) {
      return;
    }
    _engineRetryInFlight = true;
    _openCvPollTimer?.cancel();
    try {
      if (mounted) {
        setState(() {
          _opencvLoadFailed = false;
          _opencvAvailable = false;
          _status = 'Loading scan engine…';
        });
      }
      await _bootstrapScannerEngine(forceRetry: true);
      if (mounted && !_opencvAvailable) {
        _markOpenCvFailed();
      }
    } finally {
      _engineRetryInFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openCvPollTimer?.cancel();
    _stopContinuousScanning();
    _stopLightingMonitor();
    unawaited(_turnOffTorchIfNeeded());
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
    _stopLightingMonitor();
    unawaited(_turnOffTorchIfNeeded());
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
      setState(() {
        _opencvAvailable = true;
        _opencvLoadFailed = false;
      });
    }
    _resumeContinuousPollingIfNeeded();
  }

  /// Prefer launch-time cache; refresh once if warm-up had not finished yet.
  Future<void> _detectDeviceCapabilities() async {
    if (!DeviceScanCapability.isWarmed) {
      await DeviceScanCapability.warmUp();
    }
    if (!mounted) return;

    final remaining = DeviceScanCapability.remainingMemoryMB ?? 100;
    setState(() {
      _scanTier = DeviceScanCapability.tier;
      _isLowEndDevice =
          DeviceScanCapability.isConstrained || remaining < 80;
    });

    debugPrint(
      'Device: tier=${_scanTier.name} heapClassMb=${DeviceScanCapability.heapClassMb} '
      'remaining=${remaining}MB lowEnd=$_isLowEndDevice '
      'capture=${DeviceScanCapability.captureWidth}x${DeviceScanCapability.captureHeight}',
    );
  }

  Future<void> _applyFocusAtPoint(Offset normalizedPoint) async {
    await _scannerCamera?.setFocusPoint(normalizedPoint);
  }

  Future<void> _prepareCaptureFocus() async {
    await _scannerCamera?.prepareCaptureFocus(_preCaptureFocusDelay);
  }

  Future<void> _handlePreviewTap(
      TapDownDetails details, Size previewSize) async {
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
    var attempts = 0;
    while (mounted && attempts < 6) {
      attempts++;
      if (_opencvAvailable || ScannerEngine.isReady) {
        if (!_opencvAvailable && mounted) {
          setState(() {
            _opencvAvailable = true;
            _opencvLoadFailed = false;
          });
        }
        return true;
      }

      final synced = await ScannerEngine.checkReady();
      if (synced && mounted) {
        setState(() {
          _opencvAvailable = true;
          _opencvLoadFailed = false;
        });
        return true;
      }

      final ready = forceRetry
          ? await ScannerEngine.retryLoad(
              timeout: const Duration(seconds: 45),
            )
          : await ScannerEngine.warmUp(
              timeout: const Duration(seconds: 45),
            );
      forceRetry = false;
      if (ready && mounted) {
        setState(() {
          _opencvAvailable = true;
          _opencvLoadFailed = false;
        });
        _openCvPollTimer?.cancel();
        _resumeContinuousPollingIfNeeded();
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (mounted && !_opencvAvailable) {
      _markOpenCvFailed();
    }
    return false;
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
    if (s.contains('OPENCV_NOT_READY') || s.contains('OpenCV not available')) {
      return 'Reading sheet…';
    }
    final friendly = UserErrorMessages.friendlyError(error);
    if (friendly != 'Something went wrong. Try again.') {
      return friendly;
    }
    return 'Something went wrong while reading the sheet. Check lighting, hold steady, and try again.';
  }

  String get _displayStatusLine {
    if (_opencvLoadFailed && !_isProcessing) {
      return 'Scanner engine failed to load';
    }
    if (!_opencvAvailable && !_isProcessing) {
      return 'Preparing scanner…';
    }
    if (_isProcessing) {
      return _status;
    }
    if (_cameraBindFailed) {
      return 'Camera failed — tap to retry';
    }
    if (_scannerCamera != null &&
        _scannerCamera!.isInitialized &&
        !_scannerCamera!.isCaptureReady) {
      return 'Starting camera…';
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
    if (_isContinuousMode &&
        _sheetDetected &&
        _sheetAligned &&
        !_isProcessing) {
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
        if (_scannerCamera?.torchSupported ?? false)
          IconButton(
            onPressed: _isProcessing ? null : () => unawaited(_toggleTorch()),
            icon: Icon(
              _torchEnabled
                  ? Icons.flashlight_on_rounded
                  : Icons.flashlight_off_outlined,
              color: _torchEnabled ? AppColors.cautionAccent : Colors.white,
            ),
            tooltip: _torchEnabled ? 'Turn off light' : 'Turn on light',
          ),
        IconButton(
          onPressed: _showScannerSettingsSheet,
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Scanner settings',
        ),
      ],
    );
  }

  void _showScannerSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return SafeArea(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
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
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Exam turbo mode',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandText,
                          ),
                        ),
                        subtitle: const Text(
                          'Faster scanning on exam day. Turn off when troubleshooting corner detection.',
                          style: TextStyle(color: AppColors.brandMuted, fontSize: 12),
                        ),
                        value: _examTurboMode,
                        activeThumbColor: AppColors.brandGreen,
                        onChanged: _isProcessing
                            ? null
                            : (value) async {
                                setState(() => _examTurboMode = value);
                                await ScannerPreferencesService.setExamTurboMode(
                                  value,
                                );
                              },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomBar(ColorScheme colorScheme) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final cameraReady = _scannerCamera?.isCaptureReady ?? false;
    final captureReady =
        !_isProcessing && cameraReady && _opencvAvailable;
    final showEngineRetry =
        _opencvLoadFailed && !_isProcessing && !_engineRetryInFlight;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + bottomInset,
      child: GestureDetector(
        onTap: _isProcessing
            ? null
            : _cameraBindFailed
                ? () => unawaited(_initCamera())
                : showEngineRetry
                    ? () => unawaited(_retryScannerEngine())
                    : null,
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
                  const SizedBox(width: 12),
                  if (showEngineRetry)
                    FilledButton(
                      onPressed: () => unawaited(_retryScannerEngine()),
                      style: FilledButton.styleFrom(
                        backgroundColor: _scannerAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Retry'),
                    )
                  else
                    _buildCaptureButton(
                      colorScheme: colorScheme,
                      captureReady: captureReady,
                    ),
                ],
              ),
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
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
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
                  'On phones with less memory, close other apps before scanning so grading stays reliable.',
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
    _resumeLightingMonitorIfNeeded();
    _showAndroidStyleFailureDialog(
      title: 'Could not save scan',
      message: UserErrorMessages.friendlySaveError(detail),
      debugDetail: detail.toString(),
    );
  }

  bool _isEngineNotReadyFailure(OmrScanResult result) {
    final platformError = result.debugInfo['platformError']?.toString();
    if (platformError == 'OPENCV_NOT_READY') {
      return true;
    }
    return result.debugInfo['failureReason']?.toString() == 'ENGINE_NOT_READY';
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
    if (!_isInitialized ||
        _scannerCamera == null ||
        _isStreamingFrames ||
        !_opencvAvailable) {
      return;
    }

    setState(() {
      _isStreamingFrames = true;
      _status = "Auto-scan active - position sheet";
      _stableFrameCount = 0;
      _sheetDetected = false;
      _sheetAligned = false;
    });

    _stopLightingMonitor();

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
      if (!_isContinuousMode) {
        _resumeLightingMonitorIfNeeded();
      }
    }
  }

  void _resumeContinuousPollingIfNeeded() {
    if (!_isContinuousMode ||
        !_isInitialized ||
        _scannerCamera == null ||
        !_scannerCamera!.isCaptureReady ||
        !_opencvAvailable ||
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
        !_scannerCamera!.isCaptureReady ||
        !_opencvAvailable) {
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
      await _updateLightingLevelFromBytes(bytes);

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
          await _triggerAutoCapture(bytes);
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
            hint = ScanLightingGuard.overlayHint(
                  _lightingLevel,
                  torchOn: _torchEnabled,
                ) ??
                "Improve lighting";
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

    if (await _blockIfCaptureTooDark(bytes, showDialog: false)) {
      _stableFrameCount = 0;
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "Processing...";
    });

    try {
      // Optimize image if needed
      var processBytes = bytes;
      if (_isLowEndDevice ||
          bytes.length >
              (_examTurboMode ? 2 * 1024 * 1024 : 1024 * 1024)) {
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
        totalQuestions: _sessionLayout.totalQuestions,
        sessionLayout: _sessionLayout.toNativeMap(),
        turboMode: _examTurboMode,
      );

      if (!omrResult.success || omrResult.omrId == null) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = OmrScanFailureMessage.from(
              errorMessage: omrResult.errorMessage,
              debugInfo: omrResult.debugInfo,
            ).title;
          });
          await _handleFailedOmrResult(
            omrResult,
            sourceBytes: processBytes,
          );
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

      // Sheet QR supplies sheet id and validation only — grading stays on targetSubject.
      final subject = widget.targetSubject;
      String? sheetId;
      SubjectSheetQrPayload? qrPayload;

      if (omrResult.qrData != null) {
        qrPayload = _qrPayloadFromOmrResult(omrResult);
        sheetId = qrPayload?.sheetId;
      }

      if (!await _passesScanIdentityChecks(
        omrResult: omrResult,
        student: student,
        qrPayload: qrPayload,
      )) {
        return;
      }

      final scanSafety = _assessScanSafety(
        omrResult: omrResult,
        student: student,
        subject: subject,
        sheetId: sheetId,
        qrPayload: qrPayload,
      );

      // Check for existing scan
      final existingScan = _findExistingScan(student, subject);
      if (existingScan != null) {
        final duplicateSafety = scanSafety.withAdditionalReason(
          'Rescan detected for an already-scanned student and subject.',
        );
        await _recordScanContinuous(
          student: student,
          subject: subject,
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
        subject: subject,
        answers: omrResult.answers,
        confidence: omrResult.confidence,
        sheetId: sheetId,
        scanSafety: _effectiveScanSafety(
          scanSafety,
          turboAutoSave: _canTurboAutoSave(
            safety: scanSafety,
            omrResult: omrResult,
            subject: subject,
          ),
        ),
        sourceBytes: processBytes,
        processingMs: omrResult.debugInfo['processingTimeMs'] is num
            ? (omrResult.debugInfo['processingTimeMs'] as num).toInt()
            : null,
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
      final resized =
          decoded.width > 1000 ? img.copyResize(decoded, width: 1000) : decoded;
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
    int? processingMs,
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
      final timingSuffix = processingMs != null ? ' · ${processingMs}ms' : '';
      setState(() {
        _isProcessing = false;
        _status = pendingReview
            ? '${student.name}: queued for review'
            : "✓ ${student.name}: $scoreDisplay$timingSuffix";
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

  // ==================== LIGHTING + TORCH ====================

  String? get _lightingOverlayHint {
    if (_isProcessing) {
      return null;
    }
    return ScanLightingGuard.overlayHint(
      _lightingLevel,
      torchOn: _torchEnabled,
    );
  }

  Future<void> _toggleTorch() async {
    final camera = _scannerCamera;
    if (camera == null || !camera.torchSupported || _isProcessing) {
      return;
    }
    try {
      final enabled = await camera.toggleTorch();
      if (!mounted) return;
      setState(() => _torchEnabled = enabled);
    } catch (error) {
      debugPrint('Torch toggle failed: $error');
    }
  }

  Future<void> _turnOffTorchIfNeeded() async {
    final camera = _scannerCamera;
    if (camera == null || !camera.torchEnabled) {
      return;
    }
    try {
      await camera.setTorchEnabled(false);
    } catch (error) {
      debugPrint('Torch off failed: $error');
    }
    _torchEnabled = false;
  }

  void _syncTorchStateFromCamera() {
    final camera = _scannerCamera;
    if (camera == null) {
      return;
    }
    _torchEnabled = camera.torchEnabled;
  }

  void _startLightingMonitor() {
    if (_lightingMonitorTimer != null || _isContinuousMode) {
      return;
    }

    final interval = _isLowEndDevice
        ? const Duration(milliseconds: 2200)
        : const Duration(milliseconds: 1600);
    _lightingMonitorTimer = Timer.periodic(
      interval,
      (_) => unawaited(_pollLightingLevel()),
    );
  }

  void _stopLightingMonitor() {
    _lightingMonitorTimer?.cancel();
    _lightingMonitorTimer = null;
  }

  void _resumeLightingMonitorIfNeeded() {
    if (!_isContinuousMode && _lightingMonitorTimer == null && mounted) {
      _startLightingMonitor();
    }
  }

  Future<void> _pollLightingLevel() async {
    if (!mounted ||
        !_isInitialized ||
        _isProcessing ||
        _isCheckingFrame ||
        _isContinuousMode) {
      return;
    }

    final camera = _scannerCamera;
    if (camera == null || !camera.isCaptureReady) {
      return;
    }

    try {
      final bytes = await camera.capture();
      await _updateLightingLevelFromBytes(bytes);
    } catch (error) {
      debugPrint('Lighting monitor error: $error');
    }
  }

  Future<ScanLightingLevel> _lightingLevelFromBytes(Uint8List bytes) async {
    try {
      final result = await OpenCVBridge.analyzeImageQuality(bytes);
      if (result != null) {
        final brightness = (result['brightness'] as num?)?.toDouble() ?? 0.5;
        return ScanLightingGuard.levelFromNormalizedBrightness(brightness);
      }
    } catch (error) {
      debugPrint('Lighting analysis failed: $error');
    }
    return ScanLightingLevel.good;
  }

  Future<void> _updateLightingLevelFromBytes(Uint8List bytes) async {
    final level = await _lightingLevelFromBytes(bytes);
    if (!mounted || level == _lightingLevel) {
      return;
    }
    setState(() => _lightingLevel = level);
  }

  /// Returns true when capture must be blocked (too dark).
  Future<bool> _blockIfCaptureTooDark(
    Uint8List bytes, {
    required bool showDialog,
  }) async {
    final level = await _lightingLevelFromBytes(bytes);
    if (!mounted) {
      return true;
    }

    setState(() => _lightingLevel = level);
    if (level != ScanLightingLevel.tooDark) {
      return false;
    }

    setState(() {
      _isProcessing = false;
      _status = 'Too dark to scan';
    });

    if (showDialog) {
      _showScanError(
        ScanLightingGuard.hardBlockMessage(torchOn: _torchEnabled),
        debugInfo: const {'failureReason': 'TOO_DARK'},
      );
    } else if (_isContinuousMode) {
      final hint = ScanLightingGuard.overlayHint(level, torchOn: _torchEnabled);
      setState(() {
        _status = hint ?? 'Too dark to scan';
        _continuousHint = _status;
      });
    }

    _resumeLightingMonitorIfNeeded();
    return true;
  }

  // ==================== END LIGHTING + TORCH ====================

  Future<void> _handleNativeCameraBindFailed(String message) async {
    debugPrint('Native camera bind failed: $message');
    if (!mounted) {
      return;
    }
    setState(() {
      _isInitialized = false;
      _cameraInitFailed = true;
      _cameraBindFailed = true;
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
        _cameraBindFailed = false;
      });
    }

    try {
      _scannerCamera = await ScannerCameraFactory.create(
        cameras: widget.availableCameras,
        scanTier: _scanTier,
      );
      if (_scannerCamera is NativeScannerCamera) {
        final native = _scannerCamera as NativeScannerCamera;
        native.onViewReady = () {
          if (mounted) {
            setState(() {
              _syncTorchStateFromCamera();
            });
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
          _cameraBindFailed = false;
        });
        _startLightingMonitor();
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
            'Camera could not start. Tap Retry.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => unawaited(_initCamera()),
          ),
        ),
      );
    }
  }

  /// Compress and optimize image for processing (runs in isolate for UI responsiveness)
  Future<Uint8List> _optimizeImageForProcessing(Uint8List bytes) async {
    if (bytes.length < _scanTier.dartOptimizeMinBytes) {
      return bytes;
    }

    debugPrint(
      'Optimizing image: ${bytes.length ~/ 1024}KB tier=${_scanTier.name}',
    );

    try {
      final optimized = await compute(
        _compressImageIsolate,
        _CompressArgs(
          bytes: bytes,
          maxDim: _scanTier.dartOptimizeMaxDimension,
          quality: _scanTier.dartJpegQuality,
        ),
      );
      debugPrint("Optimized to: ${optimized.length ~/ 1024}KB");
      return optimized;
    } catch (e) {
      debugPrint("Image optimization failed: $e");
      return bytes;
    }
  }

  /// Static function for isolate - compresses image
  static Uint8List _compressImageIsolate(_CompressArgs args) {
    final image = img.decodeImage(args.bytes);
    if (image == null) return args.bytes;

    final maxDim = args.maxDim;
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

    return Uint8List.fromList(img.encodeJpg(resized, quality: args.quality));
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

      if (_isLowEndDevice ||
          bytes.length >
              (_examTurboMode ? 2 * 1024 * 1024 : 1024 * 1024)) {
        setState(() => _status = 'Optimizing...');
        bytes = await _optimizeImageForProcessing(bytes);
      }

      if (!_opencvAvailable) {
        setState(() => _status = 'Preparing scanner…');
      }

      final engineReady = await _waitForOpenCvReady(forceRetry: true);
      if (!engineReady) {
        return;
      }

      if (mounted) {
        setState(() => _status = 'Reading sheet…');
      }

      OmrScanResult omrResult = await OpenCVBridge.processOmr(
        bytes,
        totalQuestions: _sessionLayout.totalQuestions,
        sessionLayout: _sessionLayout.toNativeMap(),
        turboMode: _examTurboMode,
      );

      for (var attempt = 0;
          attempt < 3 && !omrResult.success && _isEngineNotReadyFailure(omrResult);
          attempt++) {
        if (mounted) {
          setState(() => _status = 'Reading sheet…');
        }
        await _waitForOpenCvReady(forceRetry: true);
        if (!mounted) {
          return;
        }
        omrResult = await OpenCVBridge.processOmr(
          bytes,
          totalQuestions: _sessionLayout.totalQuestions,
          sessionLayout: _sessionLayout.toNativeMap(),
          turboMode: _examTurboMode,
        );
      }

      debugPrint('OMR Result: $omrResult');
      final processingMs = omrResult.debugInfo['processingTimeMs'];

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
          setState(() {
            _isProcessing = false;
            _status = OmrScanFailureMessage.from(
              errorMessage: omrResult.errorMessage,
              debugInfo: omrResult.debugInfo,
            ).title;
          });
          await _handleFailedOmrResult(
            omrResult,
            sourceBytes: bytes,
          );
        }
        return;
      }

      if (omrResult.omrId == null) {
        if (mounted) {
          setState(() {
            _status = 'Could not read OMR ID';
            _isProcessing = false;
          });
          await _handleFailedOmrResult(
            omrResult,
            sourceBytes: bytes,
          );
        }
        return;
      }

      await _finishScanWithOmrId(
        omrResult: omrResult,
        omrId: omrResult.omrId!,
        sourceBytes: bytes,
        processingMs: processingMs is num ? processingMs.toInt() : null,
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
      _resumeLightingMonitorIfNeeded();
    }
  }

  Future<void> _captureAndProcess() async {
    if (_isProcessing ||
        _scannerCamera == null ||
        !_scannerCamera!.isCaptureReady) {
      return;
    }

    if (!await _waitForAutoFrameCheckToFinish()) {
      if (mounted && !_isProcessing) {
        setState(() => _status = 'Try capture again');
      }
      return;
    }

    if (_isProcessing ||
        _scannerCamera == null ||
        !_scannerCamera!.isCaptureReady) {
      return;
    }

    _stopLightingMonitor();

    setState(() {
      _isProcessing = true;
      _status = 'Capturing...';
    });

    try {
      await _prepareCaptureFocus();
      final bytes = await _scannerCamera!.capture();
      if (await _blockIfCaptureTooDark(bytes, showDialog: true)) {
        return;
      }
      await _processCapturedBytes(bytes);
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Capture failed — try again';
        });
        _resumeLightingMonitorIfNeeded();
      }
    }
  }

  Future<bool> _waitForAutoFrameCheckToFinish() async {
    if (!_isCheckingFrame) {
      return true;
    }

    if (mounted && !_isProcessing) {
      setState(() => _status = 'Finishing auto-check...');
    }

    for (var attempt = 0; attempt < 12; attempt++) {
      if (!_isCheckingFrame) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || _isProcessing) {
        return false;
      }
    }

    return !_isCheckingFrame;
  }

  SubjectSheetQrPayload? _qrPayloadFromOmrResult(OmrScanResult omrResult) {
    final raw = omrResult.qrData;
    if (raw == null) {
      return null;
    }
    return _parseQrPayload(raw);
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
              const Text(
                'Session progress',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_sessionScannedCount of ${roster.length} scanned for ${widget.targetSubject.name}',
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

    if (debugInfo['omrIdNeedsReview'] == true) {
      final ambiguousColumn = _readDebugInt(debugInfo, 'omrIdAmbiguousColumn');
      reasons.add(
        'OMR ID digit ${ambiguousColumn + 1} was unclear — verify the 4-digit ID.',
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

    if (omrResult.qrData == null && debugInfo['layoutFromSession'] != true) {
      reasons.add('Template QR was not found.');
    } else if (qrPayload == null && omrResult.qrData != null) {
      reasons.add('Template QR could not be read.');
    } else if (qrPayload != null) {
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
              _normalizeScanSection(student.section) &&
          _assignedScanSections.contains(_normalizeScanSection(qrSection)) &&
          _assignedScanSections.contains(_normalizeScanSection(student.section))) {
        reasons.add(
          'Section mismatch — Paper: $qrSection · Student: ${student.section}. '
          'Match each student\'s sheet to their section next time for faster grading.',
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

    final ambiguousQuestions = _readDebugIntList(debugInfo, 'ambiguousQuestions')
        .where((question) => question >= 1 && question <= subject.totalQuestions)
        .toList()
      ..sort();
    final ambiguousSet = ambiguousQuestions.toSet();

    final multipleMarks = _readDebugInt(debugInfo, 'multipleSelectionsLayout') +
        _readDebugInt(debugInfo, 'multipleSelections');
    if (multipleMarks > 0) {
      reasons.add(
        multipleMarks == 1
            ? '1 question has more than one mark — left blank; tap to choose the answer.'
            : '$multipleMarks questions have more than one mark — left blank; tap flagged cells to choose.',
      );
    }

    if (ambiguousQuestions.isNotEmpty) {
      reasons.add(
        ambiguousQuestions.length == 1
            ? 'Q${ambiguousQuestions.first} needs your choice (crossed-out or double mark).'
            : '${ambiguousQuestions.length} questions need your choice '
                '(e.g. Q${ambiguousQuestions.take(5).join(', Q')}'
                '${ambiguousQuestions.length > 5 ? '…' : ''}).',
      );
      flaggedQuestions.addAll(ambiguousQuestions);
    }

    final lightMarkQuestions = _readDebugIntList(debugInfo, 'lightMarkQuestions')
        .where((question) => question >= 1 && question <= subject.totalQuestions)
        .toList()
      ..sort();
    if (lightMarkQuestions.isNotEmpty) {
      reasons.add(
        lightMarkQuestions.length == 1
            ? 'Q${lightMarkQuestions.first} looks lightly marked — confirm it is intentional.'
            : '${lightMarkQuestions.length} answers look lightly marked '
                '(e.g. Q${lightMarkQuestions.take(5).join(', Q')}'
                '${lightMarkQuestions.length > 5 ? '…' : ''}) — confirm they are intentional.',
      );
      flaggedQuestions.addAll(lightMarkQuestions);
    }

    final scratchRejected = _readDebugIntList(debugInfo, 'scratchRejectedQuestions')
        .where((question) => question >= 1 && question <= subject.totalQuestions)
        .length;
    if (scratchRejected > 0) {
      reasons.add(
        scratchRejected == 1
            ? '1 faint scratch was ignored (not counted as an answer).'
            : '$scratchRejected faint scratches were ignored (not counted as answers).',
      );
    }

    final weakWinnerRejected =
        _readDebugIntList(debugInfo, 'weakWinnerRejectedQuestions')
            .where((question) => question >= 1 && question <= subject.totalQuestions)
            .length;
    if (weakWinnerRejected > 0) {
      reasons.add(
        weakWinnerRejected == 1
            ? '1 uncertain mark was left blank (safer than guessing).'
            : '$weakWinnerRejected uncertain marks were left blank (safer than guessing).',
      );
    }

    final missingQuestions = <int>[
      for (int question = 1; question <= subject.totalQuestions; question++)
        if (!omrResult.answers.containsKey(question) &&
            !ambiguousSet.contains(question))
          question,
    ];
    final timingScore = (debugInfo['timingMarkScore'] as num?)?.toDouble();
    if (missingQuestions.isNotEmpty) {
      final blankCount = missingQuestions.length;
      final blankHeavy =
          blankCount >= 8 || blankCount >= (subject.totalQuestions * 0.25).round();
      final timingWeak = timingScore != null && timingScore < 0.75;
      final crumpleSuspect = debugInfo['crumpleSuspect'] == true;
      final gridLockApplied = debugInfo['gridLockApplied'] == true;
      if (blankHeavy && (timingWeak || crumpleSuspect || gridLockApplied)) {
        reasons.add(
          '$blankCount blanks with weak sheet alignment — page may be crumpled. '
          'Flatten under a book and rescan, or fill blanks in review.',
        );
      } else {
        reasons.add(
          blankCount == 1
              ? '1 question left blank.'
              : '$blankCount questions left blank.',
        );
      }
    }

    final layoutFromSession = debugInfo['layoutFromSession'] == true;
    final layoutFromQr = debugInfo['layoutFromQr'] == true;
    if (!layoutFromQr && !layoutFromSession) {
      reasons.add('Template layout could not be confirmed from QR.');
    }

    // --- Geometry / capture-health gating ---
    // Fail-safe: a scan may only auto-save when alignment and fill calibration are
    // healthy. Any doubt here becomes a review reason, which both blocks turbo
    // auto-save (_canTurboAutoSave) and forces the manual path into review — so an
    // uncertain warp or uncalibrated fill can never be recorded as a final grade.
    if (debugInfo['calibrationSuccess'] == false) {
      reasons.add(
        'Fill-darkness auto-calibration failed — verify the marked answers.',
      );
    }

    if (timingScore != null && timingScore < 0.75) {
      reasons.add(
        'Alignment marks only partly detected (${(timingScore * 100).round()}%) — verify sheet positioning.',
      );
    }

    if (debugInfo['templateMismatchWarning'] == true) {
      reasons.add(
        "Answer grid may not match this exam's template — verify the sheet.",
      );
    }

    if (debugInfo['cornerDetectionSucceededVia'] == 'edge') {
      reasons.add(
        'Corners located with a last-resort method — verify alignment.',
      );
    }

    return _ScanSafetyAssessment(
      reviewReasons: <String>{...reasons}.toList(),
      flaggedQuestions: flaggedQuestions.toList()..sort(),
    );
  }

  String _normalizeScanSection(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  List<String> get _assignedScanSections {
    return (widget.targetSubject.sectionNames ?? const <String>[])
        .map(_normalizeScanSection)
        .where((section) => section.isNotEmpty)
        .toList();
  }

  String _assignedSectionsLabel() {
    final sections = _assignedScanSections;
    if (sections.isEmpty) {
      return widget.targetSubject.displayName;
    }
    if (sections.length == 1) {
      return sections.first;
    }
    return sections.join(', ');
  }

  String? _wrongSubjectMessage(SubjectSheetQrPayload? qrPayload) {
    if (qrPayload == null) {
      return null;
    }

    final target = widget.targetSubject;
    final sheetSubject = qrPayload.resolveSubject();
    final sheetLabel = sheetSubject?.displayName ??
        (qrPayload.subjectName.trim().isEmpty
            ? 'another subject'
            : qrPayload.subjectName);

    if (qrPayload.subjectId.isNotEmpty && qrPayload.subjectId != target.id) {
      return 'This sheet is for $sheetLabel, but you opened the scanner for '
          '${target.displayName}. Print the correct subject\'s sheet or open '
          'that subject\'s answer key before scanning.';
    }

    if (sheetSubject != null && sheetSubject.id != target.id) {
      return 'This sheet is for ${sheetSubject.displayName}, but you opened '
          'the scanner for ${target.displayName}. Print the correct subject\'s '
          'sheet or open that subject\'s answer key before scanning.';
    }

    return null;
  }

  bool _blockIfWrongSubject({
    SubjectSheetQrPayload? qrPayload,
    Map<String, dynamic>? debugInfo,
  }) {
    final message = _wrongSubjectMessage(qrPayload);
    if (message == null) {
      return false;
    }
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = 'Wrong subject';
      });
      _showScanError(
        message,
        debugInfo: {
          ...?debugInfo,
          'failureReason': 'WRONG_SUBJECT',
          'scannerSubjectId': widget.targetSubject.id,
          if (qrPayload?.subjectId.isNotEmpty == true)
            'sheetSubjectId': qrPayload!.subjectId,
        },
      );
    }
    return true;
  }

  bool _blockIfForeignTeacherSheet({
    SubjectSheetQrPayload? qrPayload,
    Map<String, dynamic>? debugInfo,
  }) {
    final failure = ScanSheetIdentity.ownershipFailure(
      targetSubject: widget.targetSubject,
      qrPayload: qrPayload,
      currentUserId: ApiService.currentUserId,
      currentTeacherEmail:
          ApiService.currentEmail ?? LocalAuthService.instance.cachedTeacherEmail,
      currentTeacherName: LocalAuthService.instance.cachedTeacherName,
    );
    if (failure == null) {
      return false;
    }
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _status = switch (failure.failureReason) {
          'REPRINT_REQUIRED' => 'Reprint required',
          'QR_REQUIRED' => 'QR not readable',
          'FOREIGN_SHEET' => 'Not a COC sheet',
          _ => 'Not your sheet',
        };
      });
      _showScanError(
        failure.message,
        debugInfo: {
          ...?debugInfo,
          'failureReason': failure.failureReason,
          'scannerSubjectId': widget.targetSubject.id,
          if (qrPayload?.ownerTeacherId?.isNotEmpty == true)
            'sheetOwnerTeacherId': qrPayload!.ownerTeacherId,
          if (qrPayload?.subjectId.isNotEmpty == true)
            'sheetSubjectId': qrPayload!.subjectId,
        },
      );
    }
    return true;
  }

  String? _wrongExamSectionMessage({
    SubjectSheetQrPayload? qrPayload,
    Student? student,
  }) {
    final assigned = _assignedScanSections.toSet();
    if (assigned.isEmpty) {
      return null;
    }

    final qrSection = qrPayload?.sectionName?.trim();
    if (qrSection != null && qrSection.isNotEmpty) {
      final normalizedQrSection = _normalizeScanSection(qrSection);
      if (!assigned.contains(normalizedQrSection)) {
        return 'This sheet is for $qrSection, but you are grading '
            '${_assignedSectionsLabel()}. Print the sheet for the correct section '
            'or open the answer key for $qrSection.';
      }
    }

    if (student != null) {
      final studentSection = _normalizeScanSection(student.section);
      if (!assigned.contains(studentSection)) {
        return '${student.name} is in ${student.section}, which is not assigned to '
            '${widget.targetSubject.displayName}. You are grading '
            '${_assignedSectionsLabel()}.';
      }
    }

    return null;
  }

  _SheetStudentSectionMismatch? _sheetStudentSectionMismatch({
    SubjectSheetQrPayload? qrPayload,
    required Student student,
  }) {
    final assigned = _assignedScanSections.toSet();
    if (assigned.isEmpty) {
      return null;
    }

    final qrSection = qrPayload?.sectionName?.trim();
    if (qrSection == null || qrSection.isEmpty) {
      return null;
    }

    final normalizedQrSection = _normalizeScanSection(qrSection);
    final normalizedStudentSection = _normalizeScanSection(student.section);
    if (normalizedQrSection == normalizedStudentSection) {
      return null;
    }
    if (!assigned.contains(normalizedQrSection) ||
        !assigned.contains(normalizedStudentSection)) {
      return null;
    }

    return _SheetStudentSectionMismatch(
      sheetSection: qrSection,
      student: student,
    );
  }

  Future<bool> _confirmSheetStudentSectionMismatch(
    _SheetStudentSectionMismatch mismatch,
  ) async {
    if (!mounted) {
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Section mismatch'),
        content: Text(
          'This paper is for ${mismatch.sheetSection}.\n'
          'OMR ID ${mismatch.student.omrId} is ${mismatch.student.name} '
          '(${mismatch.student.section}).\n\n'
          'If this is correct, save for review. If not, discard and scan the '
          'right sheet.\n\n'
          'Tip: Match each student\'s sheet to their section next time — '
          'mixed papers add review and slow grading.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard & rescan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save for review'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _passesScanIdentityChecks({
    required OmrScanResult omrResult,
    required Student student,
    SubjectSheetQrPayload? qrPayload,
  }) async {
    if (_blockIfForeignTeacherSheet(
      qrPayload: qrPayload,
      debugInfo: omrResult.debugInfo,
    )) {
      return false;
    }

    if (_blockIfWrongSubject(
      qrPayload: qrPayload,
      debugInfo: omrResult.debugInfo,
    )) {
      return false;
    }

    final wrongExamSection = _wrongExamSectionMessage(
      qrPayload: qrPayload,
      student: student,
    );
    if (wrongExamSection != null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Wrong section';
        });
        _showScanError(
          wrongExamSection,
          debugInfo: {
            ...omrResult.debugInfo,
            'failureReason': 'WRONG_SECTION',
            if (qrPayload?.sectionName != null)
              'sheetSection': qrPayload!.sectionName,
            'assignedSections': widget.targetSubject.sectionNames,
          },
        );
      }
      return false;
    }

    final sectionMismatch = _sheetStudentSectionMismatch(
      qrPayload: qrPayload,
      student: student,
    );
    if (sectionMismatch != null) {
      final confirmed = await _confirmSheetStudentSectionMismatch(sectionMismatch);
      if (!confirmed) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = 'Discarded — section mismatch';
          });
        }
        return false;
      }
    }

    return true;
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
    Map<String, dynamic>? scanDebugInfo,
    bool turboAutoSave = false,
    int? processingMs,
  }) async {
    final safety = _effectiveScanSafety(
      scanSafety ?? _ScanSafetyAssessment.safe(),
      turboAutoSave: turboAutoSave,
    );

    // Risky scans are reviewed even when the optional review toggle is off.
    if ((_reviewBeforeSave && !skipReview && !turboAutoSave) ||
        safety.requiresReview) {
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
        scanDebugInfo: scanDebugInfo,
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
      processingMs: processingMs,
    );
  }

  bool _canTurboAutoSave({
    required _ScanSafetyAssessment safety,
    required OmrScanResult omrResult,
    required Subject subject,
  }) {
    if (!_examTurboMode) {
      return false;
    }
    if (omrResult.confidence < 0.80) {
      return false;
    }
    if (omrResult.answers.length < subject.totalQuestions) {
      return false;
    }
    if (safety.flaggedQuestions.isNotEmpty) {
      return false;
    }
    if (safety.reviewReasons.isNotEmpty) {
      return false;
    }
    return true;
  }

  _ScanSafetyAssessment _effectiveScanSafety(
    _ScanSafetyAssessment safety, {
    required bool turboAutoSave,
  }) {
    if (!turboAutoSave) {
      return safety;
    }
    return _ScanSafetyAssessment.safe();
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
    Map<String, dynamic>? scanDebugInfo,
  }) async {
    if (!mounted) return;

    final diagnostics =
        OmrScanDiagnostics.fromDebugInfo(scanDebugInfo).lines;

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
          scanDiagnostics: diagnostics,
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
      _resumeLightingMonitorIfNeeded();
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
    int? processingMs,
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
      final timingSuffix = processingMs != null ? ' · ${processingMs}ms' : '';
      setState(() {
        _isProcessing = false;
        _status = pendingReview
            ? "Queued for review: ${student.name}"
            : wasEdited
                ? "Saved (edited): ${updatedStudent.name}"
                : "Scanned: ${updatedStudent.name} - ${subject.displayName}$timingSuffix";
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
    Map<String, dynamic>? scanDebugInfo,
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
                  scanDebugInfo: scanDebugInfo,
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
    Map<String, dynamic>? scanDebugInfo,
  }) async {
    if (!mounted) return;

    final diagnostics =
        OmrScanDiagnostics.fromDebugInfo(scanDebugInfo).lines;

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
          scanDiagnostics: diagnostics,
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

  void _showScanError(String message, {Map<String, dynamic>? debugInfo}) {
    final failure = OmrScanFailureMessage.from(
      errorMessage: message,
      debugInfo: debugInfo,
    );
    _showScanErrorWithTips(failure, debugInfo: debugInfo);
  }

  Future<void> _handleFailedOmrResult(
    OmrScanResult omrResult, {
    Uint8List? sourceBytes,
  }) async {
    final failure = OmrScanFailureMessage.from(
      errorMessage: omrResult.errorMessage,
      debugInfo: omrResult.debugInfo,
    );
    final reason = omrResult.debugInfo['failureReason']?.toString();
    if (reason == 'OMR_ID') {
      final qrPayload = _qrPayloadFromOmrResult(omrResult);
      if (_blockIfForeignTeacherSheet(
        qrPayload: qrPayload,
        debugInfo: omrResult.debugInfo,
      )) {
        return;
      }

      final typedId = await _promptOmrIdRecovery(
        failure: failure,
        debugInfo: omrResult.debugInfo,
      );
      if (typedId != null && mounted) {
        await _finishScanWithOmrId(
          omrResult: omrResult,
          omrId: typedId,
          sourceBytes: sourceBytes,
          forceReview: true,
        );
        return;
      }
    }
    if (mounted) {
      _showScanErrorWithTips(failure, debugInfo: omrResult.debugInfo);
    }
  }

  Future<String?> _promptOmrIdRecovery({
    required OmrScanFailureMessage failure,
    required Map<String, dynamic> debugInfo,
  }) async {
    final guessedDigits = <String>[];
    for (var col = 0; col < 4; col++) {
      final raw = debugInfo['omrIdColumn$col'];
      if (raw is Map) {
        final best = raw['bestDigit'];
        if (best is num && best.toInt() >= 0) {
          guessedDigits.add('${best.toInt()}');
          continue;
        }
      }
      guessedDigits.add('');
    }
    final guessed = guessedDigits.every((d) => d.isNotEmpty)
        ? guessedDigits.join()
        : '';
    final controller = TextEditingController(text: guessed);
    final answered = (debugInfo['answersDetected'] as num?)?.toInt();
    final blank = (debugInfo['blankAnswersCount'] as num?)?.toInt();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(failure.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(failure.message),
                if (answered != null || blank != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Answers found: ${answered ?? '?'} · Blank: ${blank ?? '?'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  failure.helpTip,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Type 4-digit OMR ID',
                    counterText: '',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('TRY AGAIN'),
            ),
            TextButton(
              onPressed: () {
                final typed = controller.text.trim();
                if (typed.length != 4) {
                  return;
                }
                Navigator.pop(context, typed);
              },
              child: const Text('USE THIS ID'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _finishScanWithOmrId({
    required OmrScanResult omrResult,
    required String omrId,
    Uint8List? sourceBytes,
    int? processingMs,
    bool forceReview = false,
  }) async {
    final student = _resolveStudentFromOmrId(omrId);
    if (student == null) {
      if (mounted) {
        setState(() {
          _status = 'Student not found: $omrId';
          _isProcessing = false;
        });
        _showScanError("OMR ID '$omrId' does not match any imported student.");
      }
      return;
    }

    String? sheetId;
    SubjectSheetQrPayload? qrPayload;

    if (omrResult.qrData != null) {
      try {
        qrPayload = _qrPayloadFromOmrResult(omrResult);
        if (qrPayload != null) {
          if (!qrPayload.isCocIssued) {
            if (mounted) {
              setState(() {
                _status = 'Not a COC answer sheet';
                _isProcessing = false;
              });
              _showScanError(
                'This does not look like a COC OMR answer sheet. '
                'Print sheets from this app (Prepare → Print Sheets), then scan again.',
                debugInfo: {
                  ...omrResult.debugInfo,
                  'failureReason': 'FOREIGN_SHEET',
                },
              );
            }
            return;
          }
          sheetId = qrPayload.sheetId;
        }
      } catch (e) {
        debugPrint('QR parsing error: $e');
      }
    }

    if (!await _passesScanIdentityChecks(
      omrResult: omrResult,
      student: student,
      qrPayload: qrPayload,
    )) {
      return;
    }

    final subject = widget.targetSubject;
    var scanSafety = _assessScanSafety(
      omrResult: omrResult,
      student: student,
      subject: subject,
      sheetId: sheetId,
      qrPayload: qrPayload,
    );
    if (forceReview) {
      scanSafety = scanSafety.withAdditionalReason(
        'OMR ID was typed manually — verify the ID and blank answers before saving.',
      );
    }

    final existingScan = _findExistingScan(student, subject);
    if (existingScan != null) {
      if (mounted) {
        setState(() {
          _status = 'Already scanned: ${student.name}';
          _isProcessing = false;
        });
        _showRescanDialog(
          student: student,
          subject: subject,
          existingScan: existingScan,
          newAnswers: omrResult.answers,
          newConfidence: omrResult.confidence,
          sheetId: sheetId,
          scanSafety: scanSafety.withAdditionalReason(
            'Rescan detected for an already-scanned student and subject.',
          ),
          scanDebugInfo: omrResult.debugInfo,
        );
      }
      return;
    }

    await _recordScan(
      student: student,
      subject: subject,
      answers: omrResult.answers,
      confidence: omrResult.confidence,
      sheetId: sheetId,
      scanSafety: scanSafety,
      sourceBytes: sourceBytes,
      scanDebugInfo: omrResult.debugInfo,
      turboAutoSave: !forceReview &&
          _canTurboAutoSave(
            safety: scanSafety,
            omrResult: omrResult,
            subject: subject,
          ),
      processingMs: processingMs,
    );
  }

  /// Show scan error with quality improvement tips
  void _showScanErrorWithTips(
    OmrScanFailureMessage failure, {
    Map<String, dynamic>? debugInfo,
  }) {
    final problemSummary = _teacherFacingScanProblem(debugInfo);
    Uint8List? overlayBytes;
    final overlayB64 = debugInfo?['debugOverlayJpegBase64']?.toString();
    if (overlayB64 != null && overlayB64.isNotEmpty) {
      try {
        overlayBytes = base64Decode(overlayB64);
      } catch (e) {
        debugPrint('Failed to decode scan overlay: $e');
      }
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(failure.title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(failure.message),
              if (problemSummary != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    problemSummary,
                    style: TextStyle(
                      color: Colors.red.shade800,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              if (overlayBytes != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Where the scanner looked',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    overlayBytes,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Green = answer found · Red = empty / not read',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
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
                        failure.helpTip,
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
                    'Print sheets at 100% scale (Actual size) — not Fit to page.'),
                _scanTipBullet(
                    'Corner squares must be visible — don’t crop the page.'),
                _scanTipBullet(
                    'Re-scan with darker marks if bubbles were light or smudged.'),
              ],
            ],
          ),
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

  /// One short teacher-facing line instead of the raw native pipeline dump.
  String? _teacherFacingScanProblem(Map<String, dynamic>? debugInfo) {
    if (debugInfo == null || debugInfo.isEmpty) {
      return null;
    }

    final reason = debugInfo['failureReason']?.toString();
    switch (reason) {
      case 'OMR_ID':
        return debugInfo['omrIdNotFilled'] == true
            ? 'Problem: OMR ID bubbles look empty.'
            : 'Problem: OMR ID bubbles were unclear.';
      case 'WRONG_TEACHER':
        return 'Problem: This sheet belongs to another teacher.';
      case 'REPRINT_REQUIRED':
        return 'Problem: This sheet is outdated — reprint required.';
      case 'QR_REQUIRED':
        return 'Problem: Sheet QR code was not readable.';
      case 'WRONG_SUBJECT':
        return 'Problem: Wrong subject sheet.';
      case 'WRONG_SECTION':
        return 'Problem: Wrong section sheet.';
      case 'FOREIGN_SHEET':
        return 'Problem: Not a COC answer sheet.';
      case 'GRID_MISALIGNED':
        return 'Problem: Answer bubbles did not line up.';
      case 'TIMING_MARKS':
        return 'Problem: Edge timing marks were not clear.';
      case 'NO_SHEET':
        return 'Problem: No answer sheet found in the photo.';
      case 'CORNERS_INCOMPLETE':
        return 'Problem: Not all four corner squares were visible.';
      case 'TOO_BLURRY':
        return 'Problem: Photo was too blurry.';
      case 'TOO_DARK':
        return 'Problem: Photo was too dark.';
      case 'TOO_BRIGHT':
        return 'Problem: Too much glare on the sheet.';
      default:
        break;
    }

    final stages = debugInfo['pipelineStages'];
    if (stages is List) {
      for (final stage in stages) {
        final line = stage.toString();
        if (!line.startsWith('✗')) {
          continue;
        }
        final lower = line.toLowerCase();
        if (lower.contains('omr id')) {
          return 'Problem: OMR ID bubbles were unclear.';
        }
        if (lower.contains('timing')) {
          return 'Problem: Edge timing marks were not clear.';
        }
        if (lower.contains('corner')) {
          return 'Problem: Corner squares were not clear.';
        }
        if (lower.contains('quality') || lower.contains('blur')) {
          return 'Problem: Photo quality was not good enough.';
        }
        return 'Problem: The scanner could not finish reading this sheet.';
      }
    }
    return null;
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
                        _resumeLightingMonitorIfNeeded();
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
                    'The in-app camera is required for exam scanning.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => unawaited(_initCamera()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry camera'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
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
          if (_lightingOverlayHint != null) _buildLightingBanner(),
          _buildBottomBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildLightingBanner() {
    final hint = _lightingOverlayHint;
    if (hint == null) {
      return const SizedBox.shrink();
    }

    final tooDark = _lightingLevel == ScanLightingLevel.tooDark;
    final background = tooDark
        ? Colors.red.shade900.withValues(alpha: 0.88)
        : Colors.orange.shade900.withValues(alpha: 0.82);

    return Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(
                  tooDark
                      ? Icons.brightness_2_outlined
                      : Icons.light_mode_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hint,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

class _CompressArgs {
  const _CompressArgs({
    required this.bytes,
    required this.maxDim,
    required this.quality,
  });

  final Uint8List bytes;
  final int maxDim;
  final int quality;
}

class _SheetStudentSectionMismatch {
  const _SheetStudentSectionMismatch({
    required this.sheetSection,
    required this.student,
  });

  final String sheetSection;
  final Student student;
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

  bool get requiresReview =>
      reviewReasons.isNotEmpty || flaggedQuestions.isNotEmpty;

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
