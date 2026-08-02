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

  /// Bottom sheet capped to [heightFactor] of the screen so long lists scroll.
  static Future<T?> showScrollable<T>({
    required BuildContext context,
    required Widget Function(BuildContext context) builder,
    double heightFactor = 0.85,
    bool showDragHandle = true,
  }) {
    assert(heightFactor > 0 && heightFactor <= 1);
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: showDragHandle,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * heightFactor;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: builder(context),
          ),
        );
      },
    );
  }

  /// Caps [child] so a scroll view can scroll inside an `isScrollControlled` sheet.
  static Widget constrainScrollBody({
    required BuildContext context,
    required Widget child,
    double heightFactor = 0.85,
  }) {
    final maxHeight = MediaQuery.sizeOf(context).height * heightFactor;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: child,
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
