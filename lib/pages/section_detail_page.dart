import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/pages/answer_key_page.dart';
import 'package:omr_app/services/backup_service.dart';
import 'package:omr_app/services/export_service.dart';
import 'package:omr_app/services/import_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/app_bottom_sheet.dart';
import 'package:omr_app/widgets/app_card.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/utils/user_error_messages.dart';

class SectionDetailPage extends StatefulWidget {
  final String sectionName;

  const SectionDetailPage({super.key, required this.sectionName});

  @override
  State<SectionDetailPage> createState() => _SectionDetailPageState();
}

class _SectionDetailPageState extends State<SectionDetailPage> {
  static const Color brandGreen = AppColors.brandGreen;
  static const Color brandGreenDark = AppColors.brandGreenDark;
  static const Color brandSurface = AppColors.brandSurface;
  static const Color brandBorder = AppColors.brandBorder;
  static const Color brandText = AppColors.brandText;
  static const Color brandMuted = AppColors.brandMuted;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  int _sortMode = 0;
  bool _sortAscending = true;
  bool _mutated = false;

  String get _sectionKey => _normalizeSectionName(widget.sectionName);
  List<Student> get _sectionStudents => globalStudentDatabase
      .where((student) => _normalizeSectionName(student.section) == _sectionKey)
      .toList();

  List<Subject> get _explicitlyAssignedSubjects =>
      globalSubjects.where((subject) {
        final sectionNames = subject.sectionNames;
        if (sectionNames == null || sectionNames.isEmpty) {
          return false;
        }

        return sectionNames.any(
          (name) => _normalizeSectionName(name) == _sectionKey,
        );
      }).toList();

  List<Subject> get _trackedSubjects {
    final assignedSubjects = _explicitlyAssignedSubjects;
    if (assignedSubjects.isNotEmpty) {
      return assignedSubjects;
    }

    return const <Subject>[];
  }

  int get _scannedStudentsCount => _sectionStudents
      .where(
        (student) => _latestResultForStudent(student) != null,
      )
      .length;

