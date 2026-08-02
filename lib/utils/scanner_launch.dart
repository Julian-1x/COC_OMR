import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/services/scanner_engine.dart';
import 'package:omr_app/theme/app_colors.dart';

/// Ensures the native grading engine is loaded before opening the scanner.
/// Returns false only if the teacher cancels the wait.
Future<bool> prepareScannerEngineForExam(BuildContext context) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    return true;
  }

  if (ScannerEngine.isReady || await ScannerEngine.checkReady()) {
    return true;
  }

  if (!context.mounted) {
    return false;
  }

  final ready = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _InitializingScannerDialog(),
  );

  return ready == true;
}

class _InitializingScannerDialog extends StatefulWidget {
  const _InitializingScannerDialog();

  @override
  State<_InitializingScannerDialog> createState() =>
      _InitializingScannerDialogState();
}

class _InitializingScannerDialogState extends State<_InitializingScannerDialog> {
  bool _showExtendedNote = false;
  bool _failed = false;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOnce());
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (mounted && !_failed) {
        setState(() => _showExtendedNote = true);
      }
    });
  }

  Future<void> _loadOnce({bool forceRetry = false}) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _failed = false;
      _retrying = forceRetry;
    });

    final ready = forceRetry
        ? await ScannerEngine.retryLoad(
            timeout: const Duration(seconds: 60),
          )
        : await ScannerEngine.warmUp(
            timeout: const Duration(seconds: 60),
          );

    if (!mounted) {
      return;
    }

    if (ready || await ScannerEngine.checkReady()) {
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
      return;
    }

    await ScannerEngine.fetchInitError();
    if (!mounted) {
      return;
    }
    setState(() {
      _failed = true;
      _retrying = false;
      _showExtendedNote = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        Navigator.pop(context, false);
      },
      child: AlertDialog(
        title: Text(_failed ? 'Scanner not ready' : 'Scanner'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_failed)
              const LinearProgressIndicator(
                color: AppColors.brandGreen,
                backgroundColor: AppColors.brandBorder,
              ),
            if (!_failed) const SizedBox(height: 16),
            Text(
              _failed
                  ? 'The grading engine did not load. Tap Retry, or cancel and try again.'
                  : 'Initializing…',
              style: const TextStyle(color: AppColors.brandText, height: 1.45),
            ),
            if (_showExtendedNote && !_failed) ...[
              const SizedBox(height: 10),
              Text(
                'First launch may take a moment.',
                style: TextStyle(
                  color: AppColors.brandMuted.withValues(alpha: 0.9),
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
            ],
            if (_failed &&
                ScannerEngine.lastError != null &&
                ScannerEngine.lastError!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                ScannerEngine.lastError!,
                style: TextStyle(
                  color: AppColors.brandMuted.withValues(alpha: 0.9),
                  height: 1.45,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          if (_failed)
            FilledButton(
              onPressed: _retrying
                  ? null
                  : () => unawaited(_loadOnce(forceRetry: true)),
              child: Text(_retrying ? 'Retrying…' : 'Retry'),
            ),
        ],
      ),
    );
  }
}
