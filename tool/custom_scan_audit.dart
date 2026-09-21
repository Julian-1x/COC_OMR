import 'dart:convert';
import 'dart:io';

import 'package:omr_app/models/omr_template_specs.dart';

/// Professional scan-contract audit for every custom count 5–200.
///
/// Checks the same floors the exam-day gate and packer enforce, plus
/// estimated registration-mark counts the native scanner needs (≥4/edge).
void main() {
  final forms = OmrLayoutProfile.allCustomForms;
  final rows = <Map<String, Object?>>[];
  final riskBuckets = <String, int>{
    'roomy': 0,
    'dense_ok': 0,
    'tight_warn': 0,
    'blocked': 0,
  };

  for (final form in forms) {
    for (var opts = 2; opts <= 6; opts++) {
      final maxFit = OmrLayoutProfile.maxFitItems(
        form: form,
        optionsCount: opts,
      );
      for (var q = OmrLayoutProfile.minCustomItems;
          q <= OmrLayoutProfile.maxCustomItems;
          q++) {
        final fit = OmrLayoutProfile.tryCompute(
          itemCount: q,
          optionsCount: opts,
          form: form,
        );
        if (!fit.isOk || fit.profile == null) {
          riskBuckets['blocked'] = riskBuckets['blocked']! + 1;
          rows.add({
            'form': form.id,
            'opts': opts,
            'q': q,
            'ok': false,
            'maxFit': maxFit,
            'risk': 'blocked',
            'reason': fit.errorMessage,
          });
          continue;
        }

        final p = fit.profile!;
        final g = p.geometry;
        final timingX = _markCount(g.timingMarkStartX, g.timingMarkEndX, g.timingMarkSpacing);
        final timingY = _markCount(g.timingMarkStartY, g.timingMarkEndY, g.timingMarkSpacing);
        final minRow = OmrLayoutProfile.scanMinRowHeight(g);
        final minSp = OmrLayoutProfile.scanMinBubbleSpacing(form, g);
        final dense = g.answerBubbleDiameter < OmrPageConstants.answerBubbleDiameter;
        final rowSlack = p.grid.rowHeight - minRow;
        final spaceSlack = p.grid.bubbleSpacingX - minSp;
        final diamGap = p.grid.rowHeight - g.answerBubbleDiameter;
        final even = q % p.grid.columns == 0;
        final empty = p.grid.columns * p.grid.rows - q;

        final verticalTouch =
            diamGap < OmrLayoutProfile.minBubbleVerticalClearance;
        final horizontalTouch =
            p.grid.bubbleSpacingX < g.answerBubbleDiameter + 0.5;
        final timingWeak = timingX < 4 || timingY < 4;
        final qrTight = g.qrCodeSize < 56.0;
        final cornerOk = g.cornerMarkerSize >= 12.0;
        final tooManyRows = p.grid.rows > OmrLayoutProfile.maxRowsPerColumn;
        final skyscraper = p.grid.columns == 1 && q > 25;

        String risk;
        final warns = <String>[];
        if (timingWeak) warns.add('timing<4');
        if (verticalTouch) warns.add('row≈bubble');
        if (horizontalTouch) warns.add('opt≈bubble');
        // Floors already include densePackMargin / denseSpacingMargin.
        // Flag only true violations (numeric noise), not a second soft margin.
        if (rowSlack < -0.01) warns.add('row-floor');
        if (spaceSlack < -0.01) warns.add('space-floor');
        if (qrTight) warns.add('qr-small');
        if (!cornerOk) warns.add('corner-small');
        if (tooManyRows) warns.add('rows>cap');
        if (skyscraper) warns.add('1-col');
        if (!even && empty > p.grid.columns) warns.add('uneven-tail');

        // After reliable floors, any warn is a residual risk we must drive to 0
        // on full page (half/¼ scaled marks are expected).
        if (warns.isNotEmpty) {
          risk = 'tight_warn';
          riskBuckets['tight_warn'] = riskBuckets['tight_warn']! + 1;
        } else if (dense && _isFull(form)) {
          risk = 'dense_ok';
          riskBuckets['dense_ok'] = riskBuckets['dense_ok']! + 1;
        } else if (dense) {
          // Half/¼ always use scaled bubbles — count as dense_ok, not tight.
          risk = 'dense_ok';
          riskBuckets['dense_ok'] = riskBuckets['dense_ok']! + 1;
        } else {
          risk = 'roomy';
          riskBuckets['roomy'] = riskBuckets['roomy']! + 1;
        }

        rows.add({
          'form': form.id,
          'opts': opts,
          'q': q,
          'ok': true,
          'maxFit': maxFit,
          'risk': risk,
          'cols': p.grid.columns,
          'rows': p.grid.rows,
          'even': even,
          'empty': empty,
          'dense': dense,
          'rowH': _r(p.grid.rowHeight),
          'colW': _r(p.grid.columnWidth),
          'bx': _r(p.grid.bubbleSpacingX),
          'diam': _r(g.answerBubbleDiameter),
          'minRow': _r(minRow),
          'minBx': _r(minSp),
          'rowSlack': _r(rowSlack),
          'spaceSlack': _r(spaceSlack),
          'diamGap': _r(diamGap),
          'timingX': timingX,
          'timingY': timingY,
          'timingSp': _r(g.timingMarkSpacing),
          'timingBandY': _r(g.timingMarkEndY - g.timingMarkStartY),
          'corner': _r(g.cornerMarkerSize),
          'qr': _r(g.qrCodeSize),
          'gridTop': _r(g.answerRowsTop),
          'gridBottom': _r(g.answerRowsBottom),
          'contentH': _r(g.answerGridContentHeight),
          'omrIdH': _r(g.omrIdHeight),
          'rowMarkX': _r(g.rowMarkX),
          'warns': warns,
        });
      }
    }
  }

  // Summaries by form×opts
  final byFormOpts = <String, Map<String, Object?>>{};
  for (final form in forms) {
    for (var opts = 2; opts <= 6; opts++) {
      final key = '${form.id}|$opts';
      final subset = rows.where((r) => r['form'] == form.id && r['opts'] == opts);
      final ok = subset.where((r) => r['ok'] == true).toList();
      final blocked = subset.where((r) => r['ok'] == false).length;
      final firstBlocked = subset
          .where((r) => r['ok'] == false)
          .map((r) => r['q'] as int)
          .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
      final lastOk = ok
          .map((r) => r['q'] as int)
          .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
      final tight = ok.where((r) => r['risk'] == 'tight_warn').length;
      final dense = ok.where((r) => r['risk'] == 'dense_ok').length;
      final roomy = ok.where((r) => r['risk'] == 'roomy').length;
      final minRowH = ok
          .map((r) => r['rowH'] as double)
          .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
      final minBx = ok
          .map((r) => r['bx'] as double)
          .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
      final minTimingY = ok
          .map((r) => r['timingY'] as int)
          .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
      final minTimingX = ok
          .map((r) => r['timingX'] as int)
          .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
      byFormOpts[key] = {
        'form': form.id,
        'opts': opts,
        'okCount': ok.length,
        'blockedCount': blocked,
        'firstBlockedQ': firstBlocked,
        'lastOkQ': lastOk,
        'roomy': roomy,
        'dense_ok': dense,
        'tight_warn': tight,
        'minRowH': minRowH,
        'minBx': minBx,
        'minTimingX': minTimingX,
        'minTimingY': minTimingY,
        'maxFit': OmrLayoutProfile.maxFitItems(form: form, optionsCount: opts),
      };
    }
  }

  // Transition points on full page × 6 (the densest production path)
  final full6 = rows
      .where((r) => r['form'] == 'lengthwise_full' && r['opts'] == 6 && r['ok'] == true)
      .toList();
  final transitions = <Map<String, Object?>>[];
  String? prevRisk;
  for (final r in full6) {
    final risk = r['risk'] as String;
    if (risk != prevRisk) {
      transitions.add({
        'q': r['q'],
        'risk': risk,
        'grid': '${r['cols']}×${r['rows']}',
        'rowH': r['rowH'],
        'bx': r['bx'],
        'diam': r['diam'],
        'dense': r['dense'],
        'timingY': r['timingY'],
      });
      prevRisk = risk;
    }
  }

  // Worst tight_warn cases (lowest rowSlack among ok)
  final tightCases = rows
      .where((r) => r['ok'] == true && r['risk'] == 'tight_warn')
      .toList()
    ..sort((a, b) =>
        (a['rowSlack'] as double).compareTo(b['rowSlack'] as double));
  final worstTight = tightCases.take(25).toList();

  // Per-question strip for full×6 (every Q) — compact for canvas filter
  final full6Strip = full6
      .map((r) => {
            'q': r['q'],
            'risk': r['risk'],
            'grid': '${r['cols']}×${r['rows']}',
            'rowH': r['rowH'],
            'bx': r['bx'],
            'diam': r['diam'],
            'timingX': r['timingX'],
            'timingY': r['timingY'],
            'even': r['even'],
            'warns': r['warns'],
          })
      .toList();

  // Half and quarter capacity walls
  final capacityWalls = <Map<String, Object?>>[];
  for (final form in forms) {
    for (var opts = 2; opts <= 6; opts++) {
      capacityWalls.add({
        'form': form.id,
        'opts': opts,
        'maxFit': OmrLayoutProfile.maxFitItems(form: form, optionsCount: opts),
        'safetyCap': OmrLayoutProfile.safetyCapForForm(form),
      });
    }
  }

  // Registration constants for full standard / dense
  final std = OmrSheetGeometry.standardPortrait();
  final dense = OmrSheetGeometry.denseFullPortrait();
  final half = OmrSheetGeometry.forForm(
    const OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.half,
    ),
  );
  final quarter = OmrSheetGeometry.forForm(
    const OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.quarter,
    ),
  );

  Map<String, Object?> geoSnap(String name, OmrSheetGeometry g) => {
        'name': name,
        'page': '${g.pageWidth.toInt()}×${g.pageHeight.toInt()}',
        'block': '${_r(g.contentBlockWidth)}×${_r(g.contentBlockHeight)}',
        'contentH': _r(g.answerGridContentHeight),
        'gridTop': _r(g.answerRowsTop),
        'gridBottom': _r(g.answerRowsBottom),
        'diam': _r(g.answerBubbleDiameter),
        'corner': _r(g.cornerMarkerSize),
        'timingSp': _r(g.timingMarkSpacing),
        'timingX': _markCount(g.timingMarkStartX, g.timingMarkEndX, g.timingMarkSpacing),
        'timingY': _markCount(g.timingMarkStartY, g.timingMarkEndY, g.timingMarkSpacing),
        'timingBandY': _r(g.timingMarkEndY - g.timingMarkStartY),
        'qr': _r(g.qrCodeSize),
        'rowMarkX': _r(g.rowMarkX),
        'omrIdH': _r(g.omrIdHeight),
        'calY': _r(g.calibrationY),
      };

  final out = {
    'generatedAt': DateTime.now().toIso8601String(),
    'scope': 'Custom portrait sheets only (lengthwise full/half/quarter). '
        'Standard 30–100 presets are out of scope and unchanged.',
    'scannerFloors': {
      'preferredRowH': OmrLayoutProfile.minRowHeight,
      'denseRowH': OmrLayoutProfile.minRowHeightDense,
      'denseRowMargin': OmrLayoutProfile.densePackMargin,
      'preferredBx': OmrLayoutProfile.minBubbleSpacingX,
      'denseBx': OmrLayoutProfile.minBubbleSpacingXDense,
      'denseBxMargin': OmrLayoutProfile.denseSpacingMargin,
      'quarterBx': OmrLayoutProfile.minBubbleSpacingXQuarter,
      'maxRowsPerColumn': OmrLayoutProfile.maxRowsPerColumn,
      'verticalClearance': OmrLayoutProfile.minBubbleVerticalClearance,
      'timingMinPerEdge': 4,
      'nativeTimingFailThreshold': 0.40,
      'qrMin': 56.0,
      'bubbleMin': 8.0,
    },
    'riskBuckets': riskBuckets,
    'totalChecked': rows.length,
    'geometries': [
      geoSnap('full_standard', std),
      geoSnap('full_dense', dense),
      geoSnap('half', half),
      geoSnap('quarter', quarter),
    ],
    'capacityWalls': capacityWalls,
    'byFormOpts': byFormOpts.values.toList(),
    'full6Transitions': transitions,
    'full6EveryQ': full6Strip,
    'worstTight': worstTight,
    'findings': _findings(byFormOpts, riskBuckets, transitions, full6Strip),
  };

  final path = File('tool/custom_scan_audit.json');
  path.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln('Wrote ${path.path}');
  stdout.writeln(jsonEncode(riskBuckets));
  stdout.writeln('full×6 lastOk=${byFormOpts['lengthwise_full|6']?['lastOkQ']} '
      'maxFit=${byFormOpts['lengthwise_full|6']?['maxFit']}');
}

