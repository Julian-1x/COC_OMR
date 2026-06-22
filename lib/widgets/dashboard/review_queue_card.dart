import 'dart:io';

import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_shadows.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/theme/app_typography.dart';

/// Flagged scan row in the dashboard review queue sheet.
class ReviewQueueCard extends StatelessWidget {
  const ReviewQueueCard({
    super.key,
    required this.scan,
    required this.studentName,
    required this.onRescan,
    required this.onApprove,
    this.onPreviewImage,
  });

  final ScanResult scan;
  final String studentName;
  final Future<void> Function() onRescan;
  final Future<void> Function() onApprove;
  final VoidCallback? onPreviewImage;

  @override
  Widget build(BuildContext context) {
    final confidencePercent = (scan.confidence * 100).round();
    final isLowConfidence = scan.isLowConfidence;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isLowConfidence
                        ? AppColors.statusDangerBg
                        : AppColors.statusWarningBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    scan.studentOmrId,
                    style: AppTypography.chipLabel.copyWith(
                      color: isLowConfidence
                          ? AppColors.statusDanger
                          : AppColors.statusWarning,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(studentName, style: AppTypography.listTitle),
                      const SizedBox(height: 2),
                      Text(scan.subjectName, style: AppTypography.captionMuted),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${scan.scoreDisplay}/${scan.totalQuestions}',
                      style: AppTypography.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLowConfidence
                              ? Icons.warning_rounded
                              : Icons.flag_rounded,
                          size: 14,
                          color: isLowConfidence
                              ? AppColors.statusDanger
                              : AppColors.statusWarning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLowConfidence ? '$confidencePercent%' : 'Flagged',
                          style: AppTypography.captionMuted.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isLowConfidence
                                ? AppColors.statusDanger
                                : AppColors.statusWarning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (scan.reviewReasons.isNotEmpty ||
                scan.flaggedQuestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusWarningBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.statusWarningBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (scan.reviewReasons.isNotEmpty)
                      ...scan.reviewReasons.map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• $reason',
                            style: AppTypography.captionMuted.copyWith(
                              color: AppColors.warningText,
                            ),
                          ),
                        ),
                      ),
                    if (scan.flaggedQuestions.isNotEmpty)
                      Text(
                        'Check question${scan.flaggedQuestions.length == 1 ? '' : 's'}: '
                        '${(scan.flaggedQuestions.toList()..sort()).join(', ')}',
                        style: AppTypography.captionMuted.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.warningText,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (scan.scannedImagePath != null &&
                scan.scannedImagePath!.isNotEmpty &&
                File(scan.scannedImagePath!).existsSync() &&
                onPreviewImage != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onPreviewImage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Image.file(
                        File(scan.scannedImagePath!),
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      const Positioned(
                        right: 8,
                        bottom: 8,
                        child: Icon(
                          Icons.zoom_out_map_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onRescan(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandGreenDark,
                      side: const BorderSide(color: AppColors.brandGreen),
                    ),
                    child: const Text('Rescan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onApprove(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
