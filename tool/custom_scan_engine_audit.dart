import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:omr_app/models/omr_template_specs.dart';

/// Professional scan-engine estimate for every custom Q∈[5,200].
/// Scores geometry headroom that drives false multi-marks / OMR ID misses
/// (row pitch, option gap, refine budget, timing marks, short-grid scale risk).
void main() {
  const form = OmrLayoutForm(
    orientation: OmrLayoutOrientation.lengthwise,
    pageFill: OmrLayoutPageFill.full,
  );

  final rows = <Map<String, Object?>>[];
  final buckets = <String, int>{
    'low': 0,
    'medium': 0,
    'elevated': 0,
    'blocked': 0,
  };

  for (var opts = 2; opts <= 6; opts++) {
    final maxFit = OmrLayoutProfile.maxFitItems(form: form, optionsCount: opts);
    for (var q = OmrLayoutProfile.minCustomItems;
        q <= OmrLayoutProfile.maxCustomItems;
        q++) {
      final fit = OmrLayoutProfile.tryCompute(
        itemCount: q,
        optionsCount: opts,
        form: form,
      );
      if (!fit.isOk || fit.profile == null) {
        buckets['blocked'] = buckets['blocked']! + 1;
        rows.add({
          'opts': opts,
          'q': q,
          'ok': false,
          'maxFit': maxFit,
          'risk': 'blocked',
        });
        continue;
      }

      final p = fit.profile!;
      final g = p.geometry;
      final rowH = p.grid.rowHeight;
      final bx = p.grid.bubbleSpacingX;
      final diam = g.answerBubbleDiameter;
      final cols = p.grid.columns;
      final rCount = p.grid.rows;
      final vClear = rowH - diam;
      final hClear = bx - diam;

      // Match native spacingSafeRefineRadius budgets (page points ≈ warp px).
      final refineBySpacing = math.max(1, (bx * 0.22).floor());
      final refineByRow = math.max(1, (rowH * 0.20).floor());
      final refineBudget = math.min(3, math.min(refineBySpacing, refineByRow));

      final timingX = _markCount(
        g.timingMarkStartX,
        g.timingMarkEndX,
        g.timingMarkSpacing,
      );
      final timingY = _markCount(
        g.timingMarkStartY,
        g.timingMarkEndY,
        g.timingMarkSpacing,
      );

      // Short grids previously applied Y-scale lock → last-row drift risk.
      final shortGridScaleRisk = rCount < 8;

      final warns = <String>[];
      if (rowH < OmrLayoutProfile.scanMinRowHeight(g) + 1.0) {
        warns.add('rowH-near-floor');
      }
      if (bx < OmrLayoutProfile.scanMinBubbleSpacing(form, g) + 1.0) {
        warns.add('bx-near-floor');
      }
      if (hClear < 4.0) warns.add('option-gap-tight');
      if (vClear < 5.0) warns.add('row-gap-tight');
      if (refineBudget < 2 && bx < 14) warns.add('refine-starved');
      if (timingX < 4 || timingY < 4) warns.add('timing-weak');
      if (shortGridScaleRisk) warns.add('short-grid');

      // Print↔scan bubble contract: centers from profile must match session map.
      var contractOk = true;
      for (var c = 0; c < cols; c++) {
        for (var oi = 0; oi < opts; oi++) {
          final x = p.bubbleCenterX(c, oi);
          final expectedLeft = g.answerGridLeft + c * p.grid.columnWidth;
          if (x < expectedLeft || x > expectedLeft + p.grid.columnWidth) {
            contractOk = false;
          }
        }
      }
      if (!contractOk) warns.add('bubble-contract');

      String risk;
      if (warns.contains('bubble-contract') ||
          warns.contains('timing-weak') ||
          hClear < 2.5) {
        risk = 'elevated';
      } else if (warns.isNotEmpty &&
          (warns.contains('option-gap-tight') ||
              warns.contains('rowH-near-floor') ||
              warns.contains('bx-near-floor'))) {
        risk = 'medium';
      } else if (warns.length >= 2) {
        risk = 'medium';
      } else {
        risk = 'low';
      }
      // short-grid alone is mitigated in native (scale disabled) → keep low/medium
      if (risk == 'elevated' && warns.length == 1 && warns.first == 'short-grid') {
        risk = 'low';
      }
      if (risk == 'medium' &&
          warns.length == 1 &&
          warns.first == 'short-grid') {
        risk = 'low';
      }

      buckets[risk] = buckets[risk]! + 1;
      rows.add({
        'opts': opts,
        'q': q,
        'ok': true,
        'maxFit': maxFit,
        'cols': cols,
        'rows': rCount,
        'rowH': _r(rowH),
        'bx': _r(bx),
        'diam': _r(diam),
        'vClear': _r(vClear),
        'hClear': _r(hClear),
        'refineBudgetPx': refineBudget,
        'timingX': timingX,
        'timingY': timingY,
        'shortGrid': shortGridScaleRisk,
        'contractOk': contractOk,
        'warns': warns,
        'risk': risk,
      });
    }
  }

  // Spot samples teachers care about
  final samples = <String, Object?>{};
  for (final q in [5, 15, 20, 30, 50, 60, 100, 155, 186, 200]) {
    for (final opts in [4, 5, 6]) {
      final hit = rows.cast<Map<String, Object?>>().firstWhere(
            (r) => r['q'] == q && r['opts'] == opts,
            orElse: () => {},
          );
      if (hit.isEmpty) continue;
      samples['${q}x$opts'] = {
        'ok': hit['ok'],
        'grid': hit['ok'] == true ? '${hit['cols']}x${hit['rows']}' : null,
        'risk': hit['risk'],
        'rowH': hit['rowH'],
        'bx': hit['bx'],
        'refine': hit['refineBudgetPx'],
        'warns': hit['warns'],
      };
    }
  }

  final elevated = rows
      .where((r) => r['risk'] == 'elevated')
      .take(20)
      .toList();

  final findings = <String>[
    'Estimated scan-engine risk for every full-page Automatic pack Q∈[5,200] × opts∈[2,6].',
    'Buckets: low=${buckets['low']}, medium=${buckets['medium']}, '
        'elevated=${buckets['elevated']}, blocked=${buckets['blocked']}.',
    'Native mitigations applied: no Y-scale lock when rows<8; spacing-safe refine; '
        'multi-mark clear-winner (sep≥0.12); softer OMR ID cut.',
    'Sample 15×A–E: ${samples['15x5']}.',
    if (elevated.isEmpty)
      'PASS: no elevated-risk accepted packs remain after geometry floors.'
    else
      'REVIEW: ${elevated.length}+ elevated packs — see elevatedSamples.',
  ];

  final out = {
    'generatedAt': DateTime.now().toIso8601String(),
    'scope': 'Full-page custom Automatic packs — scan-engine risk estimate',
    'buckets': buckets,
    'samples': samples,
    'elevatedSamples': elevated,
    'findings': findings,
    'everyPack': rows,
  };

  File('tool/custom_scan_engine_audit.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  stdout.writeln(jsonEncode(buckets));
  for (final f in findings) {
    stdout.writeln(f);
  }
}

int _markCount(double start, double end, double spacing) {
  if (spacing <= 0) return 0;
  return ((end - start) / spacing).floor() + 1;
}

double _r(double v) => double.parse(v.toStringAsFixed(2));
