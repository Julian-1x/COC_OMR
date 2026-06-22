import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_text_styles.dart';
import 'package:omr_app/utils/section_program.dart';
import 'package:omr_app/widgets/app_empty_state.dart';
import 'package:omr_app/widgets/app_filter_chip.dart';

class ClassesSearchBar extends StatelessWidget {
  const ClassesSearchBar({
    super.key,
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search section (e.g. BSIT-01, BSECE-02)',
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.brandMuted),
        suffixIcon: searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, color: AppColors.brandMuted),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandGreen, width: 1.5),
        ),
      ),
    );
  }
}

class ClassesFilterChips extends StatelessWidget {
  const ClassesFilterChips({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _filters = <(int, String)>[
    (0, 'All'),
    (1, 'In progress'),
    (2, 'Complete'),
    (3, 'Not started'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            AppFilterChip(
              label: _filters[i].$2,
              selected: selectedIndex == _filters[i].$1,
              onTap: () => onSelected(_filters[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class ClassesProgramFilterChips extends StatelessWidget {
  const ClassesProgramFilterChips({
    super.key,
    required this.programs,
    required this.selectedProgram,
    required this.onSelected,
  });

  final List<String> programs;
  final String? selectedProgram;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Program',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.brandMuted,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              AppFilterChip(
                label: 'All programs',
                selected: selectedProgram == null,
                onTap: () => onSelected(null),
              ),
              for (final program in programs) ...[
                const SizedBox(width: 8),
                AppFilterChip(
                  label: SectionProgram.chipLabel(program),
                  selected: selectedProgram == program,
                  onTap: () => onSelected(program),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ClassGroupHeader extends StatelessWidget {
  const ClassGroupHeader({
    super.key,
    required this.groupKey,
    required this.programTitle,
    required this.count,
    required this.studentCount,
    required this.isExpanded,
    required this.onToggle,
  });

  final String groupKey;
  final String programTitle;
  final int count;
  final int studentCount;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.brandBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      SectionProgram.chipLabel(groupKey),
                      style: const TextStyle(
                        color: AppColors.brandGreenDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        programTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandText,
                        ),
                      ),
                      Text(
                        '$count ${count == 1 ? 'section' : 'sections'} · $studentCount students',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.brandMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClassesNoMatchesCard extends StatelessWidget {
  const ClassesNoMatchesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No classes match',
        message: 'Try a different search or filter.',
      ),
    );
  }
}
