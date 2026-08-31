import 'package:flutter/material.dart';
import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/pages/custom_sheet_layout_editor_page.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';

class CustomSheetLayoutsPage extends StatefulWidget {
  const CustomSheetLayoutsPage({super.key});

  @override
  State<CustomSheetLayoutsPage> createState() => _CustomSheetLayoutsPageState();
}

class _CustomSheetLayoutsPageState extends State<CustomSheetLayoutsPage> {
  Future<void> _openEditor([CustomSheetLayout? existing]) async {
    final saved = await Navigator.push<CustomSheetLayout>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomSheetLayoutEditorPage(existing: existing),
      ),
    );
    if (saved != null && mounted) {
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
                      'You can skip this — normal exams use Print Sheets with '
                      '"Standard sheet" and do not need anything here.\n\n'
                      'For short quizzes: create a layout here, then Answer Key → '
                      'Saved custom to fill the matching answers. '
                      'Print a sample and scan once before exam day.',
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
