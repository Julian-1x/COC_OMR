import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/import_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/utils/student_identity.dart';
import 'package:omr_app/utils/user_error_messages.dart';

Future<ManualStudentResult?> showAddStudentDialog(
  BuildContext context, {
  String? initialSection,
}) {
  return showDialog<ManualStudentResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AddStudentDialog(initialSection: initialSection),
  );
}

class _AddStudentDialog extends StatefulWidget {
  const _AddStudentDialog({this.initialSection});

  final String? initialSection;

  @override
  State<_AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<_AddStudentDialog> {
  final _schoolIdController = TextEditingController();
  final _nameController = TextEditingController();
  late final TextEditingController _sectionController;
  String? _errorText;
  bool _saving = false;

  List<String> get _knownSections {
    final names = <String>{
      ...globalSections
          .map((section) => section.name.trim())
          .where((name) => name.isNotEmpty),
      ...globalStudentDatabase
          .map((student) => student.section.trim())
          .where((name) => name.isNotEmpty),
    }.toList()
      ..sort();
    return names;
  }

  @override
  void initState() {
    super.initState();
    _sectionController = TextEditingController(
      text: widget.initialSection?.trim() ?? '',
    );
  }

  @override
  void dispose() {
    _schoolIdController.dispose();
    _nameController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }

    final schoolId = _schoolIdController.text.trim();
    final name = _nameController.text.trim();
    final section = _sectionController.text.trim();
    if (schoolId.isEmpty || name.isEmpty || section.isEmpty) {
      setState(() {
        _errorText = 'Enter student ID, name, and section.';
      });
      return;
    }

    final existing = findStudentBySchoolId(globalStudentDatabase, schoolId);
    if (existing != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Student already on roster'),
          content: Text(
            '${existing.name} (${existing.schoolId}) already has OMR '
            '${existing.omrId} in ${existing.section}.\n\n'
            'Update name and section and keep the same OMR ID?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Keep OMR ID'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final result = await ImportService.addManualStudent(
        schoolId: schoolId,
        name: name,
        section: section,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _errorText = UserErrorMessages.friendlyImportError(error.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _knownSections;
    return AlertDialog(
      title: const Text('Add student'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'For late enrollees not in the Excel roster. OMR ID is assigned automatically.',
              style: TextStyle(color: AppColors.brandMuted, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _schoolIdController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'e.g. 2025-0123',
                border: OutlineInputBorder(),
              ),
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Student name',
                hintText: 'First name then last name (e.g. Juan Dela Cruz)',
                border: OutlineInputBorder(),
              ),
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sectionController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Section',
                hintText: 'e.g. BSIT-1A',
                border: OutlineInputBorder(),
              ),
              enabled: !_saving,
            ),
            if (sections.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sections.take(8).map((section) {
                  final selected = normalizeSectionName(_sectionController.text) ==
                      normalizeSectionName(section);
                  return FilterChip(
                    label: Text(section),
                    selected: selected,
                    onSelected: _saving
                        ? null
                        : (_) {
                            setState(() {
                              _sectionController.text = section;
                            });
                          },
                  );
                }).toList(),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(color: AppColors.error, height: 1.35),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            foregroundColor: Colors.white,
          ),
          child: Text(_saving ? 'Saving…' : 'Add student'),
        ),
      ],
    );
  }
}
