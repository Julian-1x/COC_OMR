import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omr_app/models/custom_sheet_layout.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/auto_sync_service.dart';
import 'package:omr_app/services/onboarding_preferences_service.dart';
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
  static const _allAnswerChoices = ['A', 'B', 'C', 'D', 'E', 'F'];

  final _scrollController = ScrollController();
  final _nameFieldKey = GlobalKey();
  final _questionFieldKey = GlobalKey();
  final _layoutSectionKey = GlobalKey();
  final _nameFocusNode = FocusNode();
  final _questionFocusNode = FocusNode();
  final _nameController = TextEditingController();
  final _questionController = TextEditingController();

  int _optionsCount = OmrPageConstants.answerOptionsCount;
  /// Default: app packs columns × rows (EvalBee-style Continuous).
  /// Customize: instructor picks grid width × height.
  bool _useAutomaticLayout = true;
  int? _manualColumns;
  int? _manualRows;
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
      _optionsCount = existing.optionsCount.clamp(2, 6);
      _selectedLayoutId = existing.layoutForm.id;
      if (existing.inputMode == CustomSheetLayoutInputMode.byGrid) {
        _useAutomaticLayout = false;
        _manualColumns = existing.gridColumns;
        _manualRows = existing.gridRows;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshValidation();
      if (widget.existing == null) {
        unawaited(_maybeShowGuide());
      }
    });
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

  Future<void> _maybeShowGuide({bool force = false}) async {
    if (!force) {
      final seen = await OnboardingPreferencesService.hasSeenCustomSheetGuide();
      if (seen) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.brandBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Custom sheet guide',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Build a portrait answer sheet the phone can scan upright. '
                  'Automatic layout is the default — customize the grid only if you need to.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.brandMuted,
                  ),
                ),
                const SizedBox(height: 16),
                _guideStep(
                  '1',
                  'Questions',
                  '${OmrLayoutProfile.minCustomItems}–${OmrLayoutProfile.maxCustomItems} '
                  'questions. They run top → bottom in each column (same as scanning).',
                ),
                _guideStep(
                  '2',
                  'Choices',
                  'Pick A–B up to A–F. Bubbles on printed sheets stay blank for '
                  'students — you fill the answer key separately.',
                ),
                _guideStep(
                  '3',
                  'Layout',
                  'Automatic picks a safe columns × rows grid. Switch to Customize '
                  'only to choose from the available grids that fit your question '
                  'count, then pick a scan-safe print size.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tip: Prefer a standard 30–100 sheet when that count fits your exam.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.brandMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await OnboardingPreferencesService.setCustomSheetGuideSeen();
  }

  static Widget _guideStep(String number, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.brandGreen,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.brandMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  int? get _parsedQuestionCount {
    final raw = _questionController.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return int.tryParse(raw);
  }

  /// Valid question count only; 0 when the field is blank or invalid.
  int get _questionCount => _parsedQuestionCount ?? 0;

  bool get _questionCountValid {
    final count = _parsedQuestionCount;
    return count != null &&
        count >= OmrLayoutProfile.minCustomItems &&
        count <= OmrLayoutProfile.maxCustomItems;
  }

  bool get _questionFieldHasInput =>
      _questionController.text.trim().isNotEmpty;

  String? _questionLimitGuide({required bool forSubmit}) {
    final raw = _questionController.text.trim();
    if (raw.isEmpty) {
      return forSubmit
          ? 'Enter ${OmrLayoutProfile.minCustomItems}–'
              '${OmrLayoutProfile.maxCustomItems} questions.'
          : null;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      return 'Enter a whole number from ${OmrLayoutProfile.minCustomItems}–'
          '${OmrLayoutProfile.maxCustomItems}.';
    }
    if (parsed < OmrLayoutProfile.minCustomItems ||
        parsed > OmrLayoutProfile.maxCustomItems) {
      return 'Use ${OmrLayoutProfile.minCustomItems}–'
          '${OmrLayoutProfile.maxCustomItems} questions.';
    }
    return null;
  }

  String? _choicesCapacityGuide() {
    if (!_questionCountValid) {
      return null;
    }
    final maxFit = OmrLayoutProfile.maxFitItems(
      form: const OmrLayoutForm(
        orientation: OmrLayoutOrientation.lengthwise,
        pageFill: OmrLayoutPageFill.full,
      ),
      optionsCount: _optionsCount,
    );
    if (_questionCount <= maxFit) {
      return null;
    }
    final labels = _allAnswerChoices.take(_optionsCount).join('-');
    return '$labels fits at most $maxFit questions on one full page. '
        'You entered $_questionCount — use fewer questions or fewer choices.';
  }

  bool get _hasManualGrid =>
      !_useAutomaticLayout &&
      _manualColumns != null &&
      _manualRows != null &&
      _manualColumns! >= 1 &&
      _manualRows! >= 1;

  List<OmrAvailableGridSize> get _availableGridSizes {
    if (!_questionCountValid) {
      return const [];
    }
    return OmrLayoutProfile.availableGridSizes(
      itemCount: _questionCount,
      optionsCount: _optionsCount,
    );
  }

  bool get _manualGridStillAvailable {
    if (!_hasManualGrid) {
      return false;
    }
    return _availableGridSizes.any(
      (grid) =>
          grid.columns == _manualColumns && grid.rows == _manualRows,
    );
  }

  List<OmrLayoutSuggestion> get _suggestions {
    if (_useAutomaticLayout) {
      if (!_questionCountValid) {
        return const [];
      }
      return OmrLayoutProfile.suggestLayouts(
        itemCount: _questionCount,
        optionsCount: _optionsCount,
      );
    }
    if (!_hasManualGrid) {
      return const [];
    }
    return OmrLayoutProfile.suggestExplicitGridLayouts(
      columns: _manualColumns!,
      rows: _manualRows!,
      optionsCount: _optionsCount,
    );
  }

  List<OmrLayoutBlockedOption> get _blockedLayouts {
    if (_useAutomaticLayout) {
      if (!_questionCountValid) {
        return const [];
      }
      return OmrLayoutProfile.blockedLayouts(
        itemCount: _questionCount,
        optionsCount: _optionsCount,
      );
    }
    if (!_hasManualGrid) {
      return const [];
    }
    return OmrLayoutProfile.blockedExplicitGridLayouts(
      columns: _manualColumns!,
      rows: _manualRows!,
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
    if (!_useAutomaticLayout && !_hasManualGrid) {
      return const OmrLayoutFitResult.fail(
        'Select a grid size to continue, or switch back to Automatic layout.',
      );
    }
    if (!_questionCountValid) {
      return OmrLayoutFitResult.fail(
        'Enter ${OmrLayoutProfile.minCustomItems}–'
        '${OmrLayoutProfile.maxCustomItems} questions.',
      );
    }
    if (_hasManualGrid &&
        _questionCount != _manualColumns! * _manualRows!) {
      return OmrLayoutFitResult.fail(
        'Questions must match the grid '
        '($_manualColumns×$_manualRows = '
        '${_manualColumns! * _manualRows!}). '
        'Change the grid size or switch to Automatic.',
      );
    }
    final suggestion = _selectedSuggestion;
    if (suggestion == null) {
      return const OmrLayoutFitResult.fail('No safe print layout fits yet.');
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

  bool get _matchesStandardSheet =>
      _questionCountValid &&
      _optionsCount == OmrPageConstants.answerOptionsCount &&
      _questionCount >= 30 &&
      _questionCount <= 100 &&
      _questionCount % 10 == 0;

  String get _questionSummary {
    final choices = _allAnswerChoices.take(_optionsCount).join('-');
    if (!_questionCountValid) {
      return 'Choices: $choices';
    }
    return '$_questionCount questions · $choices';
  }

  String? get _splitHint {
    if (!_useAutomaticLayout && !_hasManualGrid) {
      return 'Automatic is off — pick an available grid size for these questions.';
    }
    final profile = _currentFit.profile;
    if (profile == null || !_questionCountValid) {
      return null;
    }
    final mode = _useAutomaticLayout ? 'Automatic' : 'Custom grid';
    return '$mode · ${profile.grid.columns} columns × ${profile.grid.rows} rows';
  }

  void _setLayoutMode({required bool automatic}) {
    setState(() {
      _useAutomaticLayout = automatic;
      if (automatic) {
        _manualColumns = null;
        _manualRows = null;
      }
      _layoutError = null;
    });
    _refreshValidation();
  }

  Future<void> _openGridSizeDialog() async {
    if (!_questionCountValid) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter ${OmrLayoutProfile.minCustomItems}–'
            '${OmrLayoutProfile.maxCustomItems} questions first.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _scrollToField(_questionFieldKey, focus: _questionFocusNode);
      return;
    }

    final available = _availableGridSizes;
    if (available.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No custom grid fits this question count safely. '
            'Use Automatic, or change the number of questions.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    var selectedColumns = _manualColumns;
    var selectedRows = _manualRows;
    if (selectedColumns == null ||
        selectedRows == null ||
        !available.any(
          (grid) =>
              grid.columns == selectedColumns && grid.rows == selectedRows,
        )) {
      selectedColumns = available.first.columns;
      selectedRows = available.first.rows;
    }

    final result = await showDialog<({int width, int height})>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Select grid size'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available scan-safe grids for $_questionCount questions '
                      '(A–${_allAnswerChoices[_optionsCount - 1]}). '
                      'Width = columns, height = rows.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.brandMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: available.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final grid = available[index];
                          final selected = grid.columns == selectedColumns &&
                              grid.rows == selectedRows;
                          return Material(
                            color: selected
                                ? AppColors.brandGreen.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setLocal(() {
                                  selectedColumns = grid.columns;
                                  selectedRows = grid.rows;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.brandGreen
                                        : AppColors.brandBorder,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            grid.label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: selected
                                                  ? AppColors.brandGreen
                                                  : AppColors.brandText,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            grid.detail,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              height: 1.3,
                                              color: AppColors.brandMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.brandGreen,
                                        size: 22,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedColumns == null || selectedRows == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            (
                              width: selectedColumns!,
                              height: selectedRows!,
                            ),
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _useAutomaticLayout = false;
      _manualColumns = result.width;
      _manualRows = result.height;
      _layoutError = null;
    });
    _refreshValidation();
  }

  void _refreshValidation() {
    setState(() {
      if (!_useAutomaticLayout &&
          _manualColumns != null &&
          _manualRows != null &&
          (!_questionCountValid || !_manualGridStillAvailable)) {
        _manualColumns = null;
        _manualRows = null;
      }
      _syncSelectedLayout();
      final fit = _currentFit;
      _layoutError = null;
      // Limits stay hidden until the teacher enters a value or saves.
      _questionError = _questionLimitGuide(forSubmit: false);

      final choicesGuide = _choicesCapacityGuide();
      if (!_useAutomaticLayout && !_hasManualGrid) {
        if (!_questionCountValid) {
          _layoutError = _questionFieldHasInput
              ? 'Fix the question count, then pick a grid size.'
              : null;
        } else if (_availableGridSizes.isEmpty) {
          _layoutError = choicesGuide ??
              'No custom grid fits this question count safely. '
                  'Use Automatic, or change the number of questions.';
        } else {
          _layoutError =
              'Pick an available grid size, or switch back to Automatic layout.';
        }
      } else if (_suggestions.isEmpty &&
          (_useAutomaticLayout ? _questionCountValid : _hasManualGrid)) {
        _layoutError = choicesGuide ??
            (_useAutomaticLayout
                ? 'This many questions and choices do not fit on one bond paper '
                    'without hurting scan accuracy. Try fewer questions or fewer choices.'
                : 'This grid and choice count do not fit on one bond paper safely. '
                    'Try another available grid or fewer choices.');
      } else if (!fit.isOk && _questionCountValid) {
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
      questionError = _questionLimitGuide(forSubmit: true);
    } else if (!_useAutomaticLayout && !_hasManualGrid) {
      layoutError = 'Select a grid size, or switch back to Automatic layout.';
    } else if (_suggestions.isEmpty) {
      layoutError = _choicesCapacityGuide() ??
          'No scan-safe custom layout fits these settings on one bond paper.';
    } else {
      final fit = _currentFit;
      if (!fit.isOk) {
        layoutError = fit.errorMessage ?? 'Pick a print layout to continue.';
      } else if (_selectedSuggestion == null) {
        layoutError = 'Pick a print layout to continue.';
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
        id: widget.existing?.id ?? 'csl_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        totalQuestions: _questionCount,
        optionsCount: _optionsCount,
        layoutShape: fit.profile!.form.id,
        gridColumns: fit.profile!.grid.columns,
        gridRows: fit.profile!.grid.rows,
        inputMode: _useAutomaticLayout
            ? CustomSheetLayoutInputMode.byQuestions
            : CustomSheetLayoutInputMode.byGrid,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        lastUsedAt: widget.existing?.lastUsedAt,
      );
      await LocalDataStore.instance.upsertCustomSheetLayout(layout);
      // Push any linked answer keys (with the new grid) to the desk immediately.
      AutoSyncService.instance.scheduleSync(
        immediate: true,
        allowCellular: true,
      );
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
    final layoutName = _nameController.text.trim();
    final subject = Subject(
      name: layoutName.isNotEmpty ? layoutName : 'Custom sheet',
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
    } catch (error) {
      if (mounted) {
        final detail = error.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(printContext).showSnackBar(
          SnackBar(
            content: Text(
              detail.isNotEmpty
                  ? detail
                  : 'Could not generate sample sheet.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _standardSheetBanner() {
    if (!_matchesStandardSheet) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.warningAccent.withValues(alpha: 0.45),
        ),
      ),
      child: const Text(
        'This count matches a standard 30–100 sheet. Prefer Standard unless you '
        'need a different print layout.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.brandMuted,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final splitHint = _splitHint;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _questionSummary,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brandText,
              height: 1.35,
            ),
          ),
          if (splitHint != null) ...[
            const SizedBox(height: 8),
            Text(
              splitHint,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.brandMuted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _layoutTitle(OmrLayoutSuggestion suggestion) {
    final tiling =
        OmrSheetTiling.forGeometry(suggestion.profile.geometry)?.sheetsPerPage ?? 1;
    switch (tiling) {
      case 4:
        return '4 sheets per bond page';
      case 2:
        return '2 sheets per bond page';
      default:
        return '1 sheet per bond page';
    }
  }

  String _layoutSubtitle(OmrLayoutSuggestion suggestion) {
    final profile = suggestion.profile;
    final rowsPerColumn = profile.grid.rows;
    final questionColumns = profile.grid.columns;
    final fill = suggestion.form.pageFill.teacherLabel;
    return 'Portrait · $fill · $questionColumns question columns × '
        '$rowsPerColumn rows · ${profile.optionsCount} choices';
  }

  Widget _layoutCard(OmrLayoutSuggestion suggestion) {
    final selected = _selectedLayoutId == suggestion.id;
    final borderColor = selected
        ? AppColors.brandGreen
        : AppColors.brandBorder;

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
                        _layoutTitle(suggestion),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: selected
                              ? AppColors.brandGreen
                              : AppColors.brandText,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.brandGreen,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _layoutSubtitle(suggestion),
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
        'Why some sizes stay locked',
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
    final remainingSuggestions = suggestions
        .where((suggestion) => suggestion.id != _selectedLayoutId)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.appCanvas,
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New layout' : 'Edit layout'),
        actions: [
          IconButton(
            tooltip: 'How custom sheets work',
            onPressed: () => unawaited(_maybeShowGuide(force: true)),
            icon: const Icon(Icons.help_outline_rounded),
          ),
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
                hintText: 'e.g. Weekly quiz',
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
            '1 · Questions',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: _questionFieldKey,
            child: TextField(
              controller: _questionController,
              focusNode: _questionFocusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Questions',
                errorText: _questionError,
                errorMaxLines: 3,
              ),
              onChanged: (_) => _refreshValidation(),
            ),
          ),
          _standardSheetBanner(),
          const SizedBox(height: 16),
          const Text(
            '2 · Choices',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [2, 3, 4, 5, 6].map((count) {
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
                  color: selected ? AppColors.brandGreen : AppColors.brandBorder,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _summaryCard(),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _layoutSectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '3 · Layout',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Automatic'),
                      icon: Icon(Icons.auto_awesome_rounded, size: 18),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Customize'),
                      icon: Icon(Icons.grid_view_rounded, size: 18),
                    ),
                  ],
                  selected: {_useAutomaticLayout},
                  onSelectionChanged: (selected) {
                    _setLayoutMode(automatic: selected.first);
                  },
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.brandGreen;
                      }
                      return AppColors.brandMuted;
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _useAutomaticLayout
                      ? 'We pick a scan-safe columns × rows grid from your '
                          'question count.'
                      : 'Pick from grids that fit your question count exactly. '
                          'Only scan-safe sizes are listed.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.brandMuted,
                  ),
                ),
                if (!_useAutomaticLayout) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _questionCountValid ? _openGridSizeDialog : null,
                      icon: const Icon(Icons.grid_on_rounded, size: 18),
                      label: Text(
                        !_questionCountValid
                            ? 'Enter questions first'
                            : _hasManualGrid
                                ? 'Grid $_manualColumns×$_manualRows · Change'
                                : _availableGridSizes.isEmpty
                                    ? 'No grid available'
                                    : 'Select grid size',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandGreen,
                        side: const BorderSide(color: AppColors.brandGreen),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Print size',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                if (suggestions.isNotEmpty) ...[
                  _layoutCard(suggestions.firstWhere(
                    (entry) => entry.id == _selectedLayoutId,
                    orElse: () => suggestions.first,
                  )),
                  if (remainingSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Other options',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.brandMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...remainingSuggestions.map(_layoutCard),
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

