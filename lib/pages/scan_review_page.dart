import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_shadows.dart';
import 'package:omr_app/theme/app_spacing.dart';
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
    this.onSave,
    this.onDiscard,
    this.requireExitConfirmation = false,
  });

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  late Map<int, String> _editedAnswers;
  late Map<int, double> _correctnessMap;
  late double _score;
  bool _hasChanges = false;
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
        final credit = _correctnessMap[question];
        if (!_editedAnswers.containsKey(question) ||
            (credit != null && credit < 1.0)) {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percentage = (_score / widget.subject.totalQuestions) * 100;
    final passed = percentage >= 60;

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
        appBar: AppBar(
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
                    _editedAnswers = _baselineAnswers;
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
            _buildHeader(colorScheme, percentage, passed),
            if (widget.confidence < 0.9 || widget.reviewReasons.isNotEmpty)
              _buildReviewWarning(),
            Expanded(child: _buildAnswerGrid()),
            _buildBottomBar(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, double percentage, bool passed) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(color: AppColors.borderLight),
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.student.name, style: AppTypography.sectionTitle),
                const SizedBox(height: 4),
                Text(
                  'Section: ${widget.student.section} · OMR ${widget.student.omrId}',
                  style: AppTypography.captionMuted,
                ),
                Text(
                  widget.subject.displayName,
                  style: AppTypography.chipLabel.copyWith(
                    color: AppColors.brandGreenDark,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: passed
                  ? AppColors.statusSuccessBg
                  : AppColors.statusWarningBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: passed
                    ? AppColors.statusSuccessBorder
                    : AppColors.statusWarningBorder,
              ),
            ),
            child: Column(
              children: [
                Text(
                  '${formatScoreValue(_score)}/${widget.subject.totalQuestions}',
                  style: AppTypography.statValue.copyWith(
                    fontSize: 22,
                    color: passed
                        ? AppColors.statusSuccess
                        : AppColors.statusWarning,
                  ),
                ),
                AnimatedPercentText(
                  value: percentage.round(),
                  style: AppTypography.captionMuted.copyWith(
                    fontWeight: FontWeight.w700,
                    color: passed
                        ? AppColors.brandGreen
                        : AppColors.statusWarning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewWarning() {
    final confidencePercent = (widget.confidence * 100).toStringAsFixed(0);
    final warningText = widget.reviewReasons.isEmpty
        ? 'Scan confidence: $confidencePercent% — please review highlighted answers'
        : [
            'Scan confidence: $confidencePercent%',
            ...widget.reviewReasons,
          ].join('\n');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        border: const Border(
          bottom: BorderSide(color: AppColors.statusWarningBorder),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.statusWarning,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warningText,
              style: AppTypography.captionMuted.copyWith(
                color: AppColors.warningText,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerGrid() {
    final totalQuestions = widget.subject.totalQuestions;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = (constraints.maxWidth / 82).floor().clamp(3, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 76,
          ),
          itemCount: totalQuestions,
          itemBuilder: (context, index) => _buildQuestionCell(index + 1),
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
      backgroundColor = AppColors.neutralFill;
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

    return GestureDetector(
      onTap: () => _showAnswerPicker(questionNumber),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: borderColor,
            width: wasEdited ? 2 : 1,
          ),
          boxShadow: isFlagged ? AppShadows.glow(AppColors.cautionAccent, alpha: 0.15) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Q$questionNumber',
                  style: AppTypography.captionMuted.copyWith(
                    fontWeight: FontWeight.w600,
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
            const SizedBox(height: 4),
            Text(
              displayAnswer,
              style: TextStyle(
                fontSize: displayAnswer.length > 2 ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: answerColor,
              ),
            ),
            if (hasAnswer)
              isPartiallyCorrect
                  ? Text(
                      '${awardedCredit.toStringAsFixed(1)} pt',
                      style: AppTypography.captionMuted.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.statusWarning,
                      ),
                    )
                  : Icon(
                      isFullyCorrect ? Icons.check_rounded : Icons.close_rounded,
                      size: 14,
                      color: isFullyCorrect
                          ? AppColors.statusSuccess
                          : AppColors.statusDanger,
                    ),
          ],
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

  Widget _buildBottomBar(ColorScheme colorScheme) {
    final correct =
        _correctnessMap.values.where((value) => value >= 1.0).length;
    final partial = _correctnessMap.values
        .where((value) => value > 0 && value < 1.0)
        .length;
    final wrong = _editedAnswers.keys
        .where((question) => (_correctnessMap[question] ?? 0.0) == 0.0)
        .length;
    final blank = widget.subject.totalQuestions - _editedAnswers.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: AppShadows.soft,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatChip(Icons.check_circle_rounded, '$correct',
                    'Correct', AppColors.statusSuccess),
                _buildStatChip(Icons.adjust_rounded, '$partial', 'Partial',
                    AppColors.statusWarning),
                _buildStatChip(
                    Icons.cancel_rounded, '$wrong', 'Wrong', AppColors.statusDanger),
                _buildStatChip(Icons.remove_circle_outline_rounded, '$blank',
                    'Blank', AppColors.neutralMuted),
                if (_hasChanges)
                  _buildStatChip(
                      Icons.edit, '', 'Edited', AppColors.brandGreen),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _discardAndExit,
                    child: const Text('Discard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saveAndExit,
                    icon: const Icon(Icons.save),
                    label:
                        Text(_hasChanges ? 'Save Corrections' : 'Confirm Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            if (value.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ],
        ),
        Text(
          label,
          style: AppTypography.captionMuted,
        ),
      ],
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
