import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart' as generator;
import 'package:omr_app/services/answer_key_io_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/answer_key_delete_dialog.dart';
import 'package:omr_app/utils/user_error_messages.dart';

enum AnswerKeyEditorAction { updated, deleted }

class AnswerKeyEditorResult {
  const AnswerKeyEditorResult.updated(this.subject)
      : action = AnswerKeyEditorAction.updated,
        deletionSummary = null,
        subjectName = null;

  const AnswerKeyEditorResult.deleted({
    required this.subjectName,
    required this.deletionSummary,
  })  : action = AnswerKeyEditorAction.deleted,
        subject = null;

  final AnswerKeyEditorAction action;
  final Subject? subject;
  final String? subjectName;
  final SubjectDeletionSummary? deletionSummary;
}

class AnswerKeyPage extends StatefulWidget {
  final Subject? subjectToEdit; // For editing existing subject
  final Subject? templateSubject; // For cloning to a new subject
  final String? initialSection;
  /// When editing from a per-section row, the section the teacher tapped.
  final String? editSectionFocus;

  const AnswerKeyPage({
    super.key,
    this.subjectToEdit,
    this.templateSubject,
    this.initialSection,
    this.editSectionFocus,
  });

  @override
  State<AnswerKeyPage> createState() => _AnswerKeyPageState();
}

