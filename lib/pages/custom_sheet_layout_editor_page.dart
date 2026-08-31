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

  final _nameController = TextEditingController();
  final _questionController = TextEditingController(text: '15');
  int _optionsCount = OmrPageConstants.answerOptionsCount;
  String? _selectedLayoutId;
  bool _advancedGrid = false;
  int _gridColumns = 2;
  int _gridRows = 3;
  String? _errorMessage;
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
      _advancedGrid = existing.inputMode == CustomSheetLayoutInputMode.byGrid;
      _gridColumns = existing.gridColumns;
      _gridRows = existing.gridRows;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshValidation());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _questionController.dispose();
    super.dispose();
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
    if (_advancedGrid) {
      if (_gridColumns * _gridRows != _questionCount) {
        return OmrLayoutFitResult.fail(
          'Manual grid must be $_gridColumns×$_gridRows = '
          '${_gridColumns * _gridRows} questions, but you entered '
          '$_questionCount. Adjust the grid or question count.',
        );
      }
      final form = _selectedSuggestion?.form ??
          const OmrLayoutForm(
            orientation: OmrLayoutOrientation.lengthwise,
            pageFill: OmrLayoutPageFill.full,
          );
      return OmrLayoutProfile.tryComputeExplicitGrid(
        columns: _gridColumns,
        rows: _gridRows,
        optionsCount: _optionsCount,
        form: form,
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
      if (!_questionCountValid) {
        _errorMessage =
            'Enter ${OmrLayoutProfile.minCustomItems}–'
            '${OmrLayoutProfile.maxCustomItems} questions.';
      } else if (_suggestions.isEmpty) {
        _errorMessage =
            'No scannable layout fits $_questionCount questions with '
            '${_allAnswerChoices.take(_optionsCount).join('-')} choices. '
            'Try fewer questions, fewer choices, or a standard 30–100 sheet.';
      } else {
        _errorMessage = fit.isOk ? null : fit.errorMessage;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Add a layout name.');
      return;
    }
    final fit = _currentFit;
    if (!fit.isOk) {
      setState(() => _errorMessage = fit.errorMessage);
      return;
    }

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
        inputMode: _advancedGrid
            ? CustomSheetLayoutInputMode.byGrid
            : CustomSheetLayoutInputMode.byQuestions,
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
    final fit = _currentFit;
    if (!fit.isOk || fit.profile == null) {
      setState(() => _errorMessage = fit.errorMessage);
      return;
    }
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
        printContext: context,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
            setState(() {
              _selectedLayoutId = suggestion.id;
              _advancedGrid = false;
            });
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
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Layout name',
              hintText: 'e.g. Weekly quiz, Exit ticket 10',
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
          TextField(
            controller: _questionController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Questions on sheet',
              helperText:
                  '${OmrLayoutProfile.minCustomItems}–'
                  '${OmrLayoutProfile.maxCustomItems} questions',
            ),
            onChanged: (_) => _refreshValidation(),
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
          const SizedBox(height: 10),
          if (suggestions.isEmpty && _questionCountValid) ...[
            Text(
              _errorMessage ?? 'No layout fits these settings.',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
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
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Advanced · manual grid',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: const Text(
              'For experienced users. Still blocked if bubbles are too tight.',
              style: TextStyle(fontSize: 12),
            ),
            initiallyExpanded: _advancedGrid,
            onExpansionChanged: (expanded) {
              setState(() => _advancedGrid = expanded);
              _refreshValidation();
            },
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _gridColumns,
                      decoration: const InputDecoration(labelText: 'Columns'),
                      items: List.generate(
                        10,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${i + 1}'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _gridColumns = value);
                        _refreshValidation();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _gridRows,
                      decoration: const InputDecoration(labelText: 'Rows'),
                      items: List.generate(
                        20,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${i + 1}'),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _gridRows = value);
                        _refreshValidation();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$_gridColumns × $_gridRows = ${_gridColumns * _gridRows} '
                'questions',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandMuted,
                ),
              ),
              if (_advancedGrid &&
                  _gridColumns * _gridRows != _questionCount) ...[
                const SizedBox(height: 8),
                Text(
                  'Manual grid must match $_questionCount questions '
                  '(${_gridColumns * _gridRows} now).',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
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
          if (_errorMessage != null && suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
