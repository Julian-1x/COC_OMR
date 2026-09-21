import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/pages/answer_key_page.dart';
import 'package:omr_app/pages/custom_sheet_layout_editor_page.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';

class CustomSheetLayoutsPage extends StatefulWidget {
  const CustomSheetLayoutsPage({
    super.key,
    this.openNewLayoutOnStart = false,
    this.promptAnswerKeyAfterCreate = true,
  });

  /// When true, opens the new-layout editor immediately (e.g. from print).
  final bool openNewLayoutOnStart;

  /// After saving a *new* layout, require creating an answer key next.
  /// Set false when opened from the answer-key editor (already on that path).
  final bool promptAnswerKeyAfterCreate;

  @override
  State<CustomSheetLayoutsPage> createState() => _CustomSheetLayoutsPageState();
}

class _CustomSheetLayoutsPageState extends State<CustomSheetLayoutsPage> {
  @override
  void initState() {
    super.initState();
    if (widget.openNewLayoutOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openEditor());
        }
      });
    }
  }

  Future<void> _openEditor([CustomSheetLayout? existing]) async {
    final saved = await Navigator.push<CustomSheetLayout>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomSheetLayoutEditorPage(existing: existing),
      ),
    );
    if (!mounted) {
      return;
    }
    if (saved == null) {
      return;
    }
    setState(() {});

    // New layouts must get an answer key next — otherwise Print Sheets cannot use them.
    if (existing == null && widget.promptAnswerKeyAfterCreate) {
      await _continueToAnswerKey(saved);
    }
  }

  Future<void> _continueToAnswerKey(CustomSheetLayout layout) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Layout saved'),
        content: Text(
          '"${layout.name}" is ready (${layout.totalQuestions} questions). '
          'Next you must create the answer key for this sheet so Print Sheets '
          'and Scan can use it.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Create answer key'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AnswerKeyPage(
          sheetMode: AnswerKeySheetMode.custom,
          initialCustomLayoutId: layout.id,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmDelete(CustomSheetLayout layout) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete layout?'),
        content: Text(
          'Remove "${layout.name}" from your saved layouts? '
          'Answer keys are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await LocalDataStore.instance.deleteCustomSheetLayout(layout.id);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final layouts = List<CustomSheetLayout>.from(globalCustomSheetLayouts)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: AppColors.appCanvas,
      appBar: AppBar(
        title: const Text('Custom sheet layouts'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New layout'),
      ),
      body: layouts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.dashboard_customize_outlined,
                      size: 56,
                      color: AppColors.brandGreen.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No custom sheets yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Skip this for normal 30–100 exams — use Answer Keys · Standard, '
                      'then Print Sheets with "Standard sheet".\n\n'
                      'For short quizzes or special sizes: tap New layout, then you will '
                      'create the matching answer key right away.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.brandMuted),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: layouts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final layout = layouts[index];
                return Material(
                  color: AppColors.brandSurface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openEditor(layout),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.brandBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  layout.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  layout.previewSubtitle,
                                  style: const TextStyle(
                                    color: AppColors.brandMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(layout),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
