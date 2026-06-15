import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/loading_indicators.dart';

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? LoadingIndicators.button()
          : Icon(icon ?? Icons.arrow_forward_rounded),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandGreen,
        disabledBackgroundColor: AppColors.brandGreen.withValues(alpha: 0.65),
        foregroundColor: Colors.white,
        minimumSize: expanded
            ? const Size.fromHeight(AppSpacing.buttonHeight)
            : const Size(0, AppSpacing.buttonHeight),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );

    if (!expanded) {
      return child;
    }
    return SizedBox(width: double.infinity, child: child);
  }
}
