import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/utils/answer_key_scope.dart';

/// Compact badge: Shared / One section / No section.
class AnswerKeyScopeBadge extends StatelessWidget {
  const AnswerKeyScopeBadge({
    super.key,
    required this.subject,
    this.compact = false,
  });

  final Subject subject;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scope = AnswerKeyScope.of(subject);
    final Color bg;
    final Color fg;
    final Color border;
    switch (scope.kind) {
      case AnswerKeyScopeKind.shared:
        bg = AppColors.brandGreen.withValues(alpha: 0.12);
        fg = AppColors.brandGreen;
        border = AppColors.brandBorder;
      case AnswerKeyScopeKind.sectionOnly:
        bg = AppColors.warningBg;
        fg = AppColors.warningText;
        border = AppColors.warningBorder;
      case AnswerKeyScopeKind.unassigned:
        bg = AppColors.statusDangerBg;
        fg = AppColors.error;
        border = AppColors.error.withValues(alpha: 0.35);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        compact ? scope.shortBadge : scope.badgeLabel,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
