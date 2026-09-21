import 'dart:convert';
import 'dart:io';

import 'package:omr_app/models/omr_template_specs.dart';

/// Audits Automatic packs for Q∈[5,200] × opts∈[2,6] on full/half/¼.
/// Fails closed if any accepted pack is wider than the lengthwise column cap
/// or is a shallow "pancake" (too few rows for the column count).
void main() {
  final forms = [
    const OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.full,
    ),
    const OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.half,
    ),
    const OmrLayoutForm(
      orientation: OmrLayoutOrientation.lengthwise,
      pageFill: OmrLayoutPageFill.quarter,
    ),
  ];

  final rows = <Map<String, Object?>>[];
  final violations = <Map<String, Object?>>[];
  var okCount = 0;
  var blockedCount = 0;

  for (final form in forms) {
    for (var opts = 2; opts <= 6; opts++) {
      for (var q = OmrLayoutProfile.minCustomItems;
          q <= OmrLayoutProfile.maxCustomItems;
          q++) {
        final fit = OmrLayoutProfile.tryCompute(
          itemCount: q,
          optionsCount: opts,
          form: form,
        );
        final maxFit = OmrLayoutProfile.maxFitItems(
          form: form,
          optionsCount: opts,
        );

        if (!fit.isOk || fit.profile == null) {
          blockedCount++;
          rows.add({
            'form': form.id,
            'opts': opts,
            'q': q,
            'ok': false,
            'maxFit': maxFit,
            'reason': fit.errorMessage,
          });
          continue;
        }

        final p = fit.profile!;
        final cols = p.grid.columns;
        final r = p.grid.rows;
        final even = q % cols == 0;
        final maxCols = OmrLayoutProfile.maxColumnsFor(form, itemCount: q);
        final pancake = (cols >= 6 && r < 10) || (cols >= 4 && r <= 2);
        final tooWide = cols > maxCols;
        final skyscraper = cols == 1 && q > 25;
        final shallowPreferred =
            cols >= 5 && r < 5 && q >= 18;

        okCount++;
        final entry = {
          'form': form.id,
          'opts': opts,
          'q': q,
          'ok': true,
          'maxFit': maxFit,
          'cols': cols,
          'rows': r,
          'even': even,
          'diam': p.geometry.answerBubbleDiameter,
          'rowH': double.parse(p.grid.rowHeight.toStringAsFixed(2)),
          'bx': double.parse(p.grid.bubbleSpacingX.toStringAsFixed(2)),
        };
        rows.add(entry);

        if (tooWide || pancake || skyscraper || shallowPreferred) {
          violations.add({
            ...entry,
            'tooWide': tooWide,
            'pancake': pancake,
            'skyscraper': skyscraper,
            'shallowPreferred': shallowPreferred,
            'maxCols': maxCols,
          });
        }
      }
    }
  }

  // Summaries: column histogram for full page
  final fullColHist = <int, int>{};
  final fullByOpts = <int, Map<String, Object?>>{};
  for (var opts = 2; opts <= 6; opts++) {
    final subset = rows.where(
      (r) => r['form'] == 'lengthwise_full' && r['opts'] == opts,
    );
    final ok = subset.where((r) => r['ok'] == true).toList();
    final blocked = subset.where((r) => r['ok'] != true).length;
    var maxColsUsed = 0;
    var minRows = 999;
    for (final r in ok) {
      final c = r['cols'] as int;
      fullColHist[c] = (fullColHist[c] ?? 0) + 1;
      if (c > maxColsUsed) maxColsUsed = c;
      final rowsN = r['rows'] as int;
      if (rowsN < minRows) minRows = rowsN;
    }
    fullByOpts[opts] = {
      'ok': ok.length,
      'blocked': blocked,
      'lastOkQ': ok.isEmpty ? null : ok.last['q'],
      'maxFit': OmrLayoutProfile.maxFitItems(
        form: const OmrLayoutForm(
          orientation: OmrLayoutOrientation.lengthwise,
          pageFill: OmrLayoutPageFill.full,
        ),
        optionsCount: opts,
      ),
      'maxColsUsed': maxColsUsed,
      'minRowsAmongOk': ok.isEmpty ? null : minRows,
      // Sample every Q's cols×rows for transparency
      'packs': [
        for (final r in ok)
          '${r['q']}:${r['cols']}x${r['rows']}',
      ],
    };
  }

  // Spot-check: packs beyond preferred 5-col capacity may use 6–8 cols,
  // but only with enough rows to stay tall.
  final fullOk = rows.where(
    (r) => r['form'] == 'lengthwise_full' && r['ok'] == true,
  );
  final overPreferredFull = fullOk.where((r) {
    final q = r['q'] as int;
    final cols = r['cols'] as int;
    return q <= OmrLayoutProfile.maxColumnsLengthwise *
            OmrLayoutProfile.maxRowsPerColumn &&
        cols > OmrLayoutProfile.maxColumnsLengthwise;
  });
  final highQExtraCols = fullOk.where((r) {
    final q = r['q'] as int;
    final cols = r['cols'] as int;
    return q > OmrLayoutProfile.maxColumnsLengthwise *
            OmrLayoutProfile.maxRowsPerColumn &&
        cols > OmrLayoutProfile.maxColumnsLengthwise;
  });

  final out = {
    'generatedAt': DateTime.now().toIso8601String(),
    'scope':
        'Vertical-balance audit: Automatic packs Q∈[5,200] × opts∈[2,6] × full/half/¼',
    'floors': {
      'maxColumnsLengthwise': OmrLayoutProfile.maxColumnsLengthwise,
      'absoluteMaxColumnsLengthwise':
          OmrLayoutProfile.absoluteMaxColumnsLengthwise,
      'maxColumnsQuarter': OmrLayoutProfile.maxColumnsQuarter,
      'maxRowsPerColumn': OmrLayoutProfile.maxRowsPerColumn,
      'minBalancedRows': OmrLayoutProfile.minBalancedRows,
      'minRowHeightDense': OmrLayoutProfile.minRowHeightDense,
      'densePackMargin': OmrLayoutProfile.densePackMargin,
    },
    'totals': {
      'checked': rows.length,
      'ok': okCount,
      'blocked': blockedCount,
      'shapeViolations': violations.length,
    },
    'fullColumnHistogram': fullColHist.map((k, v) => MapEntry('$k', v)),
    'fullByOpts': fullByOpts.map((k, v) => MapEntry('$k', v)),
    'violations': violations,
    'overPreferredFullCount': overPreferredFull.length,
    'highQExtraColsCount': highQExtraCols.length,
    'findings': [
      'Checked ${rows.length} Automatic packs.',
      'Shape violations (too wide / pancake / 1-col skyscraper): ${violations.length}.',
      'Full-page packs using >5 columns while Q≤155 (should be 0): ${overPreferredFull.length}.',
      'Full-page high-Q packs using 6–8 tall columns (Q>155): ${highQExtraCols.length}.',
      for (var opts = 2; opts <= 6; opts++)
        'Full × ${opts} choices: maxFit=${fullByOpts[opts]!['maxFit']}, '
            'lastOk=${fullByOpts[opts]!['lastOkQ']}, '
            'maxColsUsed=${fullByOpts[opts]!['maxColsUsed']}.',
      if (violations.isEmpty && overPreferredFull.isEmpty)
        'PASS: every accepted custom pack is tall/vertical within column caps.'
      else
        'FAIL: ${violations.length} shape + ${overPreferredFull.length} over-preferred packs.',
    ],
  };

  File('tool/custom_vertical_pack_audit.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));

  stdout.writeln(jsonEncode(out['totals']));
  for (final f in out['findings'] as List) {
    stdout.writeln(f);
  }
  if (violations.isNotEmpty || overPreferredFull.isNotEmpty) {
    stdout.writeln('First violations:');
    for (final v in [...violations, ...overPreferredFull].take(15)) {
      stdout.writeln('  $v');
    }
    exitCode = 1;
  }
}
