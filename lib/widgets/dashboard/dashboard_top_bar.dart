import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/app_section_header.dart';

class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onMenuTap,
    this.notificationCount = 0,
    this.onNotificationTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenuTap;
  final int notificationCount;
  final VoidCallback? onNotificationTap;

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
              child: const Icon(Icons.person_rounded, color: AppColors.brandText),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: AppSectionHeader(title: title, subtitle: subtitle),
        ),
        if (onNotificationTap != null) ...[
          const SizedBox(width: 10),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onNotificationTap,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.brandBorder),
                ),
                child: Badge(
                  isLabelVisible: notificationCount > 0,
                  label: Text(
                    notificationCount > 9 ? '9+' : '$notificationCount',
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: const Color(0xFFD97706),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.brandText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
