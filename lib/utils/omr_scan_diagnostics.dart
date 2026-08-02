/// Teacher-readable lines derived from native OMR [debugInfo].
///
/// Used on the scan review screen so validation runs are diagnosable without adb.
class OmrScanDiagnostics {
  const OmrScanDiagnostics(this.lines);

  final List<String> lines;

  bool get isEmpty => lines.isEmpty;

  static OmrScanDiagnostics fromDebugInfo(Map<String, dynamic>? debugInfo) {
    if (debugInfo == null || debugInfo.isEmpty) {
      return const OmrScanDiagnostics([]);
    }

    final lines = <String>[];

    void add(String label, Object? value) {
      if (value == null) return;
      final text = value.toString().trim();
      if (text.isEmpty) return;
      lines.add('$label: $text');
    }

    final stages = debugInfo['pipelineStages'];
    if (stages is List && stages.isNotEmpty) {
      final failed = debugInfo['failedStage'];
      if (failed != null) {
        lines.add('Failed stage: $failed');
      }
      final lastOk = stages.cast<Object?>().whereType<String>().where((s) => s.startsWith('✓')).toList();
      if (lastOk.isNotEmpty) {
        lines.add('Last OK: ${lastOk.last.replaceFirst('✓ ', '')}');
      }
    }

    final cornerVia = debugInfo['cornerDetectionSucceededVia'];
    if (cornerVia != null) {
      add('Corner detection', _cornerMethodLabel(cornerVia.toString()));
    }

    final timing = _asDouble(debugInfo['timingMarkScore']);
    if (timing != null) {
      final found = debugInfo['timingMarksFound'];
      final expected = debugInfo['timingMarksExpected'];
      if (found is num && expected is num && expected > 0) {
        add(
          'Alignment marks',
          '${(timing * 100).round()}% ($found of $expected)',
        );
      } else {
        add('Alignment marks', '${(timing * 100).round()}%');
      }
    }

    final calibrated = debugInfo['calibrationSuccess'];
    if (calibrated is bool) {
      final fill = _asDouble(debugInfo['fillThreshold']);
      add(
        'Fill calibration',
        calibrated
            ? (fill != null ? 'OK (threshold ${fill.toStringAsFixed(2)})' : 'OK')
            : 'Failed — using default threshold',
      );
    }

    final layout = debugInfo['layoutTemplate'];
    if (layout != null) {
      final fromSession = debugInfo['layoutFromSession'] == true;
      add(
        'Answer layout',
        '${layout.toString()}${fromSession ? ' (exam session)' : ''}',
      );
    }

    if (debugInfo['templateMismatchWarning'] == true) {
      lines.add('Template check: grid may not match this exam');
    }

    if (debugInfo['failureReason']?.toString() == 'FOREIGN_SHEET') {
      final origin = debugInfo['sheetOriginClassification']?.toString();
      if (origin != null && origin.isNotEmpty) {
        lines.add('Sheet check: $origin');
      }
      final qrId = debugInfo['sheetQrIdentity']?.toString();
      if (qrId != null && qrId.isNotEmpty) {
        lines.add('QR identity: $qrId');
      }
    }

    if (debugInfo['omrIdNeedsReview'] == true) {
      final col = debugInfo['omrIdAmbiguousColumn'];
      if (col is num) {
        lines.add('OMR ID: digit ${col.toInt() + 1} needs verification');
      } else {
        lines.add('OMR ID: one digit needs verification');
      }
    }

    if (debugInfo['failureReason']?.toString() == 'OMR_ID') {
      for (var col = 0; col < 4; col++) {
        final raw = debugInfo['omrIdColumn$col'];
        if (raw is! Map) continue;
        final best = raw['bestDigit'];
        final fill = raw['bestFill'];
        final status = raw['status']?.toString() ?? '';
        final fillPct = fill is num ? (fill * 100).round() : null;
        final digitLabel = best is num && best.toInt() >= 0 ? '${best.toInt()}' : '?';
        final fillLabel = fillPct != null ? '$fillPct%' : '?';
        lines.add(
          'OMR ID col ${col + 1}: best $digitLabel ($fillLabel, $status)',
        );
      }
      final answered = debugInfo['answersDetected'];
      final blank = debugInfo['blankAnswersCount'];
      if (answered is num || blank is num) {
        lines.add(
          'Answers shaded: ${answered is num ? answered.toInt() : '?'} · '
          'Blank (no shade): ${blank is num ? blank.toInt() : '?'}',
        );
      }
    }

    final rejectLow = debugInfo['rejectAreaLow'];
    final rejectHigh = debugInfo['rejectAreaHigh'];
    final rejectAspect = debugInfo['rejectAspect'];
    if (rejectLow is num || rejectHigh is num || rejectAspect is num) {
      final low = rejectLow is num ? rejectLow.toInt() : 0;
      final high = rejectHigh is num ? rejectHigh.toInt() : 0;
      final aspect = rejectAspect is num ? rejectAspect.toInt() : 0;
      if (low + high + aspect > 0) {
        add(
          'Corner filter rejects',
          '$low too small, $high too large, $aspect wrong shape',
        );
      }
    }

    final candidates = debugInfo['balancedCandidates'];
    if (candidates is num) {
      add('Corner candidates', candidates.toInt());
    }

    final quadrantParts = <String>[];
    void addQuadrant(String key, String label) {
      final count = debugInfo[key];
      if (count is num) {
        quadrantParts.add('$label ${count.toInt()}');
      }
    }

    addQuadrant('quadrantCountTL', 'TL');
    addQuadrant('quadrantCountTR', 'TR');
    addQuadrant('quadrantCountBL', 'BL');
    addQuadrant('quadrantCountBR', 'BR');
    if (quadrantParts.isNotEmpty) {
      add('Corner quadrants', quadrantParts.join(', '));
    }

    final missing = debugInfo['missingQuadrants'];
    if (missing is List && missing.isNotEmpty) {
      add('Missing corners', missing.map((e) => e.toString()).join(', '));
    }

    final nearestFallback = debugInfo['cornerNearestFallback'];
    if (nearestFallback is List && nearestFallback.isNotEmpty) {
      add(
        'Corner recovery',
        'Used nearest-point fallback for ${nearestFallback.map((e) => e.toString()).join(', ')}',
      );
    }

    final blur = _asDouble(debugInfo['blurScore']);
    final contrast = _asDouble(debugInfo['contrastScore']);
    if (blur != null || contrast != null) {
      final parts = <String>[];
      if (blur != null) parts.add('sharpness ${blur.round()}');
      if (contrast != null) {
        parts.add('contrast ${(contrast * 100).round()}%');
      }
      add('Image quality', parts.join(', '));
    }

    final ms = debugInfo['processingTimeMs'];
    if (ms is num) {
      add('Processing time', '${ms.round()} ms');
    }

    return OmrScanDiagnostics(lines);
  }

  static String _cornerMethodLabel(String via) {
    switch (via) {
      case 'balanced':
        return 'Standard (balanced)';
      case 'fast_fallback':
        return 'Corner-region search';
      case 'multiThreshold':
        return 'Multi-brightness retry';
      case 'edge':
        return 'Last-resort edge search';
      case 'advanced':
        return 'High-detail pattern match';
      case 'none':
        return 'Failed — no method succeeded';
      default:
        return via;
    }
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
