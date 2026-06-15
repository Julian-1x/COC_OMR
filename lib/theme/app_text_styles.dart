import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';

abstract final class AppTextStyles {
  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: AppColors.brandText,
  );

  static const TextStyle pageSubtitle = TextStyle(
    color: AppColors.brandMuted,
    height: 1.35,
    fontSize: 14,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: AppColors.brandMuted,
    letterSpacing: 0.4,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w800,
    color: AppColors.brandText,
  );

  static const TextStyle cardSubtitle = TextStyle(
    fontSize: 13,
    color: AppColors.brandMuted,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.brandMuted,
    letterSpacing: 0.3,
  );
}
