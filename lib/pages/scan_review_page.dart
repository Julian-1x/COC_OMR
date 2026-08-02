import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_shadows.dart';
import 'package:omr_app/theme/app_typography.dart';
import 'package:omr_app/widgets/animated_percent_text.dart';

/// A page that shows scan results with the ability to review and correct answers.
/// This allows teachers to fix any misreads before saving.
class ScanReviewPage extends StatefulWidget {
  final Student student;
  final Subject subject;
  final Map<int, String> detectedAnswers;
  final double confidence;
  final String? sheetId;
  final List<String> reviewReasons;
  final List<int> flaggedQuestions;
  /// Native scan debug lines for validation (corner method, alignment %, etc.).
  final List<String> scanDiagnostics;
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;
  final bool requireExitConfirmation;

  const ScanReviewPage({
    super.key,
    required this.student,
    required this.subject,
    required this.detectedAnswers,
    required this.confidence,
    this.sheetId,
    this.reviewReasons = const <String>[],
    this.flaggedQuestions = const <int>[],
    this.scanDiagnostics = const <String>[],
    this.onSave,
    this.onDiscard,
    this.requireExitConfirmation = false,
  });

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

enum _AnswerFilter { all, needsReview, blank, wrong }

class _ScanReviewPageState extends State<ScanReviewPage> {
  late Map<int, String> _editedAnswers;
  late Map<int, double> _correctnessMap;
  late double _score;
  bool _hasChanges = false;
  bool _alertsExpanded = false;
  _AnswerFilter _filter = _AnswerFilter.all;
  final Set<int> _flaggedQuestions = <int>{};

  Map<int, String> get _baselineAnswers =>
      _normalizeStoredAnswers(widget.detectedAnswers);

  @override
  void initState() {
    super.initState();
    _editedAnswers = _baselineAnswers;
    _recalculateScore();
    _flaggedQuestions.addAll(widget.flaggedQuestions);

    if (widget.confidence < 0.85) {
      for (int question = 1;
          question <= widget.subject.totalQuestions;
          question++) {
        if (!_editedAnswers.containsKey(question)) continue;
        final credit = _correctnessMap[question];
        if (credit != null && credit < 1.0) {
          _flaggedQuestions.add(question);
        }
      }
    }
  }

  Map<int, String> _normalizeStoredAnswers(Map<int, String> answers) {
    final normalized = <int, String>{};
    answers.forEach((question, answer) {
      final serialized = _normalizeStoredAnswer(answer);
      if (serialized != null) {
        normalized[question] = serialized;
      }
    });
    return normalized;
  }

  String? _normalizeStoredAnswer(String? answer) {
    final serialized = serializeStoredAnswerSelections(
      parseStoredAnswerSelections(answer),
    );
    return serialized.isEmpty ? null : serialized;
  }

  String _displayAnswerLabel(String? answer) {
    final selections = parseStoredAnswerSelections(answer);
    if (selections.isEmpty) {
      return '-';
    }
    return selections.join('+');
  }

  void _recalculateScore() {
    _score = widget.subject.calculateSmartScore(_editedAnswers);
    _correctnessMap = <int, double>{};

    for (int question = 1;
        question <= widget.subject.totalQuestions;
        question++) {
      final answer = _editedAnswers[question];
      if (answer == null || answer.isEmpty) {
        continue;
      }
      _correctnessMap[question] =
          widget.subject.calculateQuestionScore(question, answer);
    }
  }

  void _updateAnswer(int questionNumber, String? newAnswer) {
    setState(() {
      final normalizedAnswer = _normalizeStoredAnswer(newAnswer);
      if (normalizedAnswer == null) {
        _editedAnswers.remove(questionNumber);
      } else {
        _editedAnswers[questionNumber] = normalizedAnswer;
      }

      _hasChanges = !mapEquals(_editedAnswers, _baselineAnswers);
      _recalculateScore();
    });
  }

  void _saveAndExit() {
    Navigator.pop(
      context,
      ScanReviewResult(
        editedAnswers: _editedAnswers,
        wasEdited: _hasChanges,
      ),
    );
    widget.onSave?.call();
  }

  void _discardAndExit() {
    Navigator.pop(context, null);
    widget.onDiscard?.call();
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges && !widget.requireExitConfirmation) {
      return true;
    }

