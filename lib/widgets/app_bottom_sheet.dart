import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';

/// Shared bottom sheet chrome: drag handle, padding, title typography.
abstract final class AppBottomSheet {
  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppColors.brandText,
  );

  static const TextStyle subtitleStyle = TextStyle(
    color: AppColors.brandMuted,
    height: 1.4,
  );

  static const EdgeInsets contentPadding =
      EdgeInsets.fromLTRB(20, 0, 20, 20);

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = false,
    bool useSafeArea = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: isScrollControlled,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final body = Padding(
          padding: contentPadding,
          child: child,
        );
        return useSafeArea ? SafeArea(child: body) : body;
      },
    );
  }

  static Widget header({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: subtitleStyle),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing,
            ],
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
