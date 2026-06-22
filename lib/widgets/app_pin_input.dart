import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/app_primary_button.dart';

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

/// Choose + confirm PIN on one screen — one keypad, no second page.
class AppPinSetupFlow extends StatefulWidget {
  const AppPinSetupFlow({
    super.key,
    required this.onConfirmed,
    this.enabled = true,
    this.isLoading = false,
  });

  final Future<void> Function(String pin) onConfirmed;
  final bool enabled;
  final bool isLoading;

  @override
  State<AppPinSetupFlow> createState() => _AppPinSetupFlowState();
}

class _AppPinSetupFlowState extends State<AppPinSetupFlow> {
  final TextEditingController _controller = TextEditingController();
  String? _firstPin;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPinChanged);
  }

  void _onPinChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onPinChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _pinReady {
    final pin = _controller.text.trim();
    return RegExp(r'^\d{4,6}$').hasMatch(pin);
  }

  void _startOver() {
    setState(() {
      _firstPin = null;
      _confirming = false;
      _controller.clear();
    });
  }

  Future<void> _onPrimaryPressed() async {
    final pin = _controller.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      return;
    }

    if (!_confirming) {
      setState(() {
        _firstPin = pin;
        _confirming = true;
        _controller.clear();
      });
      return;
    }

    if (pin != _firstPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PINs do not match. Try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _startOver();
      return;
    }

    await widget.onConfirmed(pin);
  }

  @override
  Widget build(BuildContext context) {
    final label = _confirming ? 'Enter PIN again' : 'Choose a PIN';
    final hint = _confirming
        ? 'Same digits as before — backs up to your account for new phones.'
        : '4–6 digits for exam-day unlock.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          hint,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.brandMuted,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppPinInput(
          key: ValueKey(_confirming ? 'pin-confirm' : 'pin-enter'),
          controller: _controller,
          label: label,
          enabled: widget.enabled && !widget.isLoading,
          compact: true,
        ),
        const SizedBox(height: AppSpacing.md),
        AppPrimaryButton(
          label: _confirming ? 'Save PIN' : 'Continue',
          icon: _confirming ? Icons.verified_rounded : Icons.arrow_forward_rounded,
          isLoading: widget.isLoading,
          onPressed: widget.enabled && !widget.isLoading && _pinReady
              ? () => _onPrimaryPressed()
              : null,
        ),
        if (_confirming) ...[
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: widget.isLoading ? null : _startOver,
            child: const Text('Start over'),
          ),
        ],
      ],
    );
  }
}