class _AnswerKeyPageState extends State<AnswerKeyPage> {
  static const Color _brandGreen = AppColors.brandGreen;
  static const Color _brandGreenDark = AppColors.brandGreenDark;
  static const Color _brandSurface = AppColors.brandSurface;
  static const Color _brandBorder = AppColors.brandBorder;
  static const Color _brandText = AppColors.brandText;
  static const Color _brandMuted = AppColors.brandMuted;
  static const Color _editorCanvas = AppColors.appCanvas;
  static const Color _fieldFill = Colors.white;
  static const Color _fieldBorder = AppColors.borderLight;
  static const Color _warningOrange = AppColors.cautionAccent;
  static const List<String> _answerChoices =
      OmrPageConstants.answerOptionLabels;
  static const Set<String> _answerChoiceSet = {'A', 'B', 'C', 'D', 'E'};
  static const List<int> _supportedQuestionCounts = [
    30,
    40,
    50,
    60,
    70,
    80,
    90,
    100,
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();
  final Map<int, Set<String>> _correctAnswers = {};
  int _questionCount = 50;
  int _editorStep = 0;
  bool _isEditing = false;
  bool _showFullLayoutGrid = false;
  Set<String> _selectedSections = {};
  bool _usePartialCredit = false;
  bool _splitEditMode = false;
  bool _sharedEditWarning = false;
  bool _sharedEditPromptHandled = false;

  String? get _focusedSection {
    final raw = widget.editSectionFocus?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _canonicalizeSectionName(raw);
  }

  List<String> _otherSectionsForSharedEdit(Subject subject) {
    final focus = _focusedSection;
    if (focus == null) {
      return const <String>[];
    }
    return (subject.sectionNames ?? const <String>[])
        .map(_canonicalizeSectionName)
        .where((section) => section != focus)
        .toList()
      ..sort();
  }

  int _scanCountForSectionOnSubject(String subjectId, String sectionName) {
    final normalized = _normalizeSectionName(sectionName);
    final omrIds = globalStudentDatabase
        .where(
          (student) => _normalizeSectionName(student.section) == normalized,
        )
        .map((student) => student.omrId)
        .toSet();
    return globalScanResults
        .where(
          (result) =>
              result.subjectId == subjectId &&
              omrIds.contains(result.studentOmrId),
        )
        .length;
  }

  Map<String, String> _buildSectionQrData({
    required String subjectId,
    required String subjectName,
    required List<String> sections,
    required int passingScore,
    required DateTime examDate,
    int? totalQuestions,
  }) {
    final questions = totalQuestions ?? _questionCount;
    final sectionQrData = <String, String>{};
    for (final section in sections) {
      sectionQrData[section] =
          generator.AnswerSheetGenerator.buildSheetQrCodeDataForSection(
        subjectId: subjectId,
        subjectName: subjectName,
        totalQuestions: questions,
        passingScore: passingScore,
        examDate: examDate,
        sectionName: section,
      );
    }
    return sectionQrData;
  }

  Future<void> _promptSharedKeyEditMode() async {
    final subject = widget.subjectToEdit;
    final focus = _focusedSection;
    if (subject == null || focus == null || _sharedEditPromptHandled) {
      return;
    }

    final sections = (subject.sectionNames ?? const <String>[])
        .map(_canonicalizeSectionName)
        .toSet();
    if (sections.length <= 1 || !sections.contains(focus)) {
      return;
    }

    _sharedEditPromptHandled = true;
    final others = _otherSectionsForSharedEdit(subject);
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shared Answer Key'),
        content: Text(
          others.isEmpty
              ? 'This answer key is assigned to multiple sections.'
              : 'This key is shared with ${others.join(', ')}. '
                  'To change only $focus, split it into a separate key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'shared'),
            child: const Text('Edit shared key'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'split'),
            child: const Text('Split section'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    setState(() {
      if (choice == 'split') {
        _splitEditMode = true;
        _sharedEditWarning = false;
        _selectedSections = {focus};
      } else {
        _splitEditMode = false;
        _sharedEditWarning = true;
        _selectedSections = sections;
      }
    });
  }

  List<String> _getSectionNames() {
    final sections =
        globalSections.map((s) => _canonicalizeSectionName(s.name)).toSet();
    for (final student in globalStudentDatabase) {
      sections.add(_canonicalizeSectionName(student.section));
    }
    for (final subject in globalSubjects) {
      sections.addAll(
        (subject.sectionNames ?? const <String>[])
            .map(_canonicalizeSectionName),
      );
    }
    sections.addAll(_selectedSections.map(_canonicalizeSectionName));
    final sorted = sections.toList()..sort();
    return sorted;
  }

  int get _answeredQuestionsCount =>
      _correctAnswers.values.where((answers) => answers.isNotEmpty).length;

  double get _completionProgress =>
      _questionCount == 0 ? 0 : _answeredQuestionsCount / _questionCount;

  int get _remainingQuestionsCount => _questionCount - _answeredQuestionsCount;

  List<int> get _unansweredQuestions {
    return [
      for (var question = 1; question <= _questionCount; question++)
        if ((_correctAnswers[question] ?? const <String>{}).isEmpty) question,
    ];
  }

  List<int> get _invalidAnswerQuestions {
    final invalidQuestions = <int>{};
    for (final entry in _correctAnswers.entries) {
      if (entry.key < 1 || entry.key > _questionCount) {
        invalidQuestions.add(entry.key);
        continue;
      }

      final providedAnswers = entry.value
          .map((answer) => answer.trim().toUpperCase())
          .where((answer) => answer.isNotEmpty)
          .toSet();
      final validAnswers = _sanitizeAnswers(entry.value);
      if (providedAnswers.length != validAnswers.length) {
        invalidQuestions.add(entry.key);
      }
    }

    return invalidQuestions.toList()..sort();
  }

  List<String> get _reviewWarnings {
    final warnings = <String>[];
    final selectedWithoutStudents = _selectedSections.where((section) {
      final normalizedSection = _normalizeSectionName(section);
      return !globalStudentDatabase.any(
        (student) =>
            _normalizeSectionName(student.section) == normalizedSection,
      );
    }).toList()
      ..sort();

    if (selectedWithoutStudents.isNotEmpty) {
      warnings.add(
        'No imported students found for: ${selectedWithoutStudents.join(', ')}.',
      );
    }

    if (!_usePartialCredit && _multiAnswerQuestionCount > 0) {
      warnings.add(
        '$_multiAnswerQuestionCount question(s) have multiple correct answers. Without partial credit, students must mark every correct option for full credit.',
      );
    }

    return warnings;
  }

  List<String> get _reviewIssues {
    final issues = <String>[];
    final availableSections =
        _getSectionNames().map(_normalizeSectionName).toSet();
    final missingSections = _selectedSections
        .where(
          (section) =>
              !availableSections.contains(_normalizeSectionName(section)),
        )
        .toList()
      ..sort();
    final invalidAnswerQuestions = _invalidAnswerQuestions;
    final unansweredQuestions = _unansweredQuestions;

    if (_nameController.text.trim().isEmpty) {
      issues.add('Add a subject name.');
    }
    if (_selectedSections.isEmpty) {
      issues.add('Select at least one section.');
    }
    if (missingSections.isNotEmpty) {
      issues
          .add('Remove unavailable section(s): ${missingSections.join(', ')}.');
    }
    if (!_supportedQuestionCounts.contains(_questionCount)) {
      issues.add('Choose a supported question count.');
    }
    if (invalidAnswerQuestions.isNotEmpty) {
      issues.add(
        'Fix invalid answer choices on question(s): ${invalidAnswerQuestions.take(8).join(', ')}${invalidAnswerQuestions.length > 8 ? '...' : ''}.',
      );
    }
    if (_answeredQuestionsCount == 0) {
      issues.add('Add answers before saving.');
    } else if (unansweredQuestions.isNotEmpty) {
      issues.add(
        'Finish the remaining ${unansweredQuestions.length} question(s): ${unansweredQuestions.take(8).join(', ')}${unansweredQuestions.length > 8 ? '...' : ''}.',
      );
    }
    return issues;
  }

  bool get _canUsePrimaryEditorAction {
    switch (_editorStep) {
      case 0:
        return _nameController.text.trim().isNotEmpty &&
            _selectedSections.isNotEmpty;
      case 1:
        return _answeredQuestionsCount == _questionCount;
      case 2:
        return _reviewIssues.isEmpty;
      default:
        return true;
    }
  }

  String get _primaryEditorHelpText {
    if (_editorStep == 0) {
      if (_nameController.text.trim().isEmpty) {
        return 'Add subject name';
      }
      if (_selectedSections.isEmpty) {
        return 'Select section';
      }
      return 'Details ready';
    }
    if (_editorStep == 1) {
      return _answeredQuestionsCount == _questionCount
          ? 'Ready to review'
          : '$_remainingQuestionsCount answer${_remainingQuestionsCount == 1 ? '' : 's'} left';
    }
    return _reviewIssues.isEmpty
        ? 'Ready to save'
        : '${_reviewIssues.length} item${_reviewIssues.length == 1 ? '' : 's'} to finish';
  }

  /// Count of questions with multiple correct answers (where partial credit matters)
  int get _multiAnswerQuestionCount =>
      _correctAnswers.values.where((answers) => answers.length > 1).length;

  String _normalizeSubjectName(String value) => value.trim().toUpperCase();
  String _normalizeSectionName(String value) => value.trim().toUpperCase();
  String _canonicalizeSectionName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  Set<String> _sanitizeAnswers(Iterable<String> answers) => answers
      .map((answer) => answer.trim().toUpperCase())
      .where(_answerChoiceSet.contains)
      .toSet();

  String _canonicalizeSubjectName(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final words = trimmed.split(' ');
    return words.map((word) {
      if (word.isEmpty) {
        return word;
      }
      if (word.toUpperCase() == word && word.length <= 4) {
        return word;
      }
      final lower = word.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join(' ');
  }

  List<Subject> _findSubjectsByName(
    String subjectName, {
    String? excludeId,
  }) {
    final normalizedName = _normalizeSubjectName(subjectName);
    return globalSubjects.where((subject) {
      if (excludeId != null && subject.id == excludeId) {
        return false;
      }
      return _normalizeSubjectName(subject.name) == normalizedName;
    }).toList();
  }

  Set<String> _normalizedSectionsOf(Subject subject) {
    return (subject.sectionNames ?? const <String>[])
        .map(_normalizeSectionName)
        .toSet();
  }

  Future<bool> _handleSectionConflict(
    String subjectName,
    List<Subject> conflictingSubjects,
    Set<String> conflictingSections,
  ) async {
    final sortedSections = conflictingSections.toList()..sort();
    final shouldOpenExisting = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subject Already Assigned'),
        content: Text(
          '$subjectName already has an answer key assigned to: ${sortedSections.join(', ')}. Open the existing subject instead of creating another one for the same section.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Existing'),
          ),
        ],
      ),
    );

    if (shouldOpenExisting == true && mounted) {
      final duplicate = conflictingSubjects.firstWhere(
        (subject) => _normalizedSectionsOf(subject)
            .intersection(conflictingSections)
            .isNotEmpty,
        orElse: () => conflictingSubjects.first,
      );
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AnswerKeyPage(subjectToEdit: duplicate),
        ),
      );
    }

