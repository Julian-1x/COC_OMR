import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/app_section_header.dart';

class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onMenuTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onMenuTap,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.brandBorder),
              ),
              child: const Icon(Icons.menu_rounded, color: AppColors.brandText),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: AppSectionHeader(title: title, subtitle: subtitle),
        ),
      ],
    );
  }
}
