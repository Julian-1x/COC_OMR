import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/export_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/app_card.dart';
import 'package:omr_app/widgets/loading_indicators.dart';

/// A question's analysis data
class QuestionAnalysis {
  final int questionNumber;
  final String correctAnswer;
  final int totalAttempts;
  final int correctCount;
  final Map<String, int> answerDistribution; // A: 5, B: 12, C: 3, etc.

  QuestionAnalysis({
    required this.questionNumber,
    required this.correctAnswer,
    required this.totalAttempts,
    required this.correctCount,
    required this.answerDistribution,
  });

  double get difficulty => totalAttempts > 0 ? correctCount / totalAttempts : 0;

  /// Difficulty category based on percentage correct
  String get difficultyLabel {
    if (difficulty >= 0.8) return 'Easy';
    if (difficulty >= 0.5) return 'Medium';
    if (difficulty >= 0.3) return 'Hard';
    return 'Very Hard';
  }

  Color get difficultyColor {
    if (difficulty >= 0.8) return Colors.green;
    if (difficulty >= 0.5) return Colors.orange;
    if (difficulty >= 0.3) return Colors.deepOrange;
    return Colors.red;
  }

  /// Discrimination index - simplified version
  /// Higher values mean the question better separates high/low performers
  double? discriminationIndex;
}

class ItemAnalysisPage extends StatefulWidget {
  final Subject subject;
  final String? sectionFilter;

  const ItemAnalysisPage({
    super.key,
    required this.subject,
    this.sectionFilter,
  });

  @override
  State<ItemAnalysisPage> createState() => _ItemAnalysisPageState();
}