List<String> _findings(
  Map<String, Map<String, Object?>> byFormOpts,
  Map<String, int> buckets,
  List<Map<String, Object?>> transitions,
  List<Map<String, Object?>> full6,
) {
  final f = <String>[];
  f.add(
    'Checked every Q∈[5,200] × opts∈[2,6] × forms∈{full,half,¼} = '
    '${buckets.values.fold(0, (a, b) => a + b)} layouts against packer + scan floors.',
  );
  final full6meta = byFormOpts['lengthwise_full|6']!;
  f.add(
    'Full page × A–F: last scannable count = ${full6meta['lastOkQ']} '
    '(maxFit ${full6meta['maxFit']}). Roomy ${full6meta['roomy']}, '
    'dense_ok ${full6meta['dense_ok']}, tight_warn ${full6meta['tight_warn']}, '
    'blocked ${full6meta['blockedCount']}.',
  );
  f.add(
    'Reliable floors: dense rowH≥${OmrLayoutProfile.minRowHeightDense}'
    '+${OmrLayoutProfile.densePackMargin} margin, '
    'bx≥${OmrLayoutProfile.minBubbleSpacingXDense}'
    '+${OmrLayoutProfile.denseSpacingMargin} margin, '
    'vertical clearance≥${OmrLayoutProfile.minBubbleVerticalClearance}, '
    'max rows/column=${OmrLayoutProfile.maxRowsPerColumn}, '
    'no 1-column packs above 25 questions.',
  );
  if ((buckets['tight_warn'] ?? 0) == 0) {
    f.add('Residual tight_warn count is 0 — every accepted layout meets floors.');
  } else {
    f.add(
      'WARNING: tight_warn=${buckets['tight_warn']} layouts still accepted — '
      'raise floors further before exam use.',
    );
  }
  final half6 = byFormOpts['lengthwise_half|6']!;
  final q6 = byFormOpts['lengthwise_quarter|6']!;
  f.add(
    'Half × A–F caps at Q=${half6['lastOkQ']} (maxFit ${half6['maxFit']}). '
    '¼ × A–F caps at Q=${q6['lastOkQ']} (maxFit ${q6['maxFit']}). '
    'High counts are fail-closed — never silently remapped to an unsafe grid.',
  );

  final timingFloor = full6.isEmpty
      ? 0
      : full6
          .map((r) => (r['timingY'] as int) < (r['timingX'] as int)
              ? r['timingY'] as int
              : r['timingX'] as int)
          .fold<int>(999, (a, b) => b < a ? b : a);
  f.add(
    'Full×A–F timing marks: minimum per-edge count across all fitting Q = $timingFloor '
    '(native requires ≥4; fail threshold 40% detection rate).',
  );

  if (full6.isNotEmpty) {
    final minDiamGap = full6
        .map((r) => (r['rowH'] as double) - (r['diam'] as double))
        .fold<double>(999, (a, b) => b < a ? b : a);
    f.add(
      'Full×A–F vertical bubble clearance (rowH − diameter) minimum = '
      '${minDiamGap.toStringAsFixed(2)} pt '
      '(required ≥${OmrLayoutProfile.minBubbleVerticalClearance}).',
    );
  }

  f.add(
    'Standard 30–100 presets are not in this matrix and still use frozen '
    'registration constants + useFrozenRegistrationMarks=true.',
  );
  return f;
}

bool _isFull(OmrLayoutForm form) =>
    form.orientation == OmrLayoutOrientation.lengthwise &&
    form.pageFill == OmrLayoutPageFill.full;

int _markCount(double start, double end, double spacing) {
  if (spacing <= 0) return 0;
  return ((end - start) / spacing).floor() + 1;
}

double _r(double v) => double.parse(v.toStringAsFixed(2));
