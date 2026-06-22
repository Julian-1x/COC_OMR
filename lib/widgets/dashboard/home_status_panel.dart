import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_shadows.dart';
import 'package:omr_app/theme/app_typography.dart';
import 'package:omr_app/widgets/animated_percent_text.dart';

/// One class row on the home status panel.
class HomeStatusSectionRow {
  const HomeStatusSectionRow({
    required this.name,
    required this.pending,
    required this.totalStudents,
    required this.scannedStudents,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBackground,
  });

  final String name;
  final int pending;
  final int totalStudents;
  final int scannedStudents;
  final String statusLabel;
  final Color statusColor;
  final Color statusBackground;
}

/// Optional urgent next step shown at the bottom of the panel.
class HomeStatusNextAction {
  const HomeStatusNextAction({
    required this.message,
    required this.icon,
    required this.onTap,
  });

  final String message;
  final IconData icon;
  final VoidCallback onTap;
}

/// Replaces the large green progress hero — compact progress + priority classes.
class HomeStatusPanel extends StatelessWidget {
  const HomeStatusPanel({
    super.key,
    required this.totalStudents,
    required this.scannedStudents,
    required this.pending,
    required this.progress,
    required this.sections,
    required this.onSectionTap,
    this.nextAction,
    this.allClassesComplete = false,
  });

  final int totalStudents;
  final int scannedStudents;
  final int pending;
  final double progress;
  final List<HomeStatusSectionRow> sections;
  final ValueChanged<String> onSectionTap;
  final HomeStatusNextAction? nextAction;
  final bool allClassesComplete;

  @override
  Widget build(BuildContext context) {
    final completion =
        totalStudents == 0 ? 0 : (progress * 100).round().clamp(0, 100);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.brandBorder),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: _ProgressHeader(
              totalStudents: totalStudents,
              scannedStudents: scannedStudents,
              pending: pending,
              progress: progress,
              completion: completion,
            ),
          ),
          const Divider(height: 1, color: AppColors.brandBorder),
          Expanded(
            child: _SectionListArea(
              sections: sections,
              allClassesComplete: allClassesComplete,
              totalStudents: totalStudents,
              onSectionTap: onSectionTap,
            ),
          ),
          if (nextAction != null) ...[
            const Divider(height: 1, color: AppColors.brandBorder),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: nextAction!.onTap,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        nextAction!.icon,
                        size: 20,
                        color: AppColors.brandGreenDark,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'What to do next',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nextAction!.message,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandText,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.brandMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.totalStudents,
    required this.scannedStudents,
    required this.pending,
    required this.progress,
    required this.completion,
  });

  final int totalStudents;
  final int scannedStudents;
  final int pending;
  final double progress;
  final int completion;

  @override
  Widget build(BuildContext context) {
    final progressLine = totalStudents == 0
        ? 'Import a roster to begin'
        : '$scannedStudents of $totalStudents students graded';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Text(
                'Grading progress',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
            ),
            if (totalStudents > 0)
              AnimatedPercentText(
                value: completion,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandGreenDark,
                  height: 1,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          progressLine,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.brandMuted,
            height: 1.35,
          ),
        ),
        if (totalStudents > 0 && pending > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$pending still pending',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD97706),
            ),
          ),
        ],
        if (totalStudents > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppColors.brandSurface,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.brandGreen,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionListArea extends StatelessWidget {
  const _SectionListArea({
    required this.sections,
    required this.allClassesComplete,
    required this.totalStudents,
    required this.onSectionTap,
  });

  final List<HomeStatusSectionRow> sections;
  final bool allClassesComplete;
  final int totalStudents;
  final ValueChanged<String> onSectionTap;

  @override
  Widget build(BuildContext context) {
    if (totalStudents == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Import students in Exam prep below, then pick a class here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.brandMuted,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    if (allClassesComplete && sections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.brandGreen,
                size: 32,
              ),
              SizedBox(height: 8),
              Text(
                'All classes graded',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Open a class to review scores or export results.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.brandMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No classes yet — add a section after importing.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.brandMuted,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final section = sections[index];
        final detail = section.pending > 0
            ? '${section.pending} pending'
            : section.scannedStudents > 0
                ? '${section.scannedStudents} graded'
                : '${section.totalStudents} students';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSectionTap(section.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.brandMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: section.statusBackground,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      section.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: section.statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.brandMuted,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
