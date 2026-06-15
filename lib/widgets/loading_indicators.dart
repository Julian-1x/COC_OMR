import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';

/// Reusable loading indicators for consistent UI
class LoadingIndicators {
  /// Primary loading spinner with brand color
  static Widget primary({double? size, Color? color}) {
    return SizedBox(
      width: size ?? 24,
      height: size ?? 24,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppColors.brandGreen,
        ),
      ),
    );
  }

  /// Loading spinner for buttons (white)
  static Widget button({double? size}) {
    return SizedBox(
      width: size ?? 20,
      height: size ?? 20,
      child: const CircularProgressIndicator(
        strokeWidth: 2.5,
        color: Colors.white,
      ),
    );
  }

  /// Full screen loading with backdrop
  static Widget fullScreen({String message = 'Loading...'}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                primary(size: 32),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Inline loading for data tables/lists
  static Widget inline({String message = 'Loading data...'}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          primary(size: 32),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// Linear progress indicator for operations
  static Widget linear({Color? color}) {
    return LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.grey.shade200,
      valueColor: AlwaysStoppedAnimation<Color>(
        color ?? const Color(0xFF10B981),
      ),
    );
  }
}

/// Loading button wrapper
class LoadingButton extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  const LoadingButton({
    super.key,
    required this.child,
    required this.isLoading,
    this.onPressed,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: style,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isLoading
            ? LoadingIndicators.button()
            : child,
      ),
    );
  }
}

/// Loading overlay for any widget
class LoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;
  final String message;

  const LoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
    this.message = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.1),
            child: LoadingIndicators.fullScreen(message: message),
          ),
      ],
    );
  }
}
