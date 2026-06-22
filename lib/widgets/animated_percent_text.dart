import 'package:flutter/material.dart';

/// Animates an integer percentage when [value] changes.
class AnimatedPercentText extends StatelessWidget {
  const AnimatedPercentText({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 450),
  });

  final int value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(value),
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, child) {
        return Text(
          '${animated.round()}%',
          textAlign: TextAlign.center,
          style: style,
        );
      },
    );
  }
}