    final forcedReview = widget.requireExitConfirmation && !_hasChanges;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(forcedReview ? 'Save this scan?' : 'Discard Changes?'),
        content: Text(
          forcedReview
              ? 'This scan needs review. Save it or discard it?'
              : 'You have unsaved corrections. Discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(forcedReview ? 'KEEP REVIEWING' : 'KEEP EDITING'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('DISCARD'),
          ),
          if (forcedReview || _hasChanges)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('SAVE'),
            ),
        ],
      ),
    );

    if (result == 'save') {
      _saveAndExit();
      return false;
    }
    if (result == 'discard') {
      _discardAndExit();
      return false;
    }
    return false;
  }

  int get _correctCount =>
      _correctnessMap.values.where((value) => value >= 1.0).length;

  int get _partialCount => _correctnessMap.values
      .where((value) => value > 0 && value < 1.0)
      .length;

  int get _wrongCount => _editedAnswers.keys
      .where((question) => (_correctnessMap[question] ?? 0.0) == 0.0)
      .length;

  int get _blankCount =>
      widget.subject.totalQuestions - _editedAnswers.length;

  List<int> get _visibleQuestions {
    final all = List<int>.generate(widget.subject.totalQuestions, (i) => i + 1);
    switch (_filter) {
      case _AnswerFilter.all:
        return all;
      case _AnswerFilter.needsReview:
        return all
            .where((q) => _flaggedQuestions.contains(q) || _isWrong(q))
            .toList();
      case _AnswerFilter.blank:
        return all.where((q) => !_editedAnswers.containsKey(q)).toList();
      case _AnswerFilter.wrong:
        return all.where(_isWrong).toList();
    }
  }

  bool _isWrong(int question) {
    if (!_editedAnswers.containsKey(question)) return false;
    return (_correctnessMap[question] ?? 0.0) == 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final percentage = (_score / widget.subject.totalQuestions) * 100;
    final passed = percentage >= 60;
    final needsAttention =
        widget.confidence < 0.9 || widget.reviewReasons.isNotEmpty;

    return PopScope(
      canPop: !_hasChanges && !widget.requireExitConfirmation,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.appCanvas,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: const Text('Review Scan'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (_hasChanges) {
                final shouldPop = await _onWillPop();
                if (shouldPop && context.mounted) {
                  _discardAndExit();
                }
              } else {
                _discardAndExit();
              }
            },
          ),
          actions: [
            if (_hasChanges)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _editedAnswers = Map<int, String>.from(_baselineAnswers);
                    _hasChanges = false;
                    _recalculateScore();
                  });
                },
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('RESET'),
              ),
          ],
        ),
        body: Column(
          children: [
            _buildHeader(percentage, passed),
            if (needsAttention) _buildAttentionCard(),
            if (widget.scanDiagnostics.isNotEmpty) _buildDiagnosticsPanel(),
            _buildFilterRow(),
            Expanded(child: _buildAnswerGrid()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double percentage, bool passed) {
    final scoreColor =
        passed ? AppColors.statusSuccess : AppColors.statusWarning;
    final scoreBg =
        passed ? AppColors.statusSuccessBg : AppColors.statusWarningBg;
    final scoreBorder =
        passed ? AppColors.statusSuccessBorder : AppColors.statusWarningBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.student.name,
                  style: AppTypography.sectionTitle.copyWith(fontSize: 17),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _metaChip(
                      Icons.groups_outlined,
                      widget.student.section,
                    ),
                    _metaChip(
                      Icons.badge_outlined,
                      'OMR ${widget.student.omrId}',
                    ),
                    _metaChip(
                      Icons.menu_book_outlined,
                      widget.subject.displayName,
                      tint: AppColors.brandGreenDark,
                      fill: AppColors.brandSurface,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            constraints: const BoxConstraints(minWidth: 78),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scoreBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scoreBorder),
            ),
            child: Column(
              children: [
                Text(
                  '${formatScoreValue(_score)}/${widget.subject.totalQuestions}',
                  style: AppTypography.statValue.copyWith(
                    fontSize: 20,
                    color: scoreColor,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedPercentText(
                  value: percentage.round(),
                  style: AppTypography.captionMuted.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(
    IconData icon,
    String label, {
    Color? tint,
    Color? fill,
  }) {
    final color = tint ?? AppColors.brandMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill ?? AppColors.neutralFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.captionMuted.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionCard() {
    final confidencePercent = (widget.confidence * 100).toStringAsFixed(0);
    final preview = widget.reviewReasons.isEmpty
        ? 'Confidence $confidencePercent% — check flagged answers before saving.'
        : widget.reviewReasons.first;
    final extraCount = widget.reviewReasons.length > 1
        ? widget.reviewReasons.length - 1
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.reviewReasons.length > 1
              ? () => setState(() => _alertsExpanded = !_alertsExpanded)
              : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.statusWarningBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.priority_high_rounded,
                      color: AppColors.statusWarning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Needs a quick look',
                            style: AppTypography.chipLabel.copyWith(
                              color: AppColors.warningText,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            preview,
                            style: AppTypography.captionMuted.copyWith(
                              color: AppColors.warningText,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          if (!_alertsExpanded && extraCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+$extraCount more · tap to expand',
                                style: AppTypography.captionMuted.copyWith(
                                  color: AppColors.warningAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
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
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$confidencePercent%',
                        style: AppTypography.captionMuted.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.warningText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_alertsExpanded && widget.reviewReasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...widget.reviewReasons.skip(1).map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(left: 26, bottom: 4),
                          child: Text(
                            '• $reason',
                            style: AppTypography.captionMuted.copyWith(
                              color: AppColors.warningText,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.borderLight),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.borderLight),
            ),
            leading: const Icon(
              Icons.analytics_outlined,
              color: AppColors.brandGreenDark,
              size: 20,
            ),
            title: Text(
              'Scan technical details',
              style: AppTypography.captionMuted.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.brandGreenDark,
              ),
            ),
            subtitle: Text(
              '${widget.scanDiagnostics.length} measurement(s)',
              style: AppTypography.captionMuted.copyWith(fontSize: 11),
            ),
            children: widget.scanDiagnostics
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            color: AppColors.brandMuted,
                            height: 1.35,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: AppTypography.captionMuted.copyWith(
                              fontSize: 12,
                              height: 1.35,
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
      ),
    );
  }

  Widget _buildFilterRow() {
    final reviewCount = List<int>.generate(widget.subject.totalQuestions, (i) => i + 1)
        .where((q) => _flaggedQuestions.contains(q) || _isWrong(q))
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(
              label: 'All ${widget.subject.totalQuestions}',
              selected: _filter == _AnswerFilter.all,
              onTap: () => setState(() => _filter = _AnswerFilter.all),
            ),
            const SizedBox(width: 6),
            _filterChip(
              label: 'Review $reviewCount',
              selected: _filter == _AnswerFilter.needsReview,
              onTap: () => setState(() => _filter = _AnswerFilter.needsReview),
              accent: AppColors.statusWarning,
            ),
            const SizedBox(width: 6),
            _filterChip(
              label: 'Wrong $_wrongCount',
              selected: _filter == _AnswerFilter.wrong,
              onTap: () => setState(() => _filter = _AnswerFilter.wrong),
              accent: AppColors.statusDanger,
            ),
            const SizedBox(width: 6),
            _filterChip(
              label: 'Blank $_blankCount',
              selected: _filter == _AnswerFilter.blank,
              onTap: () => setState(() => _filter = _AnswerFilter.blank),
              accent: AppColors.neutralMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? accent,
  }) {
    final color = accent ?? AppColors.brandGreenDark;
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.45) : AppColors.borderLight,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.captionMuted.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? color : AppColors.brandMuted,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerGrid() {
    final questions = _visibleQuestions;

    if (questions.isEmpty) {
      return Center(
        child: Text(
          'Nothing in this filter',
          style: AppTypography.captionMuted.copyWith(fontSize: 13),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = (constraints.maxWidth / 78).floor().clamp(4, 6);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 72,
          ),
          itemCount: questions.length,
          itemBuilder: (context, index) =>
              _buildQuestionCell(questions[index]),
        );
      },
    );
  }

  Widget _buildQuestionCell(int questionNumber) {
    final answer = _editedAnswers[questionNumber];
    final hasAnswer = answer != null && answer.isNotEmpty;
    final awardedCredit = _correctnessMap[questionNumber] ?? 0.0;
    final isFullyCorrect = awardedCredit >= 1.0;
    final isPartiallyCorrect = awardedCredit > 0 && awardedCredit < 1.0;
    final originalAnswer = _baselineAnswers[questionNumber];
    final wasEdited = answer != originalAnswer;
    final isFlagged = _flaggedQuestions.contains(questionNumber);
    final displayAnswer = _displayAnswerLabel(answer);

    Color backgroundColor;
    Color borderColor;
    Color answerColor;

    if (!hasAnswer) {
      backgroundColor = Colors.white;
      borderColor = AppColors.borderSubtle;
      answerColor = AppColors.neutralMuted;
    } else if (isFullyCorrect) {
      backgroundColor = AppColors.statusSuccessBg;
      borderColor =
          wasEdited ? AppColors.brandGreen : AppColors.statusSuccessBorder;
      answerColor = AppColors.statusSuccess;
    } else if (isPartiallyCorrect) {
      backgroundColor = AppColors.statusWarningBg;
      borderColor =
          wasEdited ? AppColors.brandGreen : AppColors.statusWarningBorder;
      answerColor = AppColors.warningText;
    } else {
      backgroundColor = AppColors.statusDangerBg;
      borderColor =
          wasEdited ? AppColors.brandGreen : AppColors.statusDangerBorder;
      answerColor = AppColors.statusDanger;
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _showAnswerPicker(questionNumber),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFlagged ? AppColors.statusWarning : borderColor,
              width: wasEdited || isFlagged ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Q$questionNumber',
                    style: AppTypography.captionMuted.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  if (isFlagged)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(
                        Icons.flag_rounded,
                        size: 10,
                        color: AppColors.statusWarning,
                      ),
                    ),
                  if (wasEdited)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(
                        Icons.edit,
                        size: 10,
                        color: AppColors.brandGreen,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                displayAnswer,
                style: TextStyle(
                  fontSize: displayAnswer.length > 2 ? 15 : 19,
                  fontWeight: FontWeight.w800,
                  color: answerColor,
                  height: 1.1,
                ),
              ),
              if (hasAnswer) ...[
                const SizedBox(height: 2),
                isPartiallyCorrect
                    ? Text(
                        '${awardedCredit.toStringAsFixed(1)} pt',
                        style: AppTypography.captionMuted.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.statusWarning,
                          fontSize: 10,
                        ),
                      )
                    : Icon(
                        isFullyCorrect
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        size: 13,
                        color: isFullyCorrect
                            ? AppColors.statusSuccess
                            : AppColors.statusDanger,
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAnswerPicker(int questionNumber) {
    final currentAnswer = _editedAnswers[questionNumber];
    final currentSelections =
        parseStoredAnswerSelections(currentAnswer).toSet();
    final correctAnswers = widget.subject.answerKey[questionNumber] ?? [];
    final allowsMultipleSelection = widget.subject.usePartialCredit ||
        widget.subject.allowsMultipleAnswers(questionNumber) ||
        currentSelections.length > 1;

    HapticFeedback.selectionClick();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Question $questionNumber',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandText,
                    ),
                  ),
                  const Spacer(),
                  if (correctAnswers.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.statusSuccessBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Key: ${correctAnswers.join(", ")}',
                        style: AppTypography.captionMuted.copyWith(
                          color: AppColors.statusSuccess,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                allowsMultipleSelection
                    ? 'Select answer(s):'
                    : 'Select answer:',
                style: const TextStyle(color: AppColors.brandMuted),
              ),
              if (allowsMultipleSelection) ...[
                const SizedBox(height: 4),
                const Text(
                  'Tap all shaded choices, then apply.',
                  style: AppTypography.captionMuted,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final letter in ['A', 'B', 'C', 'D', 'E'])
                    _buildAnswerButton(
                      letter,
                      isSelected: currentSelections.contains(letter),
                      isCorrect: correctAnswers.contains(letter),
                      onTap: () {
                        if (!allowsMultipleSelection) {
                          _updateAnswer(questionNumber, letter);
                          Navigator.pop(context);
                          return;
                        }

                        setSheetState(() {
                          if (currentSelections.contains(letter)) {
                            currentSelections.remove(letter);
                          } else {
                            currentSelections.add(letter);
                          }
                        });
                      },
                    ),
                ],
              ),
              if (allowsMultipleSelection) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      _updateAnswer(
                        questionNumber,
                        serializeStoredAnswerSelections(currentSelections),
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Apply Selection'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    _updateAnswer(questionNumber, null);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear Answer (Blank)'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerButton(
    String letter, {
    required bool isSelected,
    required bool isCorrect,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? (isCorrect
                  ? AppColors.statusSuccessBg
                  : AppColors.brandSurface)
              : (isCorrect
                  ? AppColors.statusSuccessBg
                  : AppColors.neutralFill),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? (isCorrect ? AppColors.statusSuccess : AppColors.brandGreen)
                : (isCorrect
                    ? AppColors.statusSuccessBorder
                    : AppColors.borderSubtle),
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Center(
          child: Text(
            letter,
            style: TextStyle(
              fontSize: 22,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isCorrect
                  ? AppColors.statusSuccess
                  : AppColors.brandMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
        boxShadow: AppShadows.soft,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatPill(
                    Icons.check_circle_rounded,
                    '$_correctCount',
                    'Correct',
                    AppColors.statusSuccess,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildStatPill(
                    Icons.adjust_rounded,
                    '$_partialCount',
                    'Partial',
                    AppColors.statusWarning,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildStatPill(
                    Icons.cancel_rounded,
                    '$_wrongCount',
                    'Wrong',
                    AppColors.statusDanger,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildStatPill(
                    Icons.remove_circle_outline_rounded,
                    '$_blankCount',
                    'Blank',
                    AppColors.neutralMuted,
                  ),
                ),
              ],
            ),
            if (_hasChanges) ...[
              const SizedBox(height: 8),
              Text(
                'You edited answers — save to keep corrections',
                style: AppTypography.captionMuted.copyWith(
                  color: AppColors.brandGreenDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _discardAndExit,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Discard'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saveAndExit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      _hasChanges ? 'Save Corrections' : 'Confirm Save',
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

  Widget _buildStatPill(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.captionMuted.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Result returned from ScanReviewPage
class ScanReviewResult {
  final Map<int, String> editedAnswers;
  final bool wasEdited;

  ScanReviewResult({
    required this.editedAnswers,
    required this.wasEdited,
  });
}