  double get _averagePercentage {
    final percentages = _sectionStudents
        .map(_percentageForStudent)
        .whereType<double>()
        .toList();

    if (percentages.isEmpty) {
      return 0;
    }

    final total = percentages.reduce((value, element) => value + element);
    return total / percentages.length;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeSectionName(String value) => normalizeSectionName(value);

  String _canonicalizeSectionName(String value) => normalizeSectionName(value);

  List<String> get _allSectionNames {
    final names = <String>{};
    for (final section in globalSections) {
      final name = normalizeSectionName(section.name);
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    for (final student in globalStudentDatabase) {
      final name = normalizeSectionName(student.section);
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    return names.toList()..sort();
  }

  String _subjectLabel(Subject subject) => subject.displayName;

  List<ScanResult> _resultsForStudent(Student student) {
    final results = globalScanResults
        .where((result) => result.studentOmrId == student.omrId)
        .toList()
      ..sort((a, b) => b.scanTime.compareTo(a.scanTime));

    return results;
  }

  ScanResult? _latestResultForStudent(Student student) {
    final results = _resultsForStudent(student);
    if (results.isEmpty) {
      return null;
    }

    return results.first;
  }

  double? _percentageForStudent(Student student) {
    final latestResult = _latestResultForStudent(student);
    if (latestResult != null) {
      return latestResult.percentage;
    }

    // No scan result = no percentage to show
    // Legacy student.score field is deprecated
    return null;
  }

  String _scoreTextForStudent(Student student) {
    final latestResult = _latestResultForStudent(student);
    if (latestResult != null) {
      return '${latestResult.scoreDisplay}/${latestResult.totalQuestions}';
    }

    // No scan result = no score to show
    return '--';
  }

  Future<void> _handleImport() async {
    try {
      final summary = await ImportService.importStudentData();

      if (mounted) {
        if (summary.wasCancelled) {
          return;
        }

        _showSnackBar(
          summary.feedbackMessage,
          backgroundColor: summary.imported > 0 ? brandGreen : Colors.orange,
        );
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          'Import failed. Please try again.',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _assignSubjectToSection(Subject subject) async {
    final sectionNames = List<String>.from(subject.sectionNames ?? <String>[]);
    final alreadyAssigned = sectionNames.any(
      (name) => _normalizeSectionName(name) == _sectionKey,
    );

    if (alreadyAssigned) {
      _showSnackBar(
          '${_subjectLabel(subject)} is already assigned to ${widget.sectionName}.');
      return;
    }

    final updatedSubject = Subject(
      id: subject.id,
      name: subject.name,
      answerKey: subject.answerKey,
      totalQuestions: subject.totalQuestions,
      sectionNames: [...sectionNames, widget.sectionName],
      sectionQrData: Map<String, String>.from(subject.sectionQrData),
      examDate: subject.examDate,
      passingScore: subject.passingScore,
      usePartialCredit: subject.usePartialCredit,
    );

    await LocalDataStore.instance.upsertSubject(updatedSubject);

    if (!mounted) {
      return;
    }

    setState(() {});

    _showSnackBar('${_subjectLabel(subject)} added to ${widget.sectionName}.');
  }

  Future<void> _createSubjectForSection() async {
    final subject = await Navigator.push<Subject>(
      context,
      MaterialPageRoute(
        builder: (context) => AnswerKeyPage(initialSection: widget.sectionName),
      ),
    );

    if (!mounted || subject == null) {
      return;
    }

    await _assignSubjectToSection(subject);
  }

  void _showAddSubjectSheet() {
    final availableSubjects = globalSubjects.where((subject) {
      final sectionNames = subject.sectionNames ?? <String>[];
      return !sectionNames.any(
        (name) => _normalizeSectionName(name) == _sectionKey,
      );
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: AppBottomSheet.contentPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppBottomSheet.header(
                title: 'Add Subject',
                subtitle:
                    'Assign an existing answer key or create a new subject for ${widget.sectionName}.',
              ),
              AppPrimaryButton(
                label: 'Create New Subject',
                icon: Icons.add_circle_outline_rounded,
                onPressed: () {
                  Navigator.pop(context);
                  _createSubjectForSection();
                },
              ),
              const SizedBox(height: 18),
              const Text(
                'Existing Answer Keys',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: brandText,
                ),
              ),
              const SizedBox(height: 12),
              if (availableSubjects.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(18),
                  child: const Text(
                    'All available subjects are already assigned to this section.',
                    style: TextStyle(
                      color: brandMuted,
                      height: 1.4,
                    ),
                  ),
                )
              else
                ...availableSubjects.map(
                  (subject) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: brandSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: brandBorder),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: brandGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: brandGreen,
                        ),
                      ),
                      title: Text(
                        _subjectLabel(subject),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('${subject.totalQuestions} questions'),
                      trailing: const Icon(Icons.add_rounded),
                      onTap: () async {
                        Navigator.pop(context);
                        await _assignSubjectToSection(subject);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Student> _getFilteredAndSortedStudents() {
    final filteredStudents = _sectionStudents.where((student) {
      if (_searchQuery.isEmpty) {
        return true;
      }

      final query = _searchQuery.toLowerCase();
      return student.name.toLowerCase().contains(query) ||
          student.schoolId.toLowerCase().contains(query) ||
          student.omrId.toLowerCase().contains(query);
    }).toList();

    filteredStudents.sort((a, b) {
      int result = 0;

      if (_sortMode == 0) {
        result = a.omrId.compareTo(b.omrId);
      } else if (_sortMode == 1) {
        result = a.name.compareTo(b.name);
      } else {
        final aScore = _percentageForStudent(a);
        final bScore = _percentageForStudent(b);

        if (aScore == null && bScore == null) {
          result = 0;
        } else if (aScore == null) {
          result = 1;
        } else if (bScore == null) {
          result = -1;
        } else {
          result = aScore.compareTo(bScore);
        }
      }

      return _sortAscending ? result : -result;
    });

    return filteredStudents;
  }

  void _showStudentDetails(Student student) {
    final subjectResults = _resultsForStudent(student);
    final latestPercentage = _percentageForStudent(student);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: brandBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: brandSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: brandBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: latestPercentage != null
                        ? brandGreen
                        : const Color(0xFF8AA497),
                    child: Text(
                      student.omrId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: brandText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID ${student.schoolId} • OMR ${student.omrId}',
                          style: const TextStyle(
                            color: brandMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestPercentage != null
                              ? '${_scoreTextForStudent(student)} • ${latestPercentage.toStringAsFixed(1)}%'
                              : 'No graded result yet',
                          style: const TextStyle(
                            color: brandGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Subject Results',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: brandText,
              ),
            ),
            const SizedBox(height: 12),
            if (subjectResults.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: brandBorder),
                ),
                child: const Text(
                  'No detailed scan results are available for this student yet.',
                  style: TextStyle(
                    color: brandMuted,
                    height: 1.4,
                  ),
                ),
              )
            else
              ...subjectResults.map(
                (result) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: brandBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.subjectName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: brandText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Score ${result.scoreDisplay}/${result.totalQuestions} • ${result.percentage.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: brandMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Scanned ${_formatDate(result.scanTime)}',
                              style: const TextStyle(
                                color: brandMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: result.passed
                              ? brandGreen.withValues(alpha: 0.12)
                              : const Color(0xFFFDECEC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          result.passed ? 'PASS' : 'REVIEW',
                          style: TextStyle(
                            color: result.passed ? brandGreen : Colors.red,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _confirmRemoveStudent(student);
              },
              icon: const Icon(Icons.person_remove_rounded, color: Colors.red),
              label: const Text(
                'Remove student',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFECACA)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveStudent(Student student) async {
    final scanCount = _resultsForStudent(student).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove student?'),
        content: Text(
          'Remove ${student.name} from ${widget.sectionName}? '
          '${scanCount > 0 ? 'This also deletes $scanCount scan result${scanCount == 1 ? '' : 's'}.' : 'No scan results will be affected.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final summary =
          await LocalDataStore.instance.removeStudentCascade(student.omrId);
      if (!mounted) {
        return;
      }
      setState(() => _mutated = true);
      _showSnackBar(
        'Removed ${student.name}. Deleted ${summary.removedScans} scan${summary.removedScans == 1 ? '' : 's'}.',
        backgroundColor: Colors.red,
      );
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlySaveError(error),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _renameCurrentSection() async {
    final controller = TextEditingController(text: widget.sectionName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename section'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'e.g. BSIT-1A',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _canonicalizeSectionName(controller.text),
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || !mounted) {
      return;
    }

    try {
      await LocalDataStore.instance.renameSection(
        oldName: widget.sectionName,
        newName: newName,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlySaveError(error),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _mergeCurrentSection() async {
    final otherSections = _allSectionNames
        .where((name) => name != _sectionKey)
        .toList();

    if (otherSections.isEmpty) {
      _showSnackBar(
        'Add or import another section before merging.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    final targetName = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Merge ${widget.sectionName} into…'),
        children: otherSections
            .map(
              (name) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, name),
                child: Text(name),
              ),
            )
            .toList(),
      ),
    );

    if (targetName == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge sections?'),
        content: Text(
          'Move all students from ${widget.sectionName} into $targetName and remove ${widget.sectionName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await LocalDataStore.instance.mergeSections(
        sourceName: widget.sectionName,
        targetName: targetName,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlySaveError(error),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _deleteEmptyCurrentSection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete empty section?'),
        content: Text(
          'Remove ${widget.sectionName}? This only works when no students are assigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await LocalDataStore.instance.deleteEmptySection(widget.sectionName);
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlySaveError(error),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _deleteCurrentSectionWithStudents() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete ${widget.sectionName} and all ${_sectionStudents.length} student${_sectionStudents.length == 1 ? '' : 's'} with their scan results?',
            ),
            const SizedBox(height: 12),
            const Text(
              'This cannot be undone. Export a backup first if you may need this data later.',
              style: TextStyle(color: brandMuted, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context, false);
              await BackupService.exportAndShare();
            },
            child: const Text('Back up first'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete class'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await LocalDataStore.instance.deleteSectionCascade(widget.sectionName);
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlySaveError(error),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  void _showSnackBar(String message, {Color backgroundColor = brandGreen}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = _getFilteredAndSortedStudents();
    final trackedSubjects = _trackedSubjects;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context, _mutated),
          ),
          title: Text(widget.sectionName),
          backgroundColor: Colors.white,
          foregroundColor: brandText,
          elevation: 0,
          surfaceTintColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort',
              onPressed: _showSortOptions,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: _showMoreOptions,
            ),
          ],
          bottom: const TabBar(
            labelColor: brandGreen,
            unselectedLabelColor: brandMuted,
            indicatorColor: brandGreen,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'Students'),
              Tab(text: 'Insights'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Students Tab
            _buildStudentsTab(students, trackedSubjects),
            // Insights Tab
            _buildInsightsTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddSubjectSheet,
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          tooltip: 'Add subject',
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }

  Widget _buildStudentsTab(
      List<Student> students, List<Subject> trackedSubjects) {
    return Column(
      children: [
        // Stats header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              _buildStatItem('${_sectionStudents.length}', 'Students'),
              _buildStatDivider(),
              _buildStatItem('$_scannedStudentsCount', 'Graded'),
              _buildStatDivider(),
              _buildStatItem(
                _averagePercentage > 0
                    ? '${_averagePercentage.toStringAsFixed(0)}%'
                    : '—',
                'Average',
              ),
              _buildStatDivider(),
              _buildStatItem('${trackedSubjects.length}', 'Subjects'),
            ],
          ),
        ),

        // Search bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search students...',
              hintStyle: const TextStyle(color: brandMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: brandMuted),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFFF1F5F9),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),

        // Student list
        Expanded(
          child: students.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: students.length,
                  itemBuilder: (context, index) =>
                      _buildStudentRow(students[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildInsightsTab() {
    final questionStats = _calculateSectionQuestionStats();
    final hasScans = globalScanResults.any((scan) {
      final student = findStudentByOmrId(scan.studentOmrId);
      return student != null && student.section == widget.sectionName;
    });

    if (!hasScans) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insights_rounded,
                size: 64, color: brandMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'No data yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: brandText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Start scanning answer sheets to see insights',
              style: TextStyle(color: brandMuted),
            ),
          ],
        ),
      );
    }

    // Sort by success rate (ascending) to find hardest questions
    final hardestQuestions = questionStats.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final top5Hard = hardestQuestions.take(5).toList();

    // Sort by success rate (descending) to find easiest questions
    final easiestQuestions = questionStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5Easy = easiestQuestions.take(5).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Section Summary
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [brandGreen, brandGreenDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Section Performance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_averagePercentage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Average Score',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$_scannedStudentsCount/${_sectionStudents.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Graded',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Challenging Questions
        if (top5Hard.isNotEmpty && top5Hard.first.value < 0.7) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: brandBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: Color(0xFFDC2626)),
                    SizedBox(width: 8),
                    Text(
                      'Challenging Questions',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: brandText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Questions most students got wrong',
                  style: TextStyle(fontSize: 12, color: brandMuted),
                ),
                const SizedBox(height: 16),
                ...top5Hard.where((e) => e.value < 0.7).map((entry) {
                  final questionNum = entry.key;
                  final successRate = entry.value;
                  final failRate = 1 - successRate;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Q$questionNum',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: failRate,
                                  backgroundColor: const Color(0xFFDCFCE7),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Color(0xFFEF4444)),
                                  minHeight: 10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(failRate * 100).round()}% got it wrong',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: brandMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Easy Questions (mastered)
        if (top5Easy.isNotEmpty && top5Easy.first.value >= 0.8) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: brandBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 20, color: Color(0xFF16A34A)),
                    SizedBox(width: 8),
                    Text(
                      'Well Understood',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: brandText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Questions most students got right',
                  style: TextStyle(fontSize: 12, color: brandMuted),
                ),
                const SizedBox(height: 16),
                ...top5Easy.where((e) => e.value >= 0.8).map((entry) {
                  final questionNum = entry.key;
                  final successRate = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Q$questionNum',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: successRate,
                                  backgroundColor: const Color(0xFFFEE2E2),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          Color(0xFF16A34A)),
                                  minHeight: 10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(successRate * 100).round()}% got it right',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: brandMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Grade distribution for this section
        _buildSectionGradeDistribution(),

        const SizedBox(height: 80), // Space for FAB
      ],
    );
  }

  Map<int, double> _calculateSectionQuestionStats() {
    final questionCorrect = <int, double>{};
    final questionTotal = <int, int>{};

    for (final scan in globalScanResults) {
      // Only include scans from this section
      final student = findStudentByOmrId(scan.studentOmrId);
      if (student == null || student.section != widget.sectionName) continue;

      if (scan.detectedAnswers.isEmpty) continue;

      for (final entry in scan.correctnessMap.entries) {
        final qNum = entry.key;
        final earnedCredit = entry.value;

        questionTotal[qNum] = (questionTotal[qNum] ?? 0) + 1;
        questionCorrect[qNum] = (questionCorrect[qNum] ?? 0) + earnedCredit;
      }
    }

    final stats = <int, double>{};
    for (final qNum in questionTotal.keys) {
      final correct = questionCorrect[qNum] ?? 0;
      final total = questionTotal[qNum]!;
      stats[qNum] = correct / total;
    }

    return stats;
  }

  Widget _buildSectionGradeDistribution() {
    final distribution = {'A': 0, 'B': 0, 'C': 0, 'D': 0, 'F': 0};

    for (final scan in globalScanResults) {
      final student = findStudentByOmrId(scan.studentOmrId);
      if (student == null || student.section != widget.sectionName) continue;

      final percentage = scan.totalQuestions > 0
          ? (scan.score / scan.totalQuestions) * 100
          : 0;

      if (percentage >= 90) {
        distribution['A'] = distribution['A']! + 1;
      } else if (percentage >= 80) {
        distribution['B'] = distribution['B']! + 1;
      } else if (percentage >= 70) {
        distribution['C'] = distribution['C']! + 1;
      } else if (percentage >= 60) {
        distribution['D'] = distribution['D']! + 1;
      } else {
        distribution['F'] = distribution['F']! + 1;
      }
    }

    final hasData = distribution.values.any((count) => count > 0);
    if (!hasData) return const SizedBox.shrink();

    final maxCount = distribution.values.reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 20, color: brandMuted),
              SizedBox(width: 8),
              Text(
                'Grade Distribution',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...['A', 'B', 'C', 'D', 'F'].map((grade) {
            final count = distribution[grade] ?? 0;
            final percentage = maxCount > 0 ? count / maxCount : 0.0;
            final color = _gradeColor(grade);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      grade,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: brandSurface,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: brandMuted,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'A':
        return const Color(0xFF16A34A);
      case 'B':
        return const Color(0xFF2DD4BF);
      case 'C':
        return const Color(0xFFF59E0B);
      case 'D':
        return const Color(0xFFF97316);
      case 'F':
        return const Color(0xFFEF4444);
      default:
        return brandMuted;
    }
  }

  Widget _buildStatItem(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: brandText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: brandMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded,
              size: 64, color: brandMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No students found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: brandText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : 'Import a student roster to get started',
            style: const TextStyle(color: brandMuted),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            AppPrimaryButton(
              label: 'Import Students',
              icon: Icons.upload_rounded,
              expanded: false,
              onPressed: _handleImport,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentRow(Student student) {
    final percentage = _percentageForStudent(student);
    final isGraded = percentage != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showStudentDetails(student),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // OMR ID badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isGraded ? brandGreen : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    student.omrId,
                    style: TextStyle(
                      color: isGraded ? Colors.white : brandMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name and ID
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: brandText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        student.schoolId,
                        style: const TextStyle(
                          fontSize: 13,
                          color: brandMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // Score
                if (isGraded)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: brandGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: brandGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Pending',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: brandMuted.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: brandBorder,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Sort By',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: brandText)),
            const SizedBox(height: 8),
            _buildSortOption(0, 'OMR ID', Icons.tag_rounded),
            _buildSortOption(1, 'Name', Icons.person_rounded),
            _buildSortOption(2, 'Score', Icons.grade_rounded),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(int mode, String label, IconData icon) {
    final isSelected = _sortMode == mode;
    return ListTile(
      leading: Icon(icon, color: isSelected ? brandGreen : brandMuted),
      title: Text(label,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500)),
      trailing: isSelected
          ? Icon(
              _sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: brandGreen,
              size: 20)
          : null,
      onTap: () {
        setState(() {
          if (_sortMode == mode) {
            _sortAscending = !_sortAscending;
          } else {
            _sortMode = mode;
            _sortAscending = true;
          }
        });
        Navigator.pop(context);
      },
    );
  }

  List<Subject> get _subjectsWithSectionResults {
    return _trackedSubjects.where((subject) {
      return globalScanResults.any((result) {
        if (result.subjectId != subject.id) {
          return false;
        }
        final student = globalStudentIndex[result.studentOmrId];
        return student != null &&
            _normalizeSectionName(student.section) == _sectionKey;
      });
    }).toList();
  }

  Future<Subject?> _pickSubjectForSummary(List<Subject> subjects) async {
    if (subjects.isEmpty) {
      return null;
    }
    if (subjects.length == 1) {
      return subjects.first;
    }

    return showModalBottomSheet<Subject>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose subject for exam summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: brandText,
                ),
              ),
              const SizedBox(height: 12),
              ...subjects.map(
                (subject) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_rounded, color: brandGreen),
                  title: Text(
                    _subjectLabel(subject),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${subject.totalQuestions} questions'),
                  onTap: () => Navigator.pop(context, subject),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareExamSummary({required bool asPdf}) async {
    final subjects = _subjectsWithSectionResults;
    if (subjects.isEmpty) {
      _showSnackBar(
        'Scan at least one graded sheet before exporting an exam summary.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    final subject = await _pickSubjectForSummary(subjects);
    if (!mounted || subject == null) {
      return;
    }

    final ok = asPdf
        ? await ExportService.instance.shareExamSummaryPdf(
            subject: subject,
            sectionName: widget.sectionName,
          )
        : await ExportService.instance.shareExamSummaryCsv(
            subject: subject,
            sectionName: widget.sectionName,
          );

    if (!mounted) {
      return;
    }

    _showSnackBar(
      ok ? 'Exam summary shared.' : 'Exam summary export failed.',
      backgroundColor: ok ? brandGreen : Colors.red,
    );
  }

  Future<void> _exportSectionResults() async {
    final section = widget.sectionName;
    final count = globalScanResults.where((r) {
      final st = globalStudentIndex[r.studentOmrId];
      return st != null && _normalizeSectionName(st.section) == _sectionKey;
    }).length;

    if (count == 0) {
      _showSnackBar(
        'No scan results for this section yet.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Export — $section',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: brandText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$count result${count == 1 ? '' : 's'} for this section',
                style: const TextStyle(color: brandMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.table_chart, color: brandGreen),
                title: const Text('CSV (Excel / Sheets)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await ExportService.instance
                      .shareResultsCsv(sectionName: section);
                  if (mounted) {
                    _showSnackBar(
                      ok ? 'CSV shared.' : 'Export failed.',
                      backgroundColor: ok ? brandGreen : Colors.red,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('PDF report'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await ExportService.instance
                      .shareResultsPdf(sectionName: section);
                  if (mounted) {
                    _showSnackBar(
                      ok ? 'PDF shared.' : 'Export failed.',
                      backgroundColor: ok ? brandGreen : Colors.red,
                    );
                  }
                },
              ),
              const Divider(height: 24),
              Text(
                'Exam summary',
                style: TextStyle(
                  color: brandMuted.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.summarize_rounded, color: brandGreenDark),
                title: const Text('Exam Summary (PDF)'),
                subtitle: const Text(
                  'Class average, pass rate, and top missed questions',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareExamSummary(asPdf: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_view_rounded, color: brandGreen),
                title: const Text('Exam Summary (Excel/CSV)'),
                subtitle: const Text('Same summary in spreadsheet format'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _shareExamSummary(asPdf: false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: brandBorder,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.upload_rounded),
              title: const Text('Import Students'),
              onTap: () {
                Navigator.pop(context);
                _handleImport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Export Results'),
              onTap: () {
                Navigator.pop(context);
                _exportSectionResults();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename section'),
              onTap: () {
                Navigator.pop(context);
                _renameCurrentSection();
              },
            ),
            if (_allSectionNames.length > 1)
              ListTile(
                leading: const Icon(Icons.merge_rounded),
                title: const Text('Merge into another section'),
                onTap: () {
                  Navigator.pop(context);
                  _mergeCurrentSection();
                },
              ),
            if (_sectionStudents.isEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text(
                  'Delete empty section',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteEmptyCurrentSection();
                },
              ),
            if (_sectionStudents.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                title: const Text(
                  'Delete class',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteCurrentSectionWithStudents();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final hour =
        date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.month}/${date.day}/${date.year} $hour:$minute $suffix';
  }
}
