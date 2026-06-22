import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/theme/app_typography.dart';
import 'package:omr_app/widgets/app_primary_button.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 52,
            color: AppColors.brandMuted.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(title, style: AppTypography.sectionTitle),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.brandMuted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: actionLabel!,
              icon: actionIcon ?? Icons.arrow_forward_rounded,
              expanded: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
