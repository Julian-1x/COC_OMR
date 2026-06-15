import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';

/// PIN entry with dot display and on-screen numeric keypad.
class AppPinInput extends StatefulWidget {
  const AppPinInput({
    super.key,
    required this.controller,
    this.maxLength = 6,
    this.minLength = 4,
    this.label,
    this.onCompleted,
    this.enabled = true,
    this.compact = false,
  });

  final TextEditingController controller;
  final int maxLength;
  final int minLength;
  final String? label;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool compact;

  @override
  State<AppPinInput> createState() => _AppPinInputState();
}

class _AppPinInputState extends State<AppPinInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPinChanged);
  }

  @override
  void didUpdateWidget(AppPinInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPinChanged);
      widget.controller.addListener(_onPinChanged);
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPinChanged);
    super.dispose();
  }

  void _onPinChanged() {
    final pin = widget.controller.text;
    if (pin.length == widget.maxLength && widget.onCompleted != null) {
      widget.onCompleted!(pin);
    }
    setState(() {});
  }

  void _appendDigit(String digit) {
    if (!widget.enabled) return;
    if (widget.controller.text.length >= widget.maxLength) return;
    widget.controller.text = '${widget.controller.text}$digit';
    setState(() {});
    HapticFeedback.lightImpact();
  }

  void _backspace() {
    if (!widget.enabled) return;
    final current = widget.controller.text;
    if (current.isEmpty) return;
    widget.controller.text = current.substring(0, current.length - 1);
    setState(() {});
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.controller.text;
    final dotCount = pin.length.clamp(0, widget.maxLength);

    return Column(
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              color: AppColors.brandText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.maxLength, (index) {
            final filled = index < dotCount;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AppColors.brandGreen : Colors.white,
                border: Border.all(
                  color: filled
                      ? AppColors.brandGreenDark
                      : AppColors.brandMuted.withValues(alpha: 0.55),
                  width: filled ? 2 : 2,
                ),
                boxShadow: filled
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildKeypad(),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${widget.minLength}-${widget.maxLength} digits',
          style: const TextStyle(
            color: AppColors.brandMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];
    final keyHeight =
        widget.compact ? AppSpacing.buttonHeight - 10 : AppSpacing.touchTarget;
    final rowGap = widget.compact ? AppSpacing.xs : AppSpacing.sm;

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: EdgeInsets.only(bottom: rowGap),
          child: Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildKey(key, keyHeight: keyHeight),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKey(String key, {required double keyHeight}) {
    if (key.isEmpty) {
      return SizedBox(height: keyHeight);
    }

    if (key == 'del') {
      return Material(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: widget.enabled ? _backspace : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: SizedBox(
            height: keyHeight,
            child: Icon(
              Icons.backspace_outlined,
              color: AppColors.brandMuted,
              size: widget.compact ? 20 : 24,
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        onTap: widget.enabled ? () => _appendDigit(key) : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          height: keyHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: widget.compact ? 20 : 22,
              fontWeight: FontWeight.w700,
              color: AppColors.brandText,
            ),
          ),
        ),
      ),
    );
  }
}