class _ItemAnalysisPageState extends State<ItemAnalysisPage> {
  List<QuestionAnalysis> _questionAnalyses = <QuestionAnalysis>[];
  bool _isLoading = true;
  int _sortMode =
      0; // 0: by question#, 1: by difficulty (hard first), 2: by difficulty (easy first)
  bool _showDistribution = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAnalysis());
  }

  @override
  void didUpdateWidget(covariant ItemAnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject.id != widget.subject.id ||
        oldWidget.sectionFilter != widget.sectionFilter) {
      unawaited(_loadAnalysis());
    }
  }

  Future<void> _loadAnalysis() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final relevantResults = await LocalDataStore.instance.fetchScanResults(
        subjectId: widget.subject.id,
        sectionName: widget.sectionFilter,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _computeAnalysis(relevantResults);
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Item analysis load failed: $error');
      if (mounted) {
        setState(() {
          _questionAnalyses = <QuestionAnalysis>[];
          _isLoading = false;
        });
      }
    }
  }

  void _computeAnalysis(List<ScanResult> relevantResults) {
    final answerKey = widget.subject.answerKey;
    final totalQuestions = widget.subject.totalQuestions;

    // Initialize analyses for each question
    _questionAnalyses = List.generate(totalQuestions, (index) {
      final qNum = index + 1;
      final correctAns =
          answerKey[qNum]?.isNotEmpty == true ? answerKey[qNum]!.first : '?';

      return QuestionAnalysis(
        questionNumber: qNum,
        correctAnswer: correctAns,
        totalAttempts: 0,
        correctCount: 0,
        answerDistribution: {},
      );
    });

    // Tally results
    for (final result in relevantResults) {
      final studentAnswers = result.detectedAnswers;

      for (int qNum = 1; qNum <= totalQuestions; qNum++) {
        final analysis = _questionAnalyses[qNum - 1];
        final studentAnswer = studentAnswers[qNum] ?? '';
        final correctAns = answerKey[qNum];

        // Only count if student answered
        if (studentAnswer.isNotEmpty) {
          // Update distribution
          final currentDist =
              Map<String, int>.from(analysis.answerDistribution);
          currentDist[studentAnswer] = (currentDist[studentAnswer] ?? 0) + 1;

          // Check if correct
          final isCorrect = correctAns?.contains(studentAnswer) == true;

          _questionAnalyses[qNum - 1] = QuestionAnalysis(
            questionNumber: qNum,
            correctAnswer: analysis.correctAnswer,
            totalAttempts: analysis.totalAttempts + 1,
            correctCount: analysis.correctCount + (isCorrect ? 1 : 0),
            answerDistribution: currentDist,
          );
        }
      }
    }

    // Compute discrimination index
    _computeDiscrimination(relevantResults);

    _sortAnalyses();
  }

  void _computeDiscrimination(List<ScanResult> results) {
    if (results.length < 4) return;

    // Sort by percentage
    results.sort((a, b) => b.percentage.compareTo(a.percentage));

    // Top 27% and bottom 27%
    final groupSize =
        (results.length * 0.27).ceil().clamp(1, results.length ~/ 2);
    final topGroup = results.take(groupSize).toList();
    final bottomGroup =
        results.skip(results.length - groupSize).take(groupSize).toList();

    for (int qNum = 1; qNum <= widget.subject.totalQuestions; qNum++) {
      final correctAns = widget.subject.answerKey[qNum];

      int topCorrect = 0;
      int bottomCorrect = 0;

      for (final result in topGroup) {
        final ans = result.detectedAnswers[qNum] ?? '';
        if (correctAns?.contains(ans) == true) topCorrect++;
      }
      for (final result in bottomGroup) {
        final ans = result.detectedAnswers[qNum] ?? '';
        if (correctAns?.contains(ans) == true) bottomCorrect++;
      }

      final discrimination = (topCorrect - bottomCorrect) / groupSize;
      _questionAnalyses[qNum - 1].discriminationIndex = discrimination;
    }
  }

  void _sortAnalyses() {
    switch (_sortMode) {
      case 0:
        _questionAnalyses
            .sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
        break;
      case 1: // Hard first
        _questionAnalyses.sort((a, b) => a.difficulty.compareTo(b.difficulty));
        break;
      case 2: // Easy first
        _questionAnalyses.sort((a, b) => b.difficulty.compareTo(a.difficulty));
        break;
    }
  }

  int get _totalAttempts {
    if (_questionAnalyses.isEmpty) return 0;
    return _questionAnalyses.first.totalAttempts;
  }

  double get _overallDifficulty {
    if (_questionAnalyses.isEmpty) return 0;
    final avg =
        _questionAnalyses.fold<double>(0, (sum, q) => sum + q.difficulty) /
            _questionAnalyses.length;
    return avg;
  }

  List<QuestionAnalysis> get _hardestQuestions => List.from(_questionAnalyses)
    ..sort((a, b) => a.difficulty.compareTo(b.difficulty))
    ..take(5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Item Analysis'),
            Text(
              widget.subject.displayName,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: AppColors.brandGreen,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export exam summary',
            onSelected: (value) async {
              final section = widget.sectionFilter;
              if (section == null || section.trim().isEmpty) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Open item analysis from a section to export an exam summary.',
                    ),
                  ),
                );
                return;
              }

              final ok = value == 'pdf'
                  ? await ExportService.instance.shareExamSummaryPdf(
                      subject: widget.subject,
                      sectionName: section,
                    )
                  : await ExportService.instance.shareExamSummaryCsv(
                      subject: widget.subject,
                      sectionName: section,
                    );

              if (!context.mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Exam summary shared.' : 'Exam summary export failed.',
                  ),
                  backgroundColor:
                      ok ? AppColors.brandGreen : AppColors.error,
                ),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Exam Summary PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Exam Summary CSV'),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: (mode) {
              setState(() {
                _sortMode = mode;
                _sortAnalyses();
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Icon(Icons.format_list_numbered,
                        color: _sortMode == 0 ? AppColors.brandGreen : null),
                    const SizedBox(width: 8),
                    const Text('By Question #'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward,
                        color: _sortMode == 1 ? AppColors.brandGreen : null),
                    const SizedBox(width: 8),
                    const Text('Hardest First'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward,
                        color: _sortMode == 2 ? AppColors.brandGreen : null),
                    const SizedBox(width: 8),
                    const Text('Easiest First'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
                _showDistribution ? Icons.pie_chart : Icons.pie_chart_outline),
            tooltip: 'Toggle answer distribution',
            onPressed: () =>
                setState(() => _showDistribution = !_showDistribution),
          ),
        ],
      ),
      body: _totalAttempts == 0
          ? (_isLoading ? _buildLoadingView() : _buildNoDataView())
          : _buildAnalysisView(),
    );
  }

  Widget _buildLoadingView() {
    return LoadingIndicators.inline(message: 'Analyzing exam results...');
  }

  Widget _buildNoDataView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_outlined,
                  size: 64, color: AppColors.brandMuted.withValues(alpha: 0.55)),
              const SizedBox(height: 16),
              const Text(
                'No scan data yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan some answer sheets for "${widget.subject.displayName}" to see question analysis.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.brandMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisView() {
    final hardest = _hardestQuestions.take(3).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Responses',
                        value: '$_totalAttempts',
                        icon: Icons.people,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Avg. Difficulty',
                        value: '${(_overallDifficulty * 100).round()}%',
                        icon: Icons.speed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Questions',
                        value: '${widget.subject.totalQuestions}',
                        icon: Icons.quiz,
                      ),
                    ),
                  ],
                ),
                if (hardest.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hardest Questions',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                              Text(
                                hardest
                                    .map((q) =>
                                        'Q${q.questionNumber} (${(q.difficulty * 100).round()}%)')
                                    .join(', '),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Question list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _questionAnalyses.length,
            itemBuilder: (context, index) {
              final q = _questionAnalyses[index];
              return _QuestionAnalysisCard(
                analysis: q,
                showDistribution: _showDistribution,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.brandGreen, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionAnalysisCard extends StatelessWidget {
  final QuestionAnalysis analysis;
  final bool showDistribution;

  const _QuestionAnalysisCard({
    required this.analysis,
    required this.showDistribution,
  });

  @override
  Widget build(BuildContext context) {
    final correctPct = (analysis.difficulty * 100).round();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Question number
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: analysis.difficultyColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: analysis.difficultyColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '${analysis.questionNumber}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: analysis.difficultyColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Answer: ${analysis.correctAnswer}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: analysis.difficultyColor
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              analysis.difficultyLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: analysis.difficultyColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${analysis.correctCount}/${analysis.totalAttempts} correct',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (analysis.discriminationIndex != null)
                            Text(
                              'D: ${analysis.discriminationIndex!.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: analysis.discriminationIndex! >= 0.3
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Circular progress
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: analysis.difficulty,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                            AlwaysStoppedAnimation(analysis.difficultyColor),
                        strokeWidth: 4,
                      ),
                      Text(
                        '$correctPct%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: analysis.difficultyColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Answer distribution
            if (showDistribution && analysis.answerDistribution.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _AnswerDistributionBar(
                distribution: analysis.answerDistribution,
                correctAnswer: analysis.correctAnswer,
                totalAttempts: analysis.totalAttempts,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnswerDistributionBar extends StatelessWidget {
  final Map<String, int> distribution;
  final String correctAnswer;
  final int totalAttempts;

  const _AnswerDistributionBar({
    required this.distribution,
    required this.correctAnswer,
    required this.totalAttempts,
  });

  @override
  Widget build(BuildContext context) {
    // Sort answers A-E
    final sortedAnswers = ['A', 'B', 'C', 'D', 'E']
        .where((a) => distribution.containsKey(a))
        .toList();

    // Add any other answers (like blank)
    for (final key in distribution.keys) {
      if (!sortedAnswers.contains(key)) {
        sortedAnswers.add(key);
      }
    }

    return Row(
      children: sortedAnswers.map((answer) {
        final count = distribution[answer] ?? 0;
        final pct = totalAttempts > 0 ? count / totalAttempts : 0.0;
        final isCorrect = answer == correctAnswer;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              children: [
                // Bar
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: isCorrect
                        ? Colors.green.shade100
                        : Colors.grey.shade100,
                    border: Border.all(
                      color: isCorrect ? Colors.green : Colors.grey.shade300,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      FractionallySizedBox(
                        heightFactor: pct,
                        widthFactor: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color:
                                isCorrect ? Colors.green : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Label
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      answer,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isCorrect ? FontWeight.bold : FontWeight.normal,
                        color: isCorrect ? Colors.green.shade700 : null,
                      ),
                    ),
                    if (isCorrect)
                      const Icon(Icons.check, size: 10, color: Colors.green),
                  ],
                ),
                Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
