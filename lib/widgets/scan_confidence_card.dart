import 'package:flutter/material.dart';
import 'package:omr_app/services/scan_confidence_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/theme/app_typography.dart';

/// Compact teacher-facing risk strip for a scan confidence report.
class ScanConfidenceCard extends StatelessWidget {
  const ScanConfidenceCard({
    super.key,
    required this.report,
    this.onReview,
    this.compact = false,
  });

  final ScanConfidenceReport report;
  final VoidCallback? onReview;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsFor(report.level);
    final reasons = report.topReasons;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.$2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(colors.$4, size: compact ? 16 : 18, color: colors.$3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.title,
                  style: AppTypography.listTitle.copyWith(
                    color: colors.$3,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• $reason',
                  style: AppTypography.captionMuted.copyWith(
                    color: colors.$3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
          if (onReview != null && report.requiresReview) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onReview,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.$3,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Review this sheet'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// (bg, border, accent, icon)
  static (Color, Color, Color, IconData) _colorsFor(ScanConfidenceLevel level) {
    switch (level) {
      case ScanConfidenceLevel.safe:
        return (
          AppColors.statusSuccessBg,
          AppColors.statusSuccessBorder,
          AppColors.statusSuccess,
          Icons.check_circle_rounded,
        );
      case ScanConfidenceLevel.check:
        return (
          AppColors.statusWarningBg,
          AppColors.statusWarningBorder,
          AppColors.statusWarning,
          Icons.flag_rounded,
        );
      case ScanConfidenceLevel.mustReview:
        return (
          AppColors.statusDangerBg,
          AppColors.statusDangerBorder,
          AppColors.statusDanger,
          Icons.warning_rounded,
        );
    }
  }
}

/// Small chip for lists (review queue, exam board).
class ScanConfidenceBadge extends StatelessWidget {
  const ScanConfidenceBadge({
    super.key,
    required this.level,
  });

  final ScanConfidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final report = ScanConfidenceReport(
      level: level,
      reasons: const <String>[],
      flaggedQuestions: const <int>[],
    );
    final colors = ScanConfidenceCard._colorsFor(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.$2),
      ),
      child: Text(
        report.title,
        style: AppTypography.chipLabel.copyWith(
          color: colors.$3,
          fontSize: 11,
        ),
      ),
    );
  }
}
