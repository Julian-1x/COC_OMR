import 'package:flutter/material.dart';
import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/omr_sheet_layout_preview.dart';

class CustomSheetLayoutEditorPage extends StatefulWidget {
  const CustomSheetLayoutEditorPage({super.key, this.existing});

  final CustomSheetLayout? existing;

  @override
  State<CustomSheetLayoutEditorPage> createState() =>
      _CustomSheetLayoutEditorPageState();
}

class _CustomSheetLayoutEditorPageState
    extends State<CustomSheetLayoutEditorPage> {
  static const _allAnswerChoices = ['A', 'B', 'C', 'D', 'E'];

  final _scrollController = ScrollController();
  final _nameFieldKey = GlobalKey();
  final _questionFieldKey = GlobalKey();
  final _layoutSectionKey = GlobalKey();
  final _nameFocusNode = FocusNode();
  final _questionFocusNode = FocusNode();
  final _nameController = TextEditingController();
  final _questionController = TextEditingController(text: '15');
  int _optionsCount = OmrPageConstants.answerOptionsCount;
  String? _selectedLayoutId;
  String? _nameError;
  String? _questionError;
  String? _layoutError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _questionController.text = '${existing.totalQuestions}';
      _optionsCount = existing.optionsCount;
      _selectedLayoutId = existing.layoutForm.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshValidation());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameFocusNode.dispose();
    _questionFocusNode.dispose();
    _nameController.dispose();
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _scrollToField(GlobalKey key, {FocusNode? focus}) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) {
      return;
    }
    final target = key.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.08,
      );
    }
    if (focus != null && mounted) {
      focus.requestFocus();
    }
  }

  int get _questionCount =>
      int.tryParse(_questionController.text.trim()) ??
      OmrLayoutProfile.minCustomItems;

  bool get _questionCountValid =>
      _questionCount >= OmrLayoutProfile.minCustomItems &&
      _questionCount <= OmrLayoutProfile.maxCustomItems;

  List<OmrLayoutSuggestion> get _suggestions {
    if (!_questionCountValid) {
      return const [];
    }
    return OmrLayoutProfile.suggestLayouts(
      itemCount: _questionCount,
      optionsCount: _optionsCount,
    );
  }

  List<OmrLayoutBlockedOption> get _blockedLayouts {
    if (!_questionCountValid) {
      return const [];
    }
    return OmrLayoutProfile.blockedLayouts(
      itemCount: _questionCount,
      optionsCount: _optionsCount,
    );
  }

  OmrLayoutSuggestion? get _selectedSuggestion {
    final id = _selectedLayoutId;
    if (id == null) {
      return null;
    }
    for (final suggestion in _suggestions) {
      if (suggestion.id == id) {
        return suggestion;
      }
    }
    return null;
  }

  OmrLayoutFitResult get _currentFit {
    if (!_questionCountValid) {
      return OmrLayoutFitResult.fail(
        'Enter ${OmrLayoutProfile.minCustomItems}–'
        '${OmrLayoutProfile.maxCustomItems} questions.',
      );
    }
    final suggestion = _selectedSuggestion;
    if (suggestion == null) {
      return const OmrLayoutFitResult.fail('Pick a sheet layout to continue.');
    }
    return OmrLayoutFitResult.ok(suggestion.profile);
  }

  void _syncSelectedLayout() {
    final suggestions = _suggestions;
    if (suggestions.isEmpty) {
      _selectedLayoutId = null;
      return;
    }
    if (_selectedLayoutId != null &&
        suggestions.any((s) => s.id == _selectedLayoutId)) {
      return;
    }
    _selectedLayoutId = suggestions.first.id;
  }

  void _refreshValidation() {
    _syncSelectedLayout();
    final fit = _currentFit;
    setState(() {
      _layoutError = null;
      if (!_questionCountValid) {
        _questionError =
            'Enter ${OmrLayoutProfile.minCustomItems}–'
            '${OmrLayoutProfile.maxCustomItems} questions.';
      } else {
        _questionError = null;
      }
      if (_suggestions.isEmpty && _questionCountValid) {
        _layoutError =
            'No scannable layout fits $_questionCount questions with '
            '${_allAnswerChoices.take(_optionsCount).join('-')} choices. '
            'Try fewer questions, fewer choices, or a standard 30–100 sheet.';
      } else if (!fit.isOk) {
        _layoutError = fit.errorMessage;
      }
    });
  }

  Future<bool> _validateForSubmit() async {
    if (!mounted) {
      return false;
    }
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    String? nameError;
    String? questionError;
    String? layoutError;

    if (name.isEmpty) {
      nameError = 'Add a layout name.';
    }
    if (!_questionCountValid) {
      questionError =
          'Enter ${OmrLayoutProfile.minCustomItems}–'
          '${OmrLayoutProfile.maxCustomItems} questions.';
    } else if (_suggestions.isEmpty) {
      layoutError =
          'No scannable layout fits these settings. Try fewer questions or choices.';
    } else {
      final fit = _currentFit;
      if (!fit.isOk) {
        layoutError = fit.errorMessage ?? 'Pick a sheet layout to continue.';
      } else if (_selectedSuggestion == null) {
        layoutError = 'Pick a sheet layout to continue.';
      }
    }

    setState(() {
      _nameError = nameError;
      _questionError = questionError;
      _layoutError = layoutError;
    });

    if (nameError != null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Add a layout name at the top.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      await _scrollToField(_nameFieldKey, focus: _nameFocusNode);
      return false;
    }
    if (questionError != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(questionError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      await _scrollToField(_questionFieldKey, focus: _questionFocusNode);
      return false;
    }
    if (layoutError != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(layoutError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      await _scrollToField(_layoutSectionKey);
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!await _validateForSubmit()) {
      return;
    }
    final fit = _currentFit;
    final name = _nameController.text.trim();

    setState(() => _saving = true);
    try {
      final layout = CustomSheetLayout(
        id: widget.existing?.id ??
            'csl_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        totalQuestions: _questionCount,
        optionsCount: _optionsCount,
        layoutShape: fit.profile!.form.id,
        gridColumns: fit.profile!.grid.columns,
        gridRows: fit.profile!.grid.rows,
        inputMode: CustomSheetLayoutInputMode.byQuestions,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        lastUsedAt: widget.existing?.lastUsedAt,
      );
      await LocalDataStore.instance.upsertCustomSheetLayout(layout);
      if (!mounted) {
        return;
      }
      Navigator.pop(context, layout);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _printSample() async {
    if (!await _validateForSubmit()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final printContext = context;
    final fit = _currentFit;
    final subject = Subject(
      name: 'Sample Exam',
      answerKey: const <int, dynamic>{},
      totalQuestions: _questionCount,
      useCustomLayout: true,
      optionsCount: _optionsCount,
      layoutShape: fit.profile!.form.id,
      customGridColumns: fit.profile!.grid.columns,
      customGridRows: fit.profile!.grid.rows,
    );
    try {
      await AnswerSheetGenerator.generateMultiple(
        subject: subject,
        sectionName: 'SAMPLE',
        copies: 1,
        printContext: printContext,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(printContext).showSnackBar(
          const SnackBar(
            content: Text('Could not generate sample sheet.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _standardSheetBanner() {
    if (_questionCount < 30) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningAccent.withValues(alpha: 0.45)),
      ),
      child: const Text(
        'For 30–100 questions, standard sheets (Answer Key → 30–100) are '
        'tested and recommended. Custom layouts work best for short quizzes.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.brandMuted,
        ),
      ),
    );
  }

  Widget _layoutCard(OmrLayoutSuggestion suggestion) {
    final selected = _selectedLayoutId == suggestion.id;
    final tier = suggestion.tier;
    final borderColor = selected
        ? AppColors.brandGreen
        : tier == OmrLayoutSuggestionTier.tight
            ? AppColors.warningAccent.withValues(alpha: 0.55)
            : AppColors.brandBorder;
    final badgeColor = switch (tier) {
      OmrLayoutSuggestionTier.recommended => AppColors.brandGreen,
      OmrLayoutSuggestionTier.workable => AppColors.brandMuted,
      OmrLayoutSuggestionTier.tight => AppColors.warningAccent,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.brandGreen.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() => _selectedLayoutId = suggestion.id);
            _refreshValidation();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        suggestion.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: selected
                              ? AppColors.brandGreen
                              : AppColors.brandText,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tier.pickerLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.brandMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockedSection() {
    final blocked = _blockedLayouts;
    if (blocked.isEmpty) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text(
        'Why are some layouts unavailable?',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppColors.brandMuted,
        ),
      ),
      children: blocked
          .map(
            (option) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                option.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandMuted,
                ),
              ),
              subtitle: Text(
                option.reason,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fit = _currentFit;
    final profile = fit.profile;
    final suggestions = _suggestions;
    final grouped = <OmrLayoutSuggestionTier, List<OmrLayoutSuggestion>>{};
    for (final suggestion in suggestions) {
      grouped.putIfAbsent(suggestion.tier, () => []).add(suggestion);
    }

    return Scaffold(
      backgroundColor: AppColors.appCanvas,
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New layout' : 'Edit layout'),
        actions: [
          TextButton(
            onPressed: _saving || profile == null ? null : _printSample,
            child: const Text('Print sample'),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          KeyedSubtree(
            key: _nameFieldKey,
            child: TextField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Layout name',
                hintText: 'e.g. Weekly quiz, Exit ticket 10',
                errorText: _nameError,
                errorMaxLines: 2,
              ),
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Step 1 · How many questions?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start here — the app will only show layouts that scan reliably.',
            style: TextStyle(fontSize: 12, color: AppColors.brandMuted),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: _questionFieldKey,
            child: TextField(
              controller: _questionController,
              focusNode: _questionFocusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Questions on sheet',
                helperText:
                    '${OmrLayoutProfile.minCustomItems}–'
                    '${OmrLayoutProfile.maxCustomItems} questions',
                errorText: _questionError,
                errorMaxLines: 3,
              ),
              onChanged: (_) => _refreshValidation(),
            ),
          ),
          _standardSheetBanner(),
          const SizedBox(height: 16),
          const Text(
            'Step 2 · Answer choices (A–E only)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [2, 3, 4, 5].map((count) {
              final selected = _optionsCount == count;
              final labels = _allAnswerChoices.take(count).join('-');
              return ChoiceChip(
                label: Text(labels),
                selected: selected,
                onSelected: (value) {
                  if (!value) return;
                  setState(() => _optionsCount = count);
                  _refreshValidation();
                },
                selectedColor: AppColors.brandGreen.withValues(alpha: 0.12),
                side: BorderSide(
                  color:
                      selected ? AppColors.brandGreen : AppColors.brandBorder,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _layoutSectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Step 3 · Pick a sheet layout',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Only scannable options are shown. Pick one — the grid is chosen '
                  'for you.',
                  style: TextStyle(fontSize: 12, color: AppColors.brandMuted),
                ),
                if (_layoutError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _layoutError!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (suggestions.isEmpty && _questionCountValid)
                  const SizedBox.shrink()
                else ...[
                  for (final tier in OmrLayoutSuggestionTier.values)
                    if (grouped[tier]?.isNotEmpty ?? false) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, top: 4),
                        child: Text(
                          tier.pickerLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.brandMuted,
                          ),
                        ),
                      ),
                      ...grouped[tier]!.map(_layoutCard),
                    ],
                  _blockedSection(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (profile != null) ...[
            OmrSheetLayoutPreview(profile: profile),
            const SizedBox(height: 8),
            Text(
              profile.previewLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}