    return shouldOpenExisting == true;
  }

  @override
  void initState() {
    super.initState();
    if (widget.subjectToEdit != null) {
      _isEditing = true;
      _nameController.text = widget.subjectToEdit!.name;
      for (final entry in widget.subjectToEdit!.answerKey.entries) {
        final sanitized = _sanitizeAnswers(entry.value);
        if (sanitized.isNotEmpty) {
          _correctAnswers[entry.key] = sanitized;
        }
      }
      _questionCount = widget.subjectToEdit!.totalQuestions;
      _selectedSections =
          (widget.subjectToEdit!.sectionNames ?? const <String>[])
              .map(_canonicalizeSectionName)
              .toSet();
      _usePartialCredit = widget.subjectToEdit!.usePartialCredit;
    } else if (widget.templateSubject != null) {
      final template = widget.templateSubject!;
      _nameController.text = template.name;
      for (final entry in template.answerKey.entries) {
        final sanitized = _sanitizeAnswers(entry.value);
        if (sanitized.isNotEmpty) {
          _correctAnswers[entry.key] = sanitized;
        }
      }
      _questionCount = template.totalQuestions;
      _usePartialCredit = template.usePartialCredit;
    }

    if (widget.initialSection != null &&
        widget.initialSection!.trim().isNotEmpty) {
      _selectedSections = {_canonicalizeSectionName(widget.initialSection!)};
    }

    if (widget.subjectToEdit != null && _focusedSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_promptSharedKeyEditMode());
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  void _createNewSectionInline() {
    _sectionController.clear();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Theme(
        data: _buildEditorTheme(context),
        child: AlertDialog(
          title: const Text('Create New Section'),
          content: TextField(
            controller: _sectionController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'e.g. BSIT-1A',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);
                final sectionName =
                    _canonicalizeSectionName(_sectionController.text);
                final alreadyExists = globalSections.any(
                  (section) =>
                      _normalizeSectionName(section.name) ==
                      _normalizeSectionName(sectionName),
                );

                if (sectionName.isEmpty) {
                  return;
                }

                if (!alreadyExists) {
                  await LocalDataStore.instance.upsertSection(
                    Section(name: sectionName),
                  );
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _selectedSections = {..._selectedSections, sectionName};
                  });
                } else {
                  setState(() {
                    _selectedSections = {..._selectedSections, sectionName};
                  });
                }

                navigator.pop();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmMultiSectionSave() async {
    if (_selectedSections.length <= 1) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: _buildEditorTheme(context),
        child: AlertDialog(
          title: const Text('Use Same Key for Multiple Sections?'),
          content: const Text(
            'Applying one answer key to multiple sections can make sharing easier. '
            'Continue if this is intended, or create separate keys per section.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  Future<void> _handleSave() async {
    String subjectName = _canonicalizeSubjectName(_nameController.text);
    final availableSections = _getSectionNames();

    if (availableSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please create a Section before saving a subject"),
          backgroundColor: AppColors.warningAccent,
        ),
      );
      return;
    }

    final validationIssues = _reviewIssues;
    if (validationIssues.isNotEmpty) {
      _showValidationSnack(validationIssues);
      return;
    }

    final duplicateSubjects = _findSubjectsByName(
      subjectName,
      excludeId: widget.subjectToEdit?.id,
    );
    if (!_splitEditMode && duplicateSubjects.isNotEmpty) {
      subjectName = duplicateSubjects.first.name;
    }
    final conflictingSections = duplicateSubjects
        .expand((subject) => _normalizedSectionsOf(subject))
        .toSet()
        .intersection(_selectedSections.map(_normalizeSectionName).toSet());
    if (conflictingSections.isNotEmpty) {
      final openedExisting = await _handleSectionConflict(
        subjectName,
        duplicateSubjects,
        conflictingSections,
      );
      if (openedExisting || !mounted) {
        return;
      }
      return;
    }

    final warningsConfirmed = await _confirmSaveWarnings();
    if (!warningsConfirmed || !mounted) {
      return;
    }

    final ok = await _confirmMultiSectionSave();
    if (!ok) {
      return;
    }
    _nameController.text = subjectName;
    try {
      await _saveSubject(subjectName);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserErrorMessages.friendlySaveError(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showValidationSnack(List<String> issues) {
    final message = issues.length == 1
        ? issues.first
        : issues.take(4).join('\n') + (issues.length > 4 ? '\n...' : '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warningAccent,
      ),
    );
  }

  Future<bool> _confirmSaveWarnings() async {
    final warnings = _reviewWarnings;
    if (warnings.isEmpty) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: _buildEditorTheme(context),
        child: AlertDialog(
          title: const Text('Review Before Saving'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: warnings
                .map(
                  (warning) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: _warningOrange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(warning)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  Map<int, List<String>> _buildNormalizedAnswerKey() {
    final normalized = <int, List<String>>{};
    for (final entry in _correctAnswers.entries) {
      if (entry.key < 1 || entry.key > _questionCount) {
        continue;
      }
      final answers = _sanitizeAnswers(entry.value).toList()..sort();
      if (answers.isNotEmpty) {
        normalized[entry.key] = answers;
      }
    }
    return normalized;
  }

  Future<void> _saveSubject(String subjectName) async {
    final existingSubject = widget.subjectToEdit;
    final passingScore =
        existingSubject?.passingScore ?? (_questionCount * 0.6).round();
    final examDate = existingSubject?.examDate ?? DateTime.now();

    if (_splitEditMode &&
        existingSubject != null &&
        _focusedSection != null) {
      final focus = _focusedSection!;
      final linkedScans =
          _scanCountForSectionOnSubject(existingSubject.id, focus);
      if (linkedScans > 0) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Existing scans'),
            content: Text(
              '$linkedScans scan${linkedScans == 1 ? '' : 's'} for $focus '
              'are still linked to the shared key. '
              'Splitting creates a new key for $focus; old scans stay on the original key.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Split anyway'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) {
          return;
        }
      }

      final remainingSections = (existingSubject.sectionNames ?? const <String>[])
          .map(_canonicalizeSectionName)
          .where((section) => section != focus)
          .toList()
        ..sort();

      final updatedOriginal = existingSubject.copyWith(
        sectionNames: remainingSections,
        sectionQrData: _buildSectionQrData(
          subjectId: existingSubject.id,
          subjectName: existingSubject.name,
          sections: remainingSections,
          passingScore: existingSubject.passingScore,
          examDate: existingSubject.examDate ?? examDate,
          totalQuestions: existingSubject.totalQuestions,
        ),
        updatedAt: DateTime.now(),
      );

      final newSubjectId = generateUniqueSubjectId();
      final newSubject = Subject(
        id: newSubjectId,
        name: subjectName,
        answerKey: _buildNormalizedAnswerKey(),
        totalQuestions: _questionCount,
        sectionNames: [focus],
        sectionQrData: _buildSectionQrData(
          subjectId: newSubjectId,
          subjectName: subjectName,
          sections: [focus],
          passingScore: passingScore,
          examDate: examDate,
        ),
        examDate: examDate,
        passingScore: passingScore,
        usePartialCredit: _usePartialCredit,
      );

      await LocalDataStore.instance.upsertSubject(updatedOriginal);
      await LocalDataStore.instance.upsertSubject(newSubject);

      if (!mounted) {
        return;
      }
      Navigator.pop(context, AnswerKeyEditorResult.updated(newSubject));
      return;
    }

    final targetSubject = existingSubject;
    final subjectId = targetSubject?.id ?? generateUniqueSubjectId();
    final selectedSections = {
      ..._selectedSections.map(_canonicalizeSectionName),
    }.toList()
      ..sort();
    final sectionQrData = _buildSectionQrData(
      subjectId: subjectId,
      subjectName: subjectName,
      sections: selectedSections,
      passingScore: passingScore,
      examDate: examDate,
    );

    final subject = Subject(
      id: subjectId,
      name: subjectName,
      answerKey: _buildNormalizedAnswerKey(),
      totalQuestions: _questionCount,
      sectionNames: selectedSections,
      sectionQrData: sectionQrData,
      examDate: examDate,
      passingScore: passingScore,
      usePartialCredit: _usePartialCredit,
    );

    await LocalDataStore.instance.upsertSubject(subject);

    if (!mounted) {
      return;
    }

    if (_isEditing) {
      Navigator.pop(context, AnswerKeyEditorResult.updated(subject));
    } else {
      if (!mounted) {
        return;
      }
      final colorScheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Answer Key for $subjectName Saved!"),
          backgroundColor: colorScheme.primary,
        ),
      );
      Navigator.pop(context, subject);
    }
  }

  Future<void> _deleteSubject() async {
    final subject = widget.subjectToEdit;
    if (subject == null) {
      return;
    }

    final sectionFocus = widget.editSectionFocus;
    final choice = await showAnswerKeyDeleteDialog(
      context: context,
      subject: subject,
      sectionName: sectionFocus,
    );
    if (choice == AnswerKeyDeleteChoice.cancelled || !mounted) {
      return;
    }

    final SubjectDeletionSummary summary;
    if (choice == AnswerKeyDeleteChoice.sectionOnly) {
      if (sectionFocus == null) {
        return;
      }
      summary = await LocalDataStore.instance.deleteSubjectFromSection(
        subject: subject,
        sectionName: sectionFocus,
      );
    } else {
      summary = await LocalDataStore.instance.deleteSubjectCascade(subject);
    }

    if (!mounted) {
      return;
    }
    Navigator.pop(
      context,
      AnswerKeyEditorResult.deleted(
        subjectName: subject.displayName,
        deletionSummary: summary,
      ),
    );
  }

  // ==================== IMPORT/EXPORT/TEMPLATES ====================

  void _showImportDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Import Answer Key"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Paste your answer key in one of these formats:",
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("â€¢ Compact: ABCDEBACDE...",
                        style: TextStyle(fontSize: 13)),
                    Text("â€¢ CSV: 1,A\\n2,B\\n3,C...",
                        style: TextStyle(fontSize: 13)),
                    Text("â€¢ Multi-answer: 1,A,B\\n2,C",
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: "Paste answer key here...",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          TextButton(
            onPressed: () async {
              // Try to paste from clipboard
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) {
                textController.text = data!.text!;
              }
            },
            child: const Text("PASTE"),
          ),
          FilledButton(
            onPressed: () {
              final result = AnswerKeyIOService.autoImport(textController.text);
              Navigator.pop(context);
              _handleImportResult(result);
            },
            child: const Text("IMPORT"),
          ),
        ],
      ),
    );
  }

  void _handleImportResult(AnswerKeyImportResult result) {
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserErrorMessages.friendlyImportError(result.errorMessage),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check question count compatibility
    final importedCount = result.totalQuestions!;
    final template = OmrTemplateSpec.forItemCount(importedCount);

    if (!_supportedQuestionCounts.contains(importedCount)) {
      // Find closest supported count
      final closest = _supportedQuestionCounts.reduce((a, b) =>
          (a - importedCount).abs() < (b - importedCount).abs() ? a : b);
      final closestTemplate = OmrTemplateSpec.forItemCount(closest);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Adjust Question Count?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Imported key has $importedCount questions."),
              Text("Closest supported count is $closest."),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Sheet layout: ${closestTemplate.columns} columns Ã— ${closestTemplate.rows} rows",
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _applyImportedAnswers(result.answers!, closest);
              },
              child: Text("USE $closest QUESTIONS"),
            ),
          ],
        ),
      );
      return;
    }

    // Show confirmation with layout info
    final currentTemplate = OmrTemplateSpec.forItemCount(_questionCount);
    final layoutChanges = currentTemplate.templateId != template.templateId;

    if (layoutChanges && _isEditing) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Import Answer Key?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  "Importing ${result.answers!.length} answers for $importedCount questions."),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brandSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.brandBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Layout will change:",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.brandGreenDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        "â€¢ Current: ${currentTemplate.columns}Ã—${currentTemplate.rows} ($_questionCount items)"),
                    Text(
                        "â€¢ New: ${template.columns}Ã—${template.rows} ($importedCount items)"),
                    const SizedBox(height: 8),
                    const Text(
                      "You'll need to reprint answer sheets.",
                      style:
                          TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _applyImportedAnswers(result.answers!, importedCount);
              },
              child: const Text("IMPORT"),
            ),
          ],
        ),
      );
    } else {
      _applyImportedAnswers(result.answers!, importedCount);
    }
  }

  void _applyImportedAnswers(
      Map<int, List<String>> answers, int questionCount) {
    final template = OmrTemplateSpec.forItemCount(questionCount);

    setState(() {
      _questionCount = questionCount;
      _correctAnswers.clear();
      answers.forEach((q, answerList) {
        if (q >= 1 && q <= questionCount) {
          _correctAnswers[q] = answerList.toSet();
        }
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Imported ${_correctAnswers.length} answers"),
            Text(
              "Layout: ${template.columns}Ã—${template.rows} grid ($questionCount items)",
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: _brandGreen,
      ),
    );
  }

  void _showExportDialog() {
    // Convert current answers to the format expected by export
    final answerKey = <int, List<String>>{};
    _correctAnswers.forEach((q, answers) {
      if (answers.isNotEmpty) {
        answerKey[q] = answers.toList();
      }
    });

    if (answerKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No answers to export")),
      );
      return;
    }

    final csvExport = AnswerKeyIOService.exportToCsv(answerKey);
    final compactExport =
        AnswerKeyIOService.exportToCompact(answerKey, _questionCount);
    final jsonExport = AnswerKeyIOService.exportToJson(answerKey);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Export Answer Key"),
        content: SizedBox(
          width: double.maxFinite,
          child: DefaultTabController(
            length: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: "Compact"),
                    Tab(text: "CSV"),
                    Tab(text: "JSON"),
                  ],
                ),
                SizedBox(
                  height: 200,
                  child: TabBarView(
                    children: [
                      _buildExportTab(compactExport,
                          "Compact format - one letter per question"),
                      _buildExportTab(
                          csvExport, "CSV format - question,answer per line"),
                      _buildExportTab(
                          jsonExport, "JSON format - structured data"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  Widget _buildExportTab(String content, String description) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Copied to clipboard")),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text("Copy"),
            ),
          ),
        ],
      ),
    );
  }

  void _saveAsTemplate() {
    if (_answeredQuestionsCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Add some answers before saving as template")),
      );
      return;
    }

    final nameController = TextEditingController(
      text: _nameController.text.isNotEmpty
          ? "${_nameController.text} Template"
          : "Answer Key Template",
    );
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save as Template"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Template Name",
                hintText: "e.g., Midterm Exam Key",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: "Description (optional)",
                hintText: "e.g., For Math 101",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              if (nameController.text.trim().isEmpty) {
                return;
              }

              final answerKey = <int, List<String>>{};
              _correctAnswers.forEach((q, answers) {
                if (answers.isNotEmpty) {
                  answerKey[q] = answers.toList();
                }
              });

              final template = AnswerKeyTemplate.create(
                name: nameController.text.trim(),
                description: descController.text.trim().isEmpty
                    ? null
                    : descController.text.trim(),
                answerKey: answerKey,
                totalQuestions: _questionCount,
              );

              await LocalDataStore.instance.upsertAnswerKeyTemplate(template);
              if (!mounted) {
                return;
              }
              navigator.pop();

              messenger.showSnackBar(
                SnackBar(
                  content: Text("Template '${template.name}' saved"),
                  backgroundColor: _brandGreen,
                ),
              );
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  void _showLoadTemplateDialog() {
    if (globalAnswerKeyTemplates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No templates saved yet")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Load Template"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: globalAnswerKeyTemplates.length,
            itemBuilder: (context, index) {
              final template = globalAnswerKeyTemplates[index];
              return ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(template.name),
                subtitle: Text(
                  "${template.totalQuestions} questions${template.description != null ? ' â€¢ ${template.description}' : ''}",
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        await LocalDataStore.instance.deleteAnswerKeyTemplate(
                          template.id,
                        );
                        if (!mounted) {
                          return;
                        }
                        navigator.pop();
                        if (globalAnswerKeyTemplates.isNotEmpty) {
                          _showLoadTemplateDialog();
                        }
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  _loadTemplate(template);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
        ],
      ),
    );
  }

  void _loadTemplate(AnswerKeyTemplate template) {
    final willOverwrite = _answeredQuestionsCount > 0;

    if (willOverwrite) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Replace Current Answers?"),
          content: Text(
            "Loading '${template.name}' will replace your current $_answeredQuestionsCount answers.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _applyTemplate(template);
              },
              child: const Text("REPLACE"),
            ),
          ],
        ),
      );
    } else {
      unawaited(_applyTemplate(template));
    }
  }

  Future<void> _applyTemplate(AnswerKeyTemplate template) async {
    setState(() {
      _questionCount = template.totalQuestions;
      _correctAnswers.clear();
      template.answerKey.forEach((q, answers) {
        _correctAnswers[q] = answers.toSet();
      });
    });

    // Update last used time
    await LocalDataStore.instance.markAnswerKeyTemplateUsed(
      templateId: template.id,
      usedAt: DateTime.now(),
    );
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            "Loaded '${template.name}' (${template.answerKey.length} answers)"),
        backgroundColor: _brandGreen,
      ),
    );
  }

  // ==================== END IMPORT/EXPORT/TEMPLATES ====================

  // ==================== QUESTION COUNT CHANGE ====================

  void _changeQuestionCount(int newCount) {
    final isDecreasing = newCount < _questionCount;
    final answersToLose = isDecreasing
        ? _correctAnswers.keys.where((q) => q > newCount).length
        : 0;

    // Get layout info for both counts
    final oldTemplate = OmrTemplateSpec.forItemCount(_questionCount);
    final newTemplate = OmrTemplateSpec.forItemCount(newCount);
    final layoutChanges = oldTemplate.templateId != newTemplate.templateId;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change Question Count?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (answersToLose > 0) ...[
              Text(
                "âš ï¸ This will remove $answersToLose answer(s) for questions "
                "${newCount + 1}-$_questionCount.",
                style: const TextStyle(color: AppColors.warningAccent),
              ),
              const SizedBox(height: 12),
            ],
            if (layoutChanges) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brandSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.brandBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.grid_view,
                            color: AppColors.brandGreenDark, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "Sheet Layout Change",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.brandGreenDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "â€¢ Current: ${oldTemplate.columns} columns Ã— ${oldTemplate.rows} rows",
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      "â€¢ New: ${newTemplate.columns} columns Ã— ${newTemplate.rows} rows",
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "You'll need to print new answer sheets after changing.",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.brandGreenDark,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isEditing)
              const Text(
                "Existing printed sheets for this subject will NOT work "
                "with the new question count.",
                style: TextStyle(fontSize: 13),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _applyQuestionCountChange(newCount, layoutChanges);
            },
            child: const Text("CHANGE"),
          ),
        ],
      ),
    );
  }

  void _applyQuestionCountChange(int newCount, bool layoutChanged) {
    setState(() {
      // Remove answers for questions beyond the new count
      _correctAnswers.removeWhere((q, _) => q > newCount);
      _questionCount = newCount;
    });

    final template = OmrTemplateSpec.forItemCount(newCount);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Changed to $newCount questions"),
            if (layoutChanged)
              Text(
                "Layout: ${template.columns}Ã—${template.rows} grid",
                style: const TextStyle(fontSize: 12),
              ),
            if (_isEditing)
              const Text(
                "Remember to save and reprint sheets!",
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
        backgroundColor: layoutChanged ? AppColors.brandGreenDark : AppColors.warningAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ==================== END QUESTION COUNT CHANGE ====================

  void _quickFillAnswers() {
    final fromController = TextEditingController(text: '1');
    final toController = TextEditingController(text: '$_questionCount');
    var selectedLetters = <String>{};

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void applyLettersToRange(int from, int to, Set<String> letters) {
            for (var question = from; question <= to; question++) {
              _correctAnswers[question] = Set<String>.from(letters);
            }
          }

          String? rangeError(int from, int to) {
            if (from < 1 || to > _questionCount || from > to) {
              return 'Enter question numbers from 1 to $_questionCount.';
            }
            if (selectedLetters.isEmpty) {
              return 'Pick at least one answer letter.';
            }
            return null;
          }

          return AlertDialog(
            title: const Text('Quick fill'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: fromController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'From',
                            hintText: '1',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: toController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'To',
                            hintText: '$_questionCount',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _usePartialCredit
                        ? 'Answer (tap one or more)'
                        : 'Answer',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _brandText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _answerChoices.map((letter) {
                      final selected = selectedLetters.contains(letter);
                      return FilterChip(
                        label: Text(letter),
                        selected: selected,
                        selectedColor: _brandGreen.withValues(alpha: 0.12),
                        checkmarkColor: _brandGreen,
                        onSelected: (value) {
                          setDialogState(() {
                            if (_usePartialCredit) {
                              if (value) {
                                selectedLetters.add(letter);
                              } else {
                                selectedLetters.remove(letter);
                              }
                            } else {
                              selectedLetters = value ? {letter} : {};
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (selectedLetters.isEmpty) {
                    return;
                  }
                  applyLettersToRange(1, _questionCount, selectedLetters);
                  setState(() {});
                  Navigator.pop(dialogContext);
                },
                child: const Text('Fill all'),
              ),
              FilledButton(
                onPressed: () {
                  final from = int.tryParse(fromController.text.trim());
                  final to = int.tryParse(toController.text.trim());
                  if (from == null || to == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter valid question numbers.'),
                      ),
                    );
                    return;
                  }
                  final error = rangeError(from, to);
                  if (error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                    return;
                  }
                  applyLettersToRange(from, to, selectedLetters);
                  setState(() {});
                  Navigator.pop(dialogContext);
                },
                child: const Text('Apply range'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionNames = _getSectionNames();
    final canSelectSection = sectionNames.isNotEmpty;
    _selectedSections = _selectedSections
        .map(_canonicalizeSectionName)
        .where(sectionNames.contains)
        .toSet();

    return _buildEditorScaffold(
      sectionNames: sectionNames,
      canSelectSection: canSelectSection,
    );
  }

  Widget _buildEditorScaffold({
    required List<String> sectionNames,
    required bool canSelectSection,
  }) {
    return Theme(
      data: _buildEditorTheme(context),
      child: Scaffold(
        backgroundColor: _editorCanvas,
        appBar: AppBar(
          title: Text(_isEditing ? "Edit Answer Key" : "Create Answer Key"),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: "Tools",
              onPressed: _showEditorToolsSheet,
            ),
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: "Delete Answer Key",
                onPressed: _deleteSubject,
              ),
          ],
        ),
        body: Column(
          children: [
            if (_splitEditMode && _focusedSection != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildEditorInfoBanner(
                  icon: Icons.call_split_rounded,
                  message:
                      'Splitting ${_focusedSection!} into its own answer key. '
                      'Other sections keep the current answers.',
                  color: _brandGreen,
                ),
              ),
            if (_sharedEditWarning)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildEditorInfoBanner(
                  icon: Icons.warning_amber_rounded,
                  message:
                      'This key is shared across multiple sections. '
                      'Saving will update every assigned section.',
                  color: _warningOrange,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                (_splitEditMode || _sharedEditWarning) ? 12 : 16,
                16,
                0,
              ),
              child: _buildEditorHeaderCard(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildEditorStepTabs(),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Padding(
                  key: ValueKey(_editorStep),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _buildEditorStepContent(
                    sectionNames: sectionNames,
                    canSelectSection: canSelectSection,
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildStickyEditorBar(),
      ),
    );
  }

  ThemeData _buildEditorTheme(BuildContext context) {
    final base = Theme.of(context);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _brandGreen,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _editorCanvas,
      textTheme: base.textTheme.apply(
        bodyColor: _brandText,
        displayColor: _brandText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: _brandText,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _brandText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _fieldFill,
        labelStyle: const TextStyle(
          color: _brandMuted,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: _brandMuted.withValues(alpha: 0.72),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: _brandMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _brandGreen, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: _brandGreen.withValues(alpha: 0.12),
        disabledColor: const Color(0xFFF1F5F9),
        checkmarkColor: _brandGreen,
        labelStyle: const TextStyle(
          color: _brandText,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: _brandGreen,
          fontWeight: FontWeight.w800,
        ),
        side: const BorderSide(color: _fieldBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brandGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandGreen,
          side: const BorderSide(color: _brandGreen),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildEditorInfoBanner({
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color == _warningOrange ? _brandText : _brandGreenDark,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _brandSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? 'Update answer key' : 'Build a new answer key',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _brandText,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set the subject details, finish the answers, then review everything before saving.',
            style: TextStyle(
              color: _brandMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TopMetricCard(
                  label: 'Answered',
                  value: '$_answeredQuestionsCount/$_questionCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TopMetricCard(
                  label: 'Sections',
                  value: '${_selectedSections.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TopMetricCard(
                  label: 'Left',
                  value: '$_remainingQuestionsCount',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: _completionProgress,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(_brandGreen),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorStepTabs() {
    const labels = <String>['1. Details', '2. Questions', '3. Review'];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brandBorder),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = _editorStep == index;
          return Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(right: index == labels.length - 1 ? 0 : 6),
              child: Material(
                color: selected ? _brandGreen : _brandSurface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() => _editorStep = index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : _brandText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEditorStepContent({
    required List<String> sectionNames,
    required bool canSelectSection,
  }) {
    switch (_editorStep) {
      case 1:
        return _buildQuestionEditorStep();
      case 2:
        return _buildReviewStep();
      case 0:
      default:
        return _buildDetailsStep(
          sectionNames: sectionNames,
          canSelectSection: canSelectSection,
        );
    }
  }

  Widget _buildDetailsStep({
    required List<String> sectionNames,
    required bool canSelectSection,
  }) {
    final duplicateSubjects = !_isEditing &&
            _nameController.text.trim().isNotEmpty
        ? _findSubjectsByName(_nameController.text)
        : const <Subject>[];
    final takenSections = duplicateSubjects
        .expand((subject) => subject.sectionNames ?? const <String>[])
        .map(_normalizeSectionName)
        .toSet();

    return ListView(
      children: [
        _buildStepCard(
          title: 'Subject',
          subtitle: 'Name the answer key clearly so it is easy to find later.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: "Subject Name",
                  hintText: "e.g., Math 101",
                  prefixIcon: Icon(Icons.book_rounded),
                ),
              ),
              if (duplicateSubjects.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'You already have ${duplicateSubjects.length} answer key'
                  '${duplicateSubjects.length == 1 ? '' : 's'} for this subject. '
                  'Create a separate key for another section (e.g. a different class) '
                  'to use different answers.',
                  style: const TextStyle(
                    color: _warningOrange,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildStepCard(
          title: 'Sections',
          subtitle: _splitEditMode
              ? 'This split applies to ${_focusedSection ?? 'the selected section'} only.'
              : duplicateSubjects.isNotEmpty
                  ? 'Pick one section for this version. Sections already assigned are disabled.'
                  : 'Assign the sections that should use this exact answer key.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!canSelectSection)
                const Text(
                  'No sections available yet. Create one first.',
                  style: TextStyle(color: _warningOrange),
                )
              else if (_splitEditMode && _focusedSection != null)
                _buildSectionSelectChip(
                  section: _focusedSection!,
                  isSelected: true,
                  isTaken: false,
                  onTap: null,
                )
              else ...[
                const Text(
                  'Tap a section to select it. Selected sections are highlighted.',
                  style: TextStyle(
                    color: _brandMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sectionNames.map((section) {
                    final isSelected = _selectedSections.contains(section);
                    final isTaken = takenSections
                        .contains(_normalizeSectionName(section));
                    return _buildSectionSelectChip(
                      section: section,
                      isSelected: isSelected,
                      isTaken: isTaken,
                      onTap: isTaken
                          ? null
                          : () {
                              setState(() {
                                if (isSelected) {
                                  _selectedSections.remove(section);
                                } else {
                                  _selectedSections.add(section);
                                }
                              });
                            },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _createNewSectionInline,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create Section'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildStepCard(
          title: 'Sheet size',
          subtitle: 'How many questions are on the answer sheet.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey(_questionCount),
                initialValue: _questionCount,
                decoration: const InputDecoration(
                  labelText: 'Questions on sheet',
                ),
                items: _supportedQuestionCounts
                    .map(
                      (count) => DropdownMenuItem<int>(
                        value: count,
                        child: Text('$count questions'),
                      ),
                    )
                    .toList(),
                onChanged: (count) {
                  if (count != null && count != _questionCount) {
                    _changeQuestionCount(count);
                  }
                },
              ),
              TextButton(
                onPressed: () {
                  setState(() => _showFullLayoutGrid = !_showFullLayoutGrid);
                },
                child: Text(
                  _showFullLayoutGrid ? 'Hide layout grid' : 'Change layout',
                ),
              ),
              if (_showFullLayoutGrid)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _supportedQuestionCounts.map((count) {
                    final selected = _questionCount == count;
                    final template = OmrTemplateSpec.forItemCount(count);
                    return ChoiceChip(
                      label: Text('$count (${template.columns}x${template.rows})'),
                      selected: selected,
                      onSelected: (value) {
                        if (value && count != _questionCount) {
                          _changeQuestionCount(count);
                        }
                      },
                      backgroundColor: Colors.white,
                      selectedColor: _brandGreen.withValues(alpha: 0.12),
                      showCheckmark: true,
                      surfaceTintColor: Colors.transparent,
                      side: BorderSide(
                        color: selected ? _brandGreen : _brandBorder,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? _brandGreen : _brandText,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildStepCard(
          title: 'Advanced',
          subtitle: 'Optional scoring settings.',
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Partial credit',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                _multiAnswerQuestionCount == 0
                    ? 'Enable after adding multi-answer questions'
                    : _usePartialCredit
                        ? 'Proportional points for partial answers'
                        : 'All-or-nothing scoring',
                style: const TextStyle(fontSize: 12, color: _brandMuted),
              ),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use partial credit'),
                  value: _usePartialCredit,
                  activeThumbColor: _brandGreen,
                  onChanged: _multiAnswerQuestionCount > 0
                      ? (value) => setState(() => _usePartialCredit = value)
                      : null,
                ),
              ],
            ),
          ),
        ),
        if (_reviewWarnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildStepCard(
            title: 'Warnings',
            subtitle: 'You can save, but review these first.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _reviewWarnings
                  .map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: _warningOrange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warning,
                              style: const TextStyle(
                                color: _brandText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuestionEditorStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Select the correct answer for each question.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _brandMuted,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _quickFillAnswers,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Quick fill'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brandGreen,
                  side: const BorderSide(color: _brandGreen),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _completionProgress == 1
                    ? 'Ready to review'
                    : '$_remainingQuestionsCount left',
                style: TextStyle(
                  color:
                      _completionProgress == 1 ? _brandGreen : _warningOrange,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = constraints.maxWidth < 360
                  ? 1
                  : (constraints.maxWidth / 190).floor().clamp(2, 4);

              return GridView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 148,
                ),
                itemCount: _questionCount,
                itemBuilder: (context, index) {
                  final qNum = index + 1;
                  final selectedAnswers =
                      _correctAnswers[qNum] ?? const <String>{};
                  return _buildQuestionCard(
                    qNum: qNum,
                    selectedAnswers: selectedAnswers,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return ListView(
      children: [
        _buildStepCard(
          title: 'Review',
          subtitle: 'Check the setup before saving the answer key.',
          child: Column(
            children: [
              _ReviewRow(
                label: 'Subject',
                value: _nameController.text.trim().isEmpty
                    ? 'Not set'
                    : _nameController.text.trim(),
              ),
              _ReviewRow(
                label: 'Sections',
                value: _selectedSections.isEmpty
                    ? 'None selected'
                    : _selectedSections.join(', '),
              ),
              _ReviewRow(
                label: 'Question count',
                value: '$_questionCount items',
              ),
              _ReviewRow(
                label: 'Answered',
                value: '$_answeredQuestionsCount of $_questionCount',
              ),
              _ReviewRow(
                label: 'Partial credit',
                value: _usePartialCredit ? 'Enabled' : 'Disabled',
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildStepCard(
          title: 'Status',
          subtitle: _reviewIssues.isEmpty
              ? 'Everything looks ready to save.'
              : 'Finish these items before saving.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _reviewIssues.isEmpty
                ? const [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: _brandGreen),
                        SizedBox(width: 8),
                        Text(
                          'Ready to save',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _brandText,
                          ),
                        ),
                      ],
                    ),
                  ]
                : _reviewIssues
                    .map(
                      (issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: _warningOrange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                issue,
                                style: const TextStyle(
                                  color: _brandText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard({
    required int qNum,
    required Set<String> selectedAnswers,
  }) {
    final isAnswered = selectedAnswers.isNotEmpty;
    final isMultiAnswer = selectedAnswers.length > 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isAnswered ? _brandGreen.withValues(alpha: 0.35) : _brandBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isAnswered ? _brandGreen : _brandSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$qNum',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isAnswered ? Colors.white : _brandText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMultiAnswer
                      ? '${selectedAnswers.length} selected'
                      : isAnswered
                          ? 'Answered'
                          : 'Choose answer',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _brandMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _answerChoices.map((label) {
              final isSelected = selectedAnswers.contains(label);
              return _AnswerOptionButton(
                label: label,
                selected: isSelected,
                onTap: () => _toggleQuestionAnswer(qNum, label),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _toggleQuestionAnswer(int qNum, String label) {
    setState(() {
      final answers = _correctAnswers[qNum] ?? <String>{};
      if (answers.contains(label)) {
        answers.remove(label);
        if (answers.isEmpty) {
          _correctAnswers.remove(qNum);
        } else {
          _correctAnswers[qNum] = answers;
        }
      } else {
        answers.add(label);
        _correctAnswers[qNum] = answers;
      }
    });
  }

  Widget _buildSectionSelectChip({
    required String section,
    required bool isSelected,
    required bool isTaken,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isTaken
                ? _brandMuted.withValues(alpha: 0.08)
                : isSelected
                    ? _brandGreen.withValues(alpha: 0.22)
                    : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isTaken
                  ? _brandBorder
                  : isSelected
                      ? _brandGreen
                      : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            section,
            style: TextStyle(
              color: isTaken
                  ? _brandMuted
                  : isSelected
                      ? _brandGreenDark
                      : _brandMuted,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _brandText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: _brandMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildStickyEditorBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _brandBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _primaryEditorHelpText,
                    style: TextStyle(
                      color: _canUsePrimaryEditorAction
                          ? _brandGreen
                          : _editorStep == 0
                              ? _brandMuted
                              : _warningOrange,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$_answeredQuestionsCount/$_questionCount answered',
                  style: const TextStyle(
                    color: _brandMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_editorStep > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _editorStep -= 1);
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Previous'),
                    ),
                  ),
                if (_editorStep > 0) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: !_canUsePrimaryEditorAction
                        ? null
                        : _editorStep == 2
                            ? _handleSave
                            : () {
                                setState(() => _editorStep += 1);
                              },
                    icon: Icon(
                      _editorStep == 2
                          ? Icons.save_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(_editorStep == 2 ? 'Save Key' : 'Continue'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandGreen,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEditorToolsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => Theme(
        data: _buildEditorTheme(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToolActionRow(
                  icon: Icons.file_download_outlined,
                  label: 'Import from text',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showImportDialog();
                  },
                ),
                _ToolActionRow(
                  icon: Icons.file_upload_outlined,
                  label: 'Export answers',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showExportDialog();
                  },
                ),
                _ToolActionRow(
                  icon: Icons.bookmark_add_outlined,
                  label: 'Save as template',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _saveAsTemplate();
                  },
                ),
                _ToolActionRow(
                  icon: Icons.bookmark_outlined,
                  label: 'Load template',
                  enabled: globalAnswerKeyTemplates.isNotEmpty,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showLoadTemplateDialog();
                  },
                ),
                _ToolActionRow(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Quick fill',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _quickFillAnswers();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopMetricCard extends StatelessWidget {
  const _TopMetricCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _AnswerKeyPageState._brandText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: _AnswerKeyPageState._brandMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(
                  color: _AnswerKeyPageState._brandBorder,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                color: _AnswerKeyPageState._brandMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _AnswerKeyPageState._brandText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerOptionButton extends StatelessWidget {
  const _AnswerOptionButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _AnswerKeyPageState._brandGreen : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 40,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? _AnswerKeyPageState._brandGreen
                  : _AnswerKeyPageState._brandBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _AnswerKeyPageState._brandText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolActionRow extends StatelessWidget {
  const _ToolActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? _AnswerKeyPageState._brandText
        : _AnswerKeyPageState._brandMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
