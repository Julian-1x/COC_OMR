import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';

/// Named text styles for consistent typography across the app.
abstract final class AppTypography {
  static TextTheme textTheme = TextTheme(
    displaySmall: pageTitle,
    headlineSmall: sectionTitle,
    titleLarge: cardTitle,
    titleMedium: listTitle,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: captionMuted,
    labelLarge: buttonLabel,
    labelMedium: chipLabel,
    labelSmall: captionMuted,
  );

  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: AppColors.brandText,
    height: 1.2,
    letterSpacing: -0.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.brandText,
    height: 1.25,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.brandText,
    height: 1.3,
  );

  static const TextStyle listTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.brandText,
    height: 1.35,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.brandText,
    height: 1.4,
  );

  static const TextStyle captionMuted = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.brandMuted,
    height: 1.35,
  );

  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.brandMuted,
    letterSpacing: 0.6,
    height: 1.2,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.brandText,
    height: 1.1,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  static const TextStyle chipLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle scannerStatus = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.3,
  );

  static const TextStyle scannerHint = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.white70,
    height: 1.35,
  );
}
