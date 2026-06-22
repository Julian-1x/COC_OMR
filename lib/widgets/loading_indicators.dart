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
              color: AppColors.brandMuted,
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
      backgroundColor: AppColors.neutralFill,
      valueColor: AlwaysStoppedAnimation<Color>(
        color ?? AppColors.brandGreen,
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

/// Placeholder rows while class list data is loading.
class ClassesListSkeleton extends StatelessWidget {
  const ClassesListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ShimmerBox(
            height: 88,
            borderRadius: 22,
            delayMs: index * 80,
          ),
        );
      }),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.height,
    required this.borderRadius,
    this.delayMs = 0,
  });

  final double height;
  final double borderRadius;
  final int delayMs;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 + (_controller.value * 2), 0),
              end: Alignment(1 + (_controller.value * 2), 0),
              colors: const [
                Color(0xFFE2E8F0),
                Color(0xFFF1F5F9),
                Color(0xFFE2E8F0),
              ],
            ),
          ),
        );
      },
    );
  }
}
