import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/exam_data.dart' as persisted;
import 'package:omr_app/pages/answer_key_page.dart';
import 'package:omr_app/pages/answer_sheet_generator.dart';
import 'package:omr_app/pages/item_analysis_page.dart';
import 'package:omr_app/pages/login_page.dart';
import 'package:omr_app/pages/omr_id_list_page.dart';
import 'package:omr_app/pages/scanner_page.dart';
import 'package:omr_app/pages/section_detail_page.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/services/app_update_service.dart';
import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:omr_app/services/backup_service.dart';
import 'package:omr_app/services/export_service.dart';
import 'package:omr_app/services/import_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/services/supabase_sync_service.dart';
import 'package:omr_app/services/sync_preferences_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_text_styles.dart';
import 'package:omr_app/widgets/app_card.dart';
import 'package:omr_app/widgets/app_empty_state.dart';
import 'package:omr_app/widgets/dashboard/classes_search_filters.dart';
import 'package:omr_app/widgets/dashboard/dashboard_top_bar.dart';
import 'package:omr_app/widgets/dashboard/home_next_action_line.dart';
import 'package:omr_app/widgets/dashboard/tool_section.dart';
import 'package:omr_app/widgets/app_bottom_sheet.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/loading_indicators.dart';
import 'package:omr_app/widgets/auth_shell.dart';

class DashboardPageData {
  final List<Student> students;
  final List<Section> sections;
  final List<Subject> subjects;
  final List<ScanResult> scanResults;
  final List<Deadline> deadlines;
  final List<ExportRecord> exportRecords;

  const DashboardPageData({
    this.students = const <Student>[],
    this.sections = const <Section>[],
    this.subjects = const <Subject>[],
    this.scanResults = const <ScanResult>[],
    this.deadlines = const <Deadline>[],
    this.exportRecords = const <ExportRecord>[],
  });

  factory DashboardPageData.fromMemory() => DashboardPageData(
        students: List<Student>.from(globalStudentDatabase),
        sections: List<Section>.from(globalSections),
        subjects: List<Subject>.from(globalSubjects),
        scanResults: List<ScanResult>.from(globalScanResults),
        deadlines: List<Deadline>.from(globalDeadlines),
        exportRecords: List<ExportRecord>.from(globalExportRecords),
      );
}

class DashboardPage extends StatefulWidget {
  final DashboardPageData? initialData;

  const DashboardPage({super.key, this.initialData});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _sectionController = TextEditingController();
  final TextEditingController _classesSearchController = TextEditingController();
  String _classesSearchQuery = '';
  int _classesStatusFilter = 0;
  final Set<String> _collapsedClassGroups = <String>{};

  int _selectedIndex = 0;
  bool _isImporting = false;
  bool _isLoadingData = true;
  bool _isSyncing = false;
  int _pendingSyncCount = 0;
  DateTime? _lastSyncAt;
  String? _dataLoadError;
  SyncSummary? _lastSyncSummary;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasOffline = false;
  bool _autoSyncOnWifi = true;
  bool _isRetryingDataLoad = false;
  AppUpdateInfo? _updateInfo;
  List<Student> _studentsData = <Student>[];
  List<Section> _sectionRecords = <Section>[];
  List<Subject> _subjectRecords = <Subject>[];
  List<ScanResult> _scanResultsData = <ScanResult>[];
  List<Deadline> _deadlineRecords = <Deadline>[];
  List<ExportRecord> _exportRecordsData = <ExportRecord>[];
  Map<String, Student> _studentIndex = <String, Student>{};

  @override
  void initState() {
    super.initState();
    final initialData = widget.initialData;
    if (initialData != null) {
      _applyDashboardData(initialData);
      _isLoadingData = false;
    } else {
      unawaited(_loadDashboardData());
    }
    unawaited(_refreshSyncStatus());
    unawaited(_loadAutoSyncPreference());
    unawaited(_checkForAppUpdate());
    _initConnectivityListener();
  }

  Future<void> _checkForAppUpdate() async {
    if (!SupabaseService.isReady) {
      return;
    }
    final info = await AppUpdateService.check();
    if (!mounted || !info.updateAvailable) {
      return;
    }
    setState(() => _updateInfo = info);
  }

  Widget _buildUpdateBanner(AppUpdateInfo info) {
    final versionLabel = info.latestVersion == null
        ? 'A new version is available.'
        : 'Update available: ${info.latestVersion}.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: AppColors.brandGreenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  versionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandText,
                  ),
                ),
                Text(
                  info.notes?.trim().isNotEmpty == true
                      ? info.notes!.trim()
                      : 'Ask your IT/admin for the latest APK.',
                  style: const TextStyle(color: AppColors.brandMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (info.downloadUrl != null && info.downloadUrl!.isNotEmpty)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: info.downloadUrl!),
                );
                if (!mounted) {
                  return;
                }
                _showSnackBar(
                  'Download link copied. Paste it in your browser.',
                  backgroundColor: AppColors.brandGreen,
                );
              },
              child: const Text('Copy link'),
            ),
          if (!info.mandatory)
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close_rounded, color: AppColors.brandMuted),
              onPressed: () => setState(() => _updateInfo = null),
            ),
        ],
      ),
    );
  }

  Future<void> _loadAutoSyncPreference() async {
    final enabled = await SyncPreferencesService.getAutoSyncOnWifi();
    if (!mounted) {
      return;
    }
    setState(() => _autoSyncOnWifi = enabled);
  }

  List<Student> get globalStudentDatabase => _studentsData;
  List<Section> get globalSections => _sectionRecords;
  List<Subject> get globalSubjects => _subjectRecords;
  List<ScanResult> get globalScanResults => _scanResultsData;
  List<Deadline> get globalDeadlines => _deadlineRecords;
  List<ExportRecord> get globalExportRecords => _exportRecordsData;

  Student? findStudentByOmrId(String omrId) => _studentIndex[omrId];

  void _applyDashboardData(DashboardPageData data) {
    _studentsData = List<Student>.from(data.students);
    _sectionRecords = List<Section>.from(data.sections);
    _subjectRecords = List<Subject>.from(data.subjects);
    _scanResultsData = List<ScanResult>.from(data.scanResults);
    _deadlineRecords = List<Deadline>.from(data.deadlines);
    _exportRecordsData = List<ExportRecord>.from(data.exportRecords);
    _studentIndex = <String, Student>{
      for (final student in _studentsData) student.omrId: student,
    };
  }

  List<ScanResult> findScansBySubject(String subjectId) => globalScanResults
      .where((result) => result.subjectId == subjectId)
      .toList();

  Future<void> _loadDashboardData({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() => _isLoadingData = true);
    }

    try {
      await LocalDataStore.instance.claimUnownedDataForCurrentTeacher();
      await LocalDataStore.instance.reloadForCurrentTeacher();
      if (!mounted) {
        return;
      }

      setState(() {
        _applyDashboardData(
          DashboardPageData(
            students: List<Student>.from(persisted.globalStudentDatabase),
            sections: List<Section>.from(persisted.globalSections),
            subjects: List<Subject>.from(persisted.globalSubjects),
            scanResults: List<ScanResult>.from(persisted.globalScanResults),
            deadlines: List<Deadline>.from(persisted.globalDeadlines),
            exportRecords: List<ExportRecord>.from(persisted.globalExportRecords),
          ),
        );
        _isLoadingData = false;
        _dataLoadError = null;
      });
    } catch (error) {
      debugPrint('Dashboard data load failed: $error');
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _dataLoadError =
              'Could not load saved data. You can retry or continue with what is available.';
        });
      }
    }
  }

  Future<void> _retryDataLoad() async {
    if (_isRetryingDataLoad) {
      return;
    }

    setState(() => _isRetryingDataLoad = true);
    await _loadDashboardData(showLoader: true);
    if (!mounted) {
      return;
    }

    setState(() => _isRetryingDataLoad = false);

    if (_dataLoadError != null) {
      _showSnackBar(
        'Still could not load saved data. Try signing in online once, then tap Retry again.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    final studentCount = globalStudentDatabase.length;
    final sectionCount = _sections.length;
    if (studentCount == 0) {
      _showSnackBar(
        'No saved students found yet. Import your roster under Tools.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    _showSnackBar(
      'Loaded $studentCount student${studentCount == 1 ? '' : 's'} across $sectionCount section${sectionCount == 1 ? '' : 's'}.',
      backgroundColor: AppColors.brandGreen,
    );
  }

  _DashboardStats get _stats {
    final students = globalStudentDatabase.length;
    final scannedStudents =
        globalStudentDatabase.where((student) => student.score != null).length;
    final scans = globalScanResults.isNotEmpty
        ? globalScanResults.length
        : scannedStudents;
    final pending = students > scannedStudents ? students - scannedStudents : 0;

    return _DashboardStats(
      students: students,
      scans: scans,
      scannedStudents: scannedStudents,
      pending: pending,
      subjects: globalSubjects.length,
    );
  }

  String _normalizeSectionName(String value) => value.trim().toUpperCase();

  String _sectionGroupKey(String sectionName) {
    final trimmed = sectionName.trim();
    if (trimmed.isEmpty) {
      return 'Other';
    }

    final programMatch = RegExp(r'^([A-Za-z]{2,})').firstMatch(trimmed);
    if (programMatch != null) {
      return programMatch.group(1)!.toUpperCase();
    }

    final prefix = trimmed.split(RegExp(r'[-\s_/]')).first.trim();
    return prefix.isEmpty ? 'Other' : prefix.toUpperCase();
  }

  bool _sectionMatchesClassesSearch(_SectionSnapshot section) {
    final query = _classesSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return section.name.toLowerCase().contains(query);
  }

  bool _sectionMatchesClassesStatus(_SectionSnapshot section) {
    switch (_classesStatusFilter) {
      case 1:
        return section.scannedStudents > 0 && section.pending > 0;
      case 2:
        return section.pending == 0 && section.totalStudents > 0;
      case 3:
        return section.scannedStudents == 0;
      default:
        return true;
    }
  }

  List<_SectionSnapshot> _filteredClassSections(
    List<_SectionSnapshot> sections,
  ) {
    return sections
        .where(
          (section) =>
              _sectionMatchesClassesSearch(section) &&
              _sectionMatchesClassesStatus(section),
        )
        .toList();
  }

  Map<String, List<_SectionSnapshot>> _groupedClassSections(
    List<_SectionSnapshot> sections,
  ) {
    final groups = <String, List<_SectionSnapshot>>{};
    for (final section in sections) {
      final key = _sectionGroupKey(section.name);
      groups.putIfAbsent(key, () => <_SectionSnapshot>[]).add(section);
    }

    for (final group in groups.values) {
      group.sort((a, b) => a.name.compareTo(b.name));
    }

    final sortedKeys = groups.keys.toList()..sort();
    return {for (final key in sortedKeys) key: groups[key]!};
  }

  bool _shouldGroupClassSections(List<_SectionSnapshot> sections) {
    if (sections.length < 4) {
      return false;
    }
    return _groupedClassSections(sections).length > 1 ||
        sections.length >= 6;
  }

  void _toggleClassGroup(String groupKey) {
    setState(() {
      if (_collapsedClassGroups.contains(groupKey)) {
        _collapsedClassGroups.remove(groupKey);
      } else {
        _collapsedClassGroups.add(groupKey);
      }
    });
  }
  String _canonicalizeSectionName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

  String _normalizeSubjectName(String value) => value.trim().toUpperCase();

  String _subjectLabel(Subject subject) => subject.displayName;

  List<_SubjectGroup> get _subjectGroups {
    final grouped = <String, List<Subject>>{};

    for (final subject in globalSubjects) {
      final key = _normalizeSubjectName(subject.name);
      grouped.putIfAbsent(key, () => <Subject>[]).add(subject);
    }

    final groups = grouped.entries.map((entry) {
      final subjects = entry.value..sort((a, b) => a.id.compareTo(b.id));
      return _SubjectGroup(
        name: subjects.first.name,
        subjects: subjects,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return groups;
  }

  List<_SectionChoice> _sectionChoicesForGroup(_SubjectGroup group) {
    final choices = <_SectionChoice>[];

    for (final subject in group.subjects) {
      final sections = subject.sectionNames ?? const <String>[];
      for (final section in sections) {
        choices.add(_SectionChoice(subject: subject, sectionName: section));
      }
    }

    choices.sort((a, b) => a.sectionName.compareTo(b.sectionName));
    return choices;
  }

  List<_AnswerKeyRow> _answerKeyRowsForGroup(_SubjectGroup group) {
    final rows = <_AnswerKeyRow>[];

    for (final subject in group.subjects) {
      final sections = subject.sectionNames ?? const <String>[];
      if (sections.isEmpty) {
        rows.add(_AnswerKeyRow(subject: subject));
        continue;
      }

      for (final section in sections) {
        rows.add(_AnswerKeyRow(subject: subject, sectionName: section));
      }
    }

    rows.sort((a, b) {
      final aLabel = a.sectionName ?? '';
      final bLabel = b.sectionName ?? '';
      return aLabel.compareTo(bLabel);
    });
    return rows;
  }

  Future<_SectionChoice?> _pickSectionChoiceForGroup(
      _SubjectGroup group) async {
    final choices = _sectionChoicesForGroup(group);
    if (choices.isEmpty) {
      return null;
    }
    if (choices.length == 1) {
      return choices.first;
    }

    return showModalBottomSheet<_SectionChoice>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.brandBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Section for ${group.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 10),
              ...choices.map(
                (choice) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brandSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.brandBorder),
                  ),
                  child: ListTile(
                    title: Text(
                      choice.sectionName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle:
                        Text('${choice.subject.totalQuestions} questions'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, choice),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subjectKeyFromSubject(Subject subject) => subject.id;

  String _subjectKeyFromResult(ScanResult result) =>
      result.subjectId ?? _normalizeSubjectName(result.subjectName);

  List<Subject> _trackedSubjectsForSection(String sectionName) {
    final normalizedSection = _normalizeSectionName(sectionName);
    final assignedSubjects = globalSubjects.where((subject) {
      final sectionNames = subject.sectionNames;
      if (sectionNames == null || sectionNames.isEmpty) {
        return false;
      }

      return sectionNames.any(
        (name) => _normalizeSectionName(name) == normalizedSection,
      );
    }).toList();

    if (assignedSubjects.isNotEmpty) {
      return assignedSubjects;
    }

    return const <Subject>[];
  }

  Set<String> _scannedSubjectKeysForSection(String sectionName) {
    final normalizedSection = _normalizeSectionName(sectionName);
    final studentOmrIds = globalStudentDatabase
        .where(
          (student) =>
              _normalizeSectionName(student.section) == normalizedSection,
        )
        .map((student) => student.omrId)
        .toSet();

    return globalScanResults
        .where((result) => studentOmrIds.contains(result.studentOmrId))
        .map(_subjectKeyFromResult)
        .toSet();
  }

  List<_SectionSnapshot> get _sections {
    final sectionNames = <String>{};

    for (final section in globalSections) {
      final name = _normalizeSectionName(section.name);
      if (name.isNotEmpty) {
        sectionNames.add(name);
      }
    }

    for (final student in globalStudentDatabase) {
      final name = _normalizeSectionName(student.section);
      if (name.isNotEmpty) {
        sectionNames.add(name);
      }
    }

    final sections = sectionNames.map((name) {
      final students = globalStudentDatabase
          .where((student) => _normalizeSectionName(student.section) == name)
          .toList();
      final scannedStudents =
          students.where((student) => student.score != null).length;
      final trackedSubjects = _trackedSubjectsForSection(name);
      final trackedSubjectKeys =
          trackedSubjects.map(_subjectKeyFromSubject).toSet();
      final scannedSubjectKeys = _scannedSubjectKeysForSection(name);
      final scannedSubjects = trackedSubjectKeys.isEmpty
          ? scannedSubjectKeys.length
          : trackedSubjectKeys.intersection(scannedSubjectKeys).length;

      return _SectionSnapshot(
        name: name,
        totalStudents: students.length,
        scannedStudents: scannedStudents,
        totalSubjects: trackedSubjects.length,
        scannedSubjects: scannedSubjects,
      );
    }).toList();

    sections.sort((a, b) => a.name.compareTo(b.name));
    return sections;
  }

  List<_DashboardAction> get _examSetupToolActions => [
        _DashboardAction(
          label: 'Answer Keys',
          subtitle: '${globalSubjects.length} saved',
          icon: Icons.menu_book_rounded,
          color: AppColors.brandGreen,
          onTap: _openAnswerKeys,
        ),
        _DashboardAction(
          label: 'Print Sheets',
          subtitle: 'Generate answer forms',
          icon: Icons.print_rounded,
          color: const Color(0xFFB45309),
          onTap: _showBatchPrintModal,
        ),
        _DashboardAction(
          label: 'OMR ID List',
          subtitle: '${globalStudentDatabase.length} students',
          icon: Icons.tag_rounded,
          color: AppColors.brandGreenDark,
          onTap: _openOmrIdList,
        ),
      ];

  List<_DashboardAction> get _dataToolActions => [
        _DashboardAction(
          label: 'Import Roster',
          subtitle: 'Load students from Excel or CSV',
          icon: Icons.upload_rounded,
          color: AppColors.brandGreen,
          onTap: _handleImport,
        ),
        _DashboardAction(
          label: 'Export Results',
          subtitle: '${globalScanResults.length} scans',
          icon: Icons.download_rounded,
          color: AppColors.brandGreen,
          onTap: _handleExport,
        ),
      ];

  Future<void> _createNewSubject() async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (context) => const AnswerKeyPage()),
    );
    if (!mounted) {
      return;
    }
    await _loadDashboardData();
    if (!mounted) {
      return;
    }
    if (result is Subject) {
      _showSnackBar(
        '${result.displayName} created! Ready to print sheets.',
        backgroundColor: AppColors.brandGreen,
      );
    }
  }

  Future<void> _openOmrIdList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OmrIdListPage()),
    );

    if (mounted) {
      await _loadDashboardData();
    }
  }

  Future<void> _showBatchPrintModal() async {
    if (globalSubjects.isEmpty) {
      _showSnackBar(
        'Create an answer key before printing sheets.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    _SubjectGroup? selectedGroup;
    Subject? selectedSubject;
    String? selectedSection;
    int copies = 1;
    int step = 0;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final subjectGroups = _subjectGroups;
            final sectionChoices = selectedGroup == null
                ? const <_SectionChoice>[]
                : _sectionChoicesForGroup(selectedGroup!);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Print Answer Sheets',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose subject, section, then how many sheets to print.',
                  ),
                  const SizedBox(height: 16),
                  if (step == 0)
                    ...subjectGroups.map(
                      (group) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.brandSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.brandBorder),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.brandGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.menu_book_rounded,
                              color: AppColors.brandGreen,
                            ),
                          ),
                          title: Text(
                            group.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${group.subjects.length} answer key${group.subjects.length == 1 ? '' : 's'}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            setModalState(() {
                              selectedGroup = group;
                              selectedSubject = null;
                              selectedSection = null;
                              step = 1;
                            });
                          },
                        ),
                      ),
                    )
                  else if (step == 1)
                    if (sectionChoices.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.brandSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.brandBorder),
                        ),
                        child: const Text(
                          'No sections assigned to this subject yet.',
                          style: TextStyle(color: AppColors.brandMuted),
                        ),
                      )
                    else
                      ...sectionChoices.map(
                        (choice) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.brandSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.brandBorder),
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.brandGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.group_rounded,
                                color: AppColors.brandGreen,
                              ),
                            ),
                            title: Text(
                              choice.sectionName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${choice.subject.totalQuestions} questions',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              setModalState(() {
                                selectedSubject = choice.subject;
                                selectedSection = choice.sectionName;
                                step = 2;
                              });
                            },
                          ),
                        ),
                      )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subject: ${selectedSubject == null ? '' : _subjectLabel(selectedSubject!)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Section: $selectedSection',
                          style: const TextStyle(color: AppColors.brandMuted),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text(
                              'Copies',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: copies > 1
                                  ? () => setModalState(() => copies -= 1)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '$copies',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              onPressed: copies < 200
                                  ? () => setModalState(() => copies += 1)
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              try {
                                await AnswerSheetGenerator.generateMultiple(
                                  subject: selectedSubject!,
                                  sectionName: selectedSection!,
                                  copies: copies,
                                );
                              } catch (error) {
                                if (mounted) {
                                  _showSnackBar(
                                    'Unable to generate the answer sheets.',
                                    backgroundColor: Colors.red,
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.print_rounded),
                            label: Text('Print $copies sheet(s)'),
                          ),
                        ),
                      ],
                    ),
                  if (step > 0) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setModalState(() {
                        if (step == 2) {
                          step = 1;
                        } else {
                          step = 0;
                        }
                      }),
                      child: const Text('Back'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _sectionController.dispose();
    _classesSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshSyncStatus() async {
    final pending = await LocalDataStore.instance.countPendingSync();
    final lastSync = await SyncPreferencesService.getLastSyncAt();
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingSyncCount = pending;
      _lastSyncAt = lastSync;
    });
  }

  void _initConnectivityListener() {
    unawaited(_startConnectivityListener());
  }

  Future<void> _startConnectivityListener() async {
    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    if (!mounted) {
      return;
    }
    _wasOffline = !_hasNetworkConnection(initial);

    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final isOnline = _hasNetworkConnection(results);
      if (isOnline && _wasOffline) {
        unawaited(_onConnectivityRestored(results));
      }
      _wasOffline = !isOnline;
    });
  }

  bool _hasNetworkConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool _isWifiLikeConnection(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet,
    );
  }

  Future<void> _onConnectivityRestored(List<ConnectivityResult> results) async {
    if (!mounted ||
        _isSyncing ||
        !SupabaseService.isReady ||
        !SupabaseService.hasActiveSession) {
      return;
    }

    await _refreshSyncStatus();
    if (!mounted || _pendingSyncCount == 0) {
      return;
    }

    if (_autoSyncOnWifi && _isWifiLikeConnection(results)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wi-Fi is back. Syncing $_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'}…',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _handleSyncNow();
      return;
    }

    if (_autoSyncOnWifi && !_isWifiLikeConnection(results)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Online on mobile data. $_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'} waiting — connect to Wi-Fi or tap Sync now.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Sync now',
            onPressed: _handleSyncNow,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Internet is back. $_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'} waiting to sync.',
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Sync now',
          onPressed: _handleSyncNow,
        ),
      ),
    );
  }

  String _formatLastSync(DateTime? value) {
    if (value == null) {
      return 'Never';
    }
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  Future<bool> _confirmDeleteSubject(Subject subject) async {
    final linkedScans = findScansBySubject(subject.id).length;
    final linkedDeadlines = globalDeadlines
        .where((deadline) => deadline.subjectId == subject.id)
        .length;
    final sections = List<String>.from(subject.sectionNames ?? const <String>[])
      ..sort();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Answer Key?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete ${subject.displayName} and all data directly linked to this answer key?',
            ),
            if (sections.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Assigned sections: ${sections.join(', ')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (linkedScans > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$linkedScans scan result${linkedScans == 1 ? '' : 's'} will also be removed.',
              ),
            ],
            if (linkedDeadlines > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$linkedDeadlines related deadline${linkedDeadlines == 1 ? '' : 's'} will also be removed.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _openAnswerKeys() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final subjectGroups = _subjectGroups;

            Future<void> openEditor({
              Subject? subject,
              String? sectionFocus,
            }) async {
              final result = await Navigator.push<dynamic>(
                this.context,
                MaterialPageRoute(
                  builder: (context) => AnswerKeyPage(
                    subjectToEdit: subject,
                    editSectionFocus: sectionFocus,
                  ),
                ),
              );

              if (mounted) {
                await _loadDashboardData();
                if (!mounted) {
                  return;
                }
                setModalState(() {});
                if (result is AnswerKeyEditorResult) {
                  switch (result.action) {
                    case AnswerKeyEditorAction.updated:
                      final updatedSubject = result.subject;
                      if (updatedSubject != null) {
                        _showSnackBar(
                          '${updatedSubject.displayName} updated successfully.',
                          backgroundColor: AppColors.brandGreen,
                        );
                      }
                      break;
                    case AnswerKeyEditorAction.deleted:
                      final deletionSummary = result.deletionSummary;
                      final subjectName = result.subjectName ?? 'Answer key';
                      final removedScans = deletionSummary?.removedScans ?? 0;
                      _showSnackBar(
                        'Deleted $subjectName. Removed $removedScans scan${removedScans == 1 ? '' : 's'}.',
                        backgroundColor: Colors.red,
                      );
                      break;
                  }
                } else if (result is Subject) {
                  _showSnackBar(
                    '${result.displayName} created successfully.',
                    backgroundColor: AppColors.brandGreen,
                  );
                }
              }
            }

            Future<void> deleteSubject(Subject subject) async {
              final confirmed = await _confirmDeleteSubject(subject);
              if (!confirmed || !mounted) {
                return;
              }

              final summary =
                  await LocalDataStore.instance.deleteSubjectCascade(subject);

              if (mounted) {
                await _loadDashboardData();
                if (!mounted) {
                  return;
                }
                setModalState(() {});
                _showSnackBar(
                  'Deleted ${subject.displayName}. Removed ${summary.removedScans} scan${summary.removedScans == 1 ? '' : 's'}.',
                  backgroundColor: Colors.red,
                );
              }
            }

            return SingleChildScrollView(
              padding: AppBottomSheet.contentPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppBottomSheet.header(
                    title: 'Answer Keys',
                    subtitle:
                        'Review answer keys and the sections each subject is assigned to.',
                    trailing: FilledButton.icon(
                      onPressed: () => openEditor(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New'),
                    ),
                  ),
                  const Text(
                    'Need different answers per section? Create one key per section — same subject name is OK.',
                    style: TextStyle(
                      color: AppColors.brandMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (subjectGroups.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.brandSurface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.brandBorder),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 52,
                            color: AppColors.brandGreen,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No subjects yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandText,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Create your first subject to save its answer key and assign sections.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.brandMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...subjectGroups.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: AppColors.brandSurface,
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: AppColors.brandBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        group.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.brandText,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(color: AppColors.brandBorder),
                                      ),
                                      child: Text(
                                        '${group.subjects.length} key${group.subjects.length == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                          color: AppColors.brandGreen,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Section-Specific Answer Keys',
                                  style: TextStyle(
                                    color: AppColors.brandMuted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._answerKeyRowsForGroup(group).map(
                                  (row) {
                                    final sectionName = row.sectionName;
                                    final isShared = sectionName != null &&
                                        (row.subject.sectionNames?.length ??
                                                0) >
                                            1;
                                    final title = sectionName == null
                                        ? group.name
                                        : '${group.name} - $sectionName';
                                    final subtitle = sectionName == null
                                        ? 'No sections assigned · ${row.subject.totalQuestions} items'
                                        : isShared
                                            ? '${row.subject.totalQuestions} items · same key for ${row.subject.sectionNames!.length} sections'
                                            : '${row.subject.totalQuestions} items';

                                    return Container(
                                      width: double.infinity,
                                      margin:
                                          const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.brandBorder,
                                        ),
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.brandText,
                                                ),
                                              ),
                                            ),
                                            if (isShared)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.brandGreen
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  border: Border.all(
                                                    color:
                                                        AppColors.brandBorder,
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Shared',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.brandGreenDark,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        subtitle: Text(
                                          subtitle,
                                          style: const TextStyle(
                                            color: AppColors.brandMuted,
                                          ),
                                        ),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              openEditor(
                                                subject: row.subject,
                                                sectionFocus: sectionName,
                                              );
                                            } else if (value == 'analyze') {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      ItemAnalysisPage(
                                                    subject: row.subject,
                                                  ),
                                                ),
                                              );
                                            } else if (value == 'delete') {
                                              deleteSubject(row.subject);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem<String>(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'analyze',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.analytics_outlined,
                                                    size: 18,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text('Item Analysis'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline_rounded,
                                                    size: 18,
                                                    color: Colors.red,
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'Delete',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () => openEditor(
                                          subject: row.subject,
                                          sectionFocus: sectionName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Color _colorForImportSummary(ImportSummary summary) {
    if (summary.imported > 0) {
      return AppColors.brandGreen;
    }

    if (summary.skipped > 0 || summary.duplicates > 0) {
      return Colors.orange;
    }

    return AppColors.brandMuted;
  }

  Future<void> _handleImport() async {
    if (_isImporting) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      await LocalDataStore.instance.reloadForCurrentTeacher();
      final preview = await ImportService.prepareImportFromPicker();

      if (!mounted) {
        return;
      }

      if (preview == null) {
        return;
      }

      final importResult = await _confirmImportPreview(preview);
      if (importResult == null || !importResult.confirmed || !mounted) {
        return;
      }

      final summary = await ImportService.commitImport(
        preview,
        replaceRoster: importResult.replaceRoster,
      );
      await _loadDashboardData();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        summary.feedbackMessage,
        backgroundColor: _colorForImportSummary(summary),
      );
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlyImportError(error.toString()),
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<({bool confirmed, bool replaceRoster})?> _confirmImportPreview(
    ImportPreview preview,
  ) {
    final summary = preview.summary;

    var replaceRoster = false;

    return showDialog<({bool confirmed, bool replaceRoster})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final effective =
              replaceRoster ? preview.replaceRosterPreview() : preview;
          final effectiveSummary = effective.summary;
          final sectionCounts = <String, int>{};
          for (final student in effective.newStudents) {
            sectionCounts.update(student.section, (value) => value + 1,
                ifAbsent: () => 1);
          }
          for (final section in effective.newSections) {
            sectionCounts.putIfAbsent(section.name, () => 0);
          }
          final sectionEntries = sectionCounts.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          return AlertDialog(
            title: const Text('Confirm import'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ImportStatLine(
                    color: AppColors.brandGreen,
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'New students',
                    value: effectiveSummary.imported,
                  ),
                  if (effectiveSummary.updated > 0)
                    _ImportStatLine(
                      color: AppColors.brandGreenDark,
                      icon: Icons.edit_rounded,
                      label: 'Updated students',
                      value: effectiveSummary.updated,
                    ),
                  if (effectiveSummary.unchanged > 0)
                    _ImportStatLine(
                      color: AppColors.brandMuted,
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Same student ID (no change)',
                      value: effectiveSummary.unchanged,
                    ),
                  if (effectiveSummary.duplicates > 0)
                    _ImportStatLine(
                      color: const Color(0xFFD97706),
                      icon: Icons.content_copy_rounded,
                      label: 'Duplicate rows in file',
                      value: effectiveSummary.duplicates,
                    ),
                  _ImportStatLine(
                    color: const Color(0xFFDC2626),
                    icon: Icons.report_gmailerrorred_rounded,
                    label: 'Invalid rows (skipped)',
                    value: effectiveSummary.skipped,
                  ),
                  if (replaceRoster && effective.studentsToRemove.isNotEmpty)
                    _ImportStatLine(
                      color: const Color(0xFFDC2626),
                      icon: Icons.person_remove_rounded,
                      label: 'Will remove (not in file)',
                      value: effective.studentsToRemove.length,
                    ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: replaceRoster,
                    onChanged: (value) {
                      setDialogState(() => replaceRoster = value ?? false);
                    },
                    title: const Text(
                      'Replace roster',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Use only for a new semester. Updates everyone in the file and removes students not listed.',
                      style: TextStyle(fontSize: 12),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (sectionEntries.isNotEmpty) ...[
                    const Divider(height: 20),
                    Text(
                      replaceRoster
                          ? 'Sections in this file'
                          : 'Sections from this import',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandText,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...sectionEntries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: const TextStyle(
                            color: AppColors.brandMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (summary.errors.isNotEmpty) ...[
                    const Divider(height: 20),
                    const Text(
                      'First issues found',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandText,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...summary.errors.take(5).map(
                          (e) => Text(
                            '• $e',
                            style: const TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 12,
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: effective.hasNothingToImport
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          (confirmed: true, replaceRoster: replaceRoster),
                        ),
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandGreen),
                child: Text(
                  effective.hasNothingToImport
                      ? 'Already up to date'
                      : replaceRoster
                          ? 'Update roster'
                          : effectiveSummary.imported > 0
                              ? 'Add ${effectiveSummary.imported} student${effectiveSummary.imported == 1 ? '' : 's'}'
                              : 'Apply changes',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleExport() async {
    final totalScanResults = await LocalDataStore.instance.countScanResults();
    if (!mounted) {
      return;
    }
    final hasData = totalScanResults > 0;
    if (!hasData) {
      _showSnackBar('No scan results to export.',
          backgroundColor: Colors.orange);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: AppBottomSheet.contentPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBottomSheet.header(
                title: 'Export Results',
                subtitle:
                    '$totalScanResults scan result${totalScanResults == 1 ? '' : 's'} available',
              ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: AppColors.brandGreen),
              title: const Text('Export as CSV'),
              subtitle: const Text('For Excel, Google Sheets'),
              onTap: () async {
                Navigator.pop(context);
                final success = await ExportService.instance.shareResultsCsv();
                if (mounted) {
                  _showSnackBar(
                    success ? 'CSV exported successfully!' : 'Export failed',
                    backgroundColor: success ? AppColors.brandGreen : Colors.red,
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Export as PDF'),
              subtitle: const Text('Printable report'),
              onTap: () async {
                Navigator.pop(context);
                final success = await ExportService.instance.shareResultsPdf();
                if (mounted) {
                  _showSnackBar(
                    success ? 'PDF exported successfully!' : 'Export failed',
                    backgroundColor: success ? AppColors.brandGreen : Colors.red,
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.backup, color: AppColors.brandGreen),
              title: const Text('Create Backup'),
              subtitle: const Text('Save all data'),
              onTap: () async {
                Navigator.pop(context);
                final file = await ExportService.instance.createBackup();
                if (mounted) {
                  _showSnackBar(
                    file != null ? 'Backup created!' : 'Backup failed',
                    backgroundColor: file != null ? AppColors.brandGreen : Colors.red,
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _handleSignOut() async {
    await _refreshSyncStatus();
    if (_pendingSyncCount > 0 &&
        SupabaseService.isReady &&
        SupabaseService.hasActiveSession) {
      final syncFirst = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsynced changes'),
          content: Text(
            'You have $_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'} waiting to upload. Sync before signing out?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Sign out anyway'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sync first'),
            ),
          ],
        ),
      );

      if (syncFirst == true) {
        await _handleSyncNow();
      }
    }

    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You can unlock again with your offline PIN, or sign in online on this or another device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await CloudAuthService.instance.signOut();

    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _handleSyncNow() async {
    if (_isSyncing) {
      return;
    }
    if (!SupabaseService.hasActiveSession) {
      _showSnackBar(
        'Sign in online to sync your data to the cloud.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final fullSummary = await SupabaseSyncService.instance.syncAll();
      if (!mounted) {
        return;
      }
      await _loadDashboardData();
      await _refreshSyncStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastSyncSummary = fullSummary.push;
        _isSyncing = false;
      });
      final pushed = fullSummary.push.total;
      final pulled = fullSummary.pull.downloaded;
      final message = pushed == 0 && pulled == 0
          ? 'Everything is already synced.'
          : 'Downloaded $pulled cloud item${pulled == 1 ? '' : 's'} and uploaded $pushed local change${pushed == 1 ? '' : 's'}.';
      _showSnackBar(message, backgroundColor: AppColors.brandGreen);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSyncing = false);
      _showSnackBar(
        UserErrorMessages.friendlySyncError(error),
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _handleExportBackup() async {
    final success = await BackupService.exportAndShare();
    if (!mounted) {
      return;
    }
    _showSnackBar(
      success ? 'Backup exported. Keep the file private.' : 'Backup failed.',
      backgroundColor: success ? AppColors.brandGreen : Colors.red,
    );
  }

  Future<void> _handleRestoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: const Text(
          'This replaces your data with the backup file. Other teachers\' data on this device is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final restored = await BackupService.importFromPick(context);
    if (!mounted) {
      return;
    }

    if (restored) {
      await _loadDashboardData();
      await _refreshSyncStatus();
    }

    if (!mounted) {
      return;
    }

    _showSnackBar(
      restored ? 'Backup restored successfully.' : 'Backup restore cancelled.',
      backgroundColor: restored ? AppColors.brandGreen : Colors.red,
    );
  }

  void _startScanning() {
    if (globalSubjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Create an answer key before starting grading.'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () {
              _openAnswerKeys();
            },
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.brandBorder,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Start Automatic Grading',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select the subject sheet to scan. The QR code identifies the subject and the shaded OMR ID identifies the student.',
                style: TextStyle(
                  color: AppColors.brandMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              ..._subjectGroups.map(
                (group) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.brandSurface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.brandBorder),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.brandGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.fact_check_rounded,
                        color: AppColors.brandGreen,
                      ),
                    ),
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_sectionChoicesForGroup(group).length} section${_sectionChoicesForGroup(group).length == 1 ? '' : 's'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      Navigator.pop(context);

                      final choices = _sectionChoicesForGroup(group);
                      if (choices.isEmpty) {
                        if (mounted) {
                          _showSnackBar(
                            'No section assigned to ${group.name}. '
                            'Open Answer Keys, edit the subject, and select a section.',
                            backgroundColor: Colors.orange,
                          );
                        }
                        return;
                      }

                      final choice = await _pickSectionChoiceForGroup(group);
                      if (choice == null) {
                        return;
                      }

                      try {
                        // Get available cameras
                        final cameras = await availableCameras();
                        if (cameras.isEmpty) {
                          if (mounted) {
                            _showSnackBar(
                              'No camera available on this device.',
                              backgroundColor: Colors.red,
                            );
                          }
                          return;
                        }

                        // Launch the scanner
                        if (!mounted) {
                          return;
                        }

                        await Navigator.push(
                          this.context,
                          MaterialPageRoute(
                            builder: (context) => ScannerPage(
                              availableCameras: cameras,
                              targetSubject: choice.subject,
                            ),
                          ),
                        );
                        if (mounted) {
                          await _loadDashboardData();
                        }
                      } catch (error) {
                        if (mounted) {
                          _showSnackBar(
                            UserErrorMessages.friendlyError(error),
                            backgroundColor: Colors.red,
                          );
                        }
                      }
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

  void _createNewSection() {
    _sectionController.clear();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
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
              }

              if (mounted) {
                await _loadDashboardData();
              }
              if (!mounted) {
                return;
              }
              navigator.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSectionMenuAction(
    _SectionSnapshot section,
    String action,
  ) async {
    switch (action) {
      case 'rename':
        await _renameSection(section.name);
        break;
      case 'merge':
        await _mergeSection(section.name);
        break;
      case 'delete_empty':
        await _deleteEmptySection(section.name);
        break;
      case 'delete_class':
        await _deleteSectionWithStudents(section);
        break;
    }
  }

  Future<void> _renameSection(String sectionName) async {
    final controller = TextEditingController(text: sectionName);
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
      final summary = await LocalDataStore.instance.renameSection(
        oldName: sectionName,
        newName: newName,
      );
      await _loadDashboardData();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Renamed to $newName. Updated ${summary.updatedStudents} student${summary.updatedStudents == 1 ? '' : 's'}.',
        backgroundColor: AppColors.brandGreen,
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

  Future<void> _mergeSection(String sourceName) async {
    final otherSections = _sections
        .where(
          (section) =>
              _normalizeSectionName(section.name) !=
              _normalizeSectionName(sourceName),
        )
        .map((section) => section.name)
        .toList()
      ..sort();

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
        title: Text('Merge $sourceName into…'),
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
          'Move all students from $sourceName into $targetName, update answer key links, and remove $sourceName.',
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
      final summary = await LocalDataStore.instance.mergeSections(
        sourceName: sourceName,
        targetName: targetName,
      );
      await _loadDashboardData();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Merged $sourceName into $targetName. Moved ${summary.movedStudents} student${summary.movedStudents == 1 ? '' : 's'}.',
        backgroundColor: AppColors.brandGreen,
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

  Future<void> _deleteEmptySection(String sectionName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete empty section?'),
        content: Text(
          'Remove $sectionName? This only works when no students are assigned.',
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
      await LocalDataStore.instance.deleteEmptySection(sectionName);
      await _loadDashboardData();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Deleted $sectionName.',
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

  Future<void> _deleteSectionWithStudents(_SectionSnapshot section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete ${section.name} and all ${section.totalStudents} student${section.totalStudents == 1 ? '' : 's'} with their scan results?',
            ),
            const SizedBox(height: 12),
            const Text(
              'This cannot be undone. Export a backup first if you may need this data later.',
              style: TextStyle(color: AppColors.brandMuted, fontSize: 13),
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
      final summary =
          await LocalDataStore.instance.deleteSectionCascade(section.name);
      await _loadDashboardData();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        'Deleted ${section.name}. Removed ${summary.removedStudents} student${summary.removedStudents == 1 ? '' : 's'} and ${summary.removedScans} scan${summary.removedScans == 1 ? '' : 's'}.',
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

  Future<void> _openSection(String sectionName) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SectionDetailPage(sectionName: sectionName),
      ),
    );

    if (mounted) {
      await _loadDashboardData();
    }
  }

  void _showSnackBar(String message, {Color backgroundColor = AppColors.brandGreen}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final sections = _sections;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: _DashboardDrawer(
        selectedIndex: _selectedIndex,
        onSelectTab: (index) {
          Navigator.pop(context);
          _selectTab(index);
        },
        onSignOut: () {
          Navigator.pop(context);
          _handleSignOut();
        },
      ),
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _createNewSection,
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Section'),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectTab,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.brandGreen.withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Classes',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Tools',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_dataLoadError != null)
              _DashboardStatusBanner(
                message: _dataLoadError!,
                isRetrying: _isRetryingDataLoad,
                onRetry: _retryDataLoad,
              ),
            if (_updateInfo != null) _buildUpdateBanner(_updateInfo!),
            Expanded(
              child: Stack(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey(_selectedIndex),
                      child: _buildCurrentTab(stats, sections),
                    ),
                  ),
                  if (_isLoadingData)
                    Align(
                      alignment: Alignment.topCenter,
                      child: LoadingIndicators.linear(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    switch (_selectedIndex) {
      case 1:
        return _buildSectionsTab(sections);
      case 2:
        return _buildToolsTab(stats);
      case 3:
        return _buildSettingsTab(stats, sections);
      case 0:
      default:
        return _buildHomeTab(stats, sections);
    }
  }

  Widget _buildHomeTab(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    final actionCenterItems = _buildHomeActionCenterItems(stats, sections);
    final needsSetup = stats.students == 0 || stats.subjects == 0;
    final attentionItems = actionCenterItems.take(2).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _buildTopBar(
          title: 'Dashboard',
          subtitle: 'Grading progress at a glance.',
        ),
        const SizedBox(height: 16),
        _buildHomeNextActionLine(stats),
        const SizedBox(height: 14),
        _buildHomeOverviewCard(stats, sections),
        const SizedBox(height: 14),
        _buildHomeDualQuickActions(),
        if (needsSetup) ...[
          const SizedBox(height: 14),
          _buildSetupChecklist(),
        ],
        if (attentionItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildNeedsAttentionSection(attentionItems),
        ],
      ],
    );
  }

  Widget _buildHomeNextActionLine(_DashboardStats stats) {
    final flaggedScans =
        globalScanResults.where((scan) => scan.requiresReview).length;

    late final String message;
    late final VoidCallback onTap;
    late final IconData icon;

    if (stats.students == 0) {
      message = 'Import your roster to get started';
      onTap = _handleImport;
      icon = Icons.upload_rounded;
    } else if (stats.subjects == 0) {
      message = 'Create an answer key before scanning';
      onTap = _createNewSubject;
      icon = Icons.edit_note_rounded;
    } else if (flaggedScans > 0) {
      message =
          'Review $flaggedScans flagged scan${flaggedScans == 1 ? '' : 's'}';
      onTap = _showReviewQueueSheet;
      icon = Icons.rule_folder_rounded;
    } else {
      message = 'Start scanning when your class is ready';
      onTap = _startScanning;
      icon = Icons.qr_code_scanner_rounded;
    }

    return HomeNextActionLine(
      message: message,
      icon: icon,
      onTap: onTap,
    );
  }

  Widget _buildHomeOverviewCard(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    final completion = stats.students == 0 ? 0 : (stats.progress * 100).round();
    final flaggedScans =
        globalScanResults.where((scan) => scan.requiresReview).length;
    final hasFlaggedScans = flaggedScans > 0;
    final summaryLine = stats.students == 0
        ? 'Import a roster to get started'
        : '${stats.students} students · ${stats.pending} pending';
    final secondaryActionLabel =
        hasFlaggedScans ? 'Review' : 'Open Classes';
    final secondaryActionIcon = hasFlaggedScans
        ? Icons.rule_folder_rounded
        : Icons.groups_rounded;
    final secondaryActionTap = hasFlaggedScans
        ? _showReviewQueueSheet
        : () => _selectTab(1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), AppColors.brandGreenDark, AppColors.brandGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreenDark.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$completion% complete',
            style: const TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summaryLine,
            style: const TextStyle(
              color: Color(0xFFE7FFF4),
              height: 1.35,
              fontSize: 14,
            ),
          ),
          if (stats.students > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: stats.progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
          if (hasFlaggedScans) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: _showReviewQueueSheet,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$flaggedScans need review',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_pendingSyncCount > 0) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: _isSyncing ? null : _handleSyncNow,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_upload_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        !SupabaseService.hasActiveSession
                            ? '$_pendingSyncCount waiting — sign in online to upload'
                            : '$_pendingSyncCount waiting to sync — tap to upload',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroActionButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Start Scan',
                  filled: true,
                  onTap: _startScanning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroActionButton(
                  icon: secondaryActionIcon,
                  label: secondaryActionLabel,
                  onTap: secondaryActionTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_HomePriorityAction> _buildHomeActionCenterItems(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    final actions = <_HomePriorityAction>[];
    final flaggedScans =
        globalScanResults.where((scan) => scan.requiresReview).length;

    if (stats.students == 0) {
      actions.add(
        _HomePriorityAction(
          tag: 'Start here',
          title: 'Import your first roster',
          subtitle:
              'Load students from Excel or CSV so classes, IDs, and grading progress can appear.',
          buttonLabel: 'Import roster',
          icon: Icons.file_upload_rounded,
          color: AppColors.brandGreenDark,
          onTap: _handleImport,
          isPrimary: true,
        ),
      );
    }

    if (stats.students > 0 && stats.subjects == 0) {
      actions.add(
        _HomePriorityAction(
          tag: 'Required next step',
          title: 'Create an answer key before scanning',
          subtitle:
              'Add a subject, assign sections, and keep the correct answers ready for review.',
          buttonLabel: 'Create answer key',
          icon: Icons.edit_note_rounded,
          color: AppColors.brandGreenDark,
          onTap: _createNewSubject,
          isPrimary: actions.isEmpty,
        ),
      );
    }

    if (flaggedScans > 0) {
      actions.add(
        _HomePriorityAction(
          tag: 'Needs review',
          title:
              '$flaggedScans scan${flaggedScans == 1 ? '' : 's'} need a manual check',
          subtitle:
              'Low-confidence or flagged scans are waiting in the review queue before final results are shared.',
          buttonLabel: 'Open review queue',
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFD97706),
          onTap: _showReviewQueueSheet,
          isPrimary: actions.isEmpty,
        ),
      );
    }

    final inProgressSections = sections
        .where(
          (section) =>
              section.scannedStudents > 0 &&
              section.scannedStudents < section.totalStudents,
        )
        .toList()
      ..sort((a, b) => b.pending.compareTo(a.pending));
    if (inProgressSections.isNotEmpty) {
      final section = inProgressSections.first;
      actions.add(
        _HomePriorityAction(
          tag: 'Continue',
          title: 'Finish ${section.name}',
          subtitle:
              '${section.pending} sheet${section.pending == 1 ? '' : 's'} are still waiting, with ${section.scannedStudents} already graded.',
          buttonLabel: 'Open class',
          icon: Icons.play_circle_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () => _navigateToSection(section.name),
          isPrimary: actions.isEmpty,
        ),
      );
    }

    final exportReadySections = sections.where((section) {
      if (section.scannedStudents == 0 || section.pending != 0) {
        return false;
      }

      final lastExport = globalExportRecords
          .where((record) => record.sectionName == section.name)
          .fold<DateTime?>(
            null,
            (prev, record) => prev == null || record.exportedAt.isAfter(prev)
                ? record.exportedAt
                : prev,
          );

      return lastExport == null ||
          DateTime.now().difference(lastExport).inDays > 7;
    }).toList();
    if (exportReadySections.isNotEmpty) {
      actions.add(
        _HomePriorityAction(
          tag: 'Share results',
          title: exportReadySections.length == 1
              ? '${exportReadySections.first.name} is ready to export'
              : '${exportReadySections.length} classes are ready to export',
          subtitle:
              'Results are complete and can be shared as CSV or PDF while everything is still fresh.',
          buttonLabel: 'Export results',
          icon: Icons.download_rounded,
          color: AppColors.brandGreen,
          onTap: _handleExport,
          isPrimary: actions.isEmpty,
        ),
      );
    }

    if (actions.isEmpty && stats.subjects > 0) {
      actions.add(
        _HomePriorityAction(
          tag: 'Ready to go',
          title: 'Start your next scan session',
          subtitle:
              'Your roster and answer keys are in place, so you can jump straight into scanning.',
          buttonLabel: 'Start scan',
          icon: Icons.qr_code_scanner_rounded,
          color: AppColors.brandGreen,
          onTap: _startScanning,
          isPrimary: true,
        ),
      );
      actions.add(
        _HomePriorityAction(
          tag: 'Prep materials',
          title: 'Print answer sheets for another class',
          subtitle:
              'Generate clean sheets before the next exam block or make spares for students.',
          buttonLabel: 'Print sheets',
          icon: Icons.print_rounded,
          color: const Color(0xFFB45309),
          onTap: _showBatchPrintModal,
        ),
      );
    }

    return actions.take(3).toList();
  }

  Widget _buildActionCenter(List<_HomePriorityAction> actions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760 ? 1 : 2;
        const spacing = 14.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map(
                (action) => SizedBox(
                  width: width,
                  child: _HomePriorityActionCard(action: action),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildHomeDualQuickActions() {
    final actions = <_CompactActionData>[
      _CompactActionData(
        label: 'Import Roster',
        subtitle: _isImporting ? 'Importing...' : 'Load students',
        icon: Icons.file_upload_rounded,
        color: AppColors.brandGreenDark,
        onTap: _handleImport,
        isBusy: _isImporting,
      ),
      _CompactActionData(
        label: 'Answer Keys',
        subtitle: 'Manage subjects',
        icon: Icons.edit_note_rounded,
        color: AppColors.brandGreenDark,
        onTap: _createNewSubject,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final cardWidth = (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: actions
              .map(
                (action) => SizedBox(
                  width: cardWidth,
                  child: _CompactActionTile(action: action),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildNeedsAttentionSection(List<_HomePriorityAction> actions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Needs attention',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.brandText,
            ),
          ),
        ),
        _buildActionCenter(actions),
      ],
    );
  }

  Widget _buildClassesPage(List<_SectionSnapshot> sections) {
    final filteredSections = _filteredClassSections(sections);
    final useGroups = _shouldGroupClassSections(filteredSections);
    final groupedSections = useGroups
        ? _groupedClassSections(filteredSections)
        : <String, List<_SectionSnapshot>>{};

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      children: [
        _buildTopBar(
          title: 'Classes',
          subtitle: sections.isEmpty
              ? 'Import students to unlock class tracking and grading progress.'
              : '${sections.length} ${sections.length == 1 ? 'class' : 'classes'} with ${globalStudentDatabase.length} students loaded.',
        ),
        const SizedBox(height: 20),
        _buildClassesOverviewStrip(sections),
        if (sections.isNotEmpty) ...[
          const SizedBox(height: 16),
          ClassesSearchBar(
            controller: _classesSearchController,
            searchQuery: _classesSearchQuery,
            onChanged: (value) => setState(() => _classesSearchQuery = value),
            onClear: () {
              _classesSearchController.clear();
              setState(() => _classesSearchQuery = '');
            },
          ),
          const SizedBox(height: 12),
          ClassesFilterChips(
            selectedIndex: _classesStatusFilter,
            onSelected: (index) => setState(() => _classesStatusFilter = index),
          ),
        ],
        const SizedBox(height: 18),
        if (sections.isEmpty)
          _buildEmptyClassesCard()
        else if (filteredSections.isEmpty)
          const ClassesNoMatchesCard()
        else if (useGroups)
          ...groupedSections.entries.expand((entry) {
            final groupKey = entry.key;
            final groupSections = entry.value;
            final isExpanded = !_collapsedClassGroups.contains(groupKey);

            return [
              ClassGroupHeader(
                groupKey: groupKey,
                count: groupSections.length,
                isExpanded: isExpanded,
                onToggle: () => _toggleClassGroup(groupKey),
              ),
              if (isExpanded)
                ...groupSections.map(_buildMinimalClassCard),
            ];
          })
        else
          ...filteredSections.map(_buildMinimalClassCard),
      ],
    );
  }

  Widget _buildClassesOverviewStrip(List<_SectionSnapshot> sections) {
    final active = sections.where((section) => section.pending > 0).length;
    final completed = sections
        .where((section) => section.pending == 0 && section.totalStudents > 0)
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Classes',
              value: '${sections.length}',
            ),
          ),
          Container(width: 1, height: 42, color: AppColors.brandBorder),
          Expanded(
            child: _MiniStat(
              label: 'Students',
              value: '${globalStudentDatabase.length}',
            ),
          ),
          Container(width: 1, height: 42, color: AppColors.brandBorder),
          Expanded(
            child: _MiniStat(
              label: 'Active',
              value: '$active',
            ),
          ),
          if (sections.isNotEmpty) ...[
            Container(width: 1, height: 42, color: AppColors.brandBorder),
            Expanded(
              child: _MiniStat(
                label: 'Ready',
                value: '$completed',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClassListCard(_SectionSnapshot section) {
    final isComplete = section.pending == 0 && section.totalStudents > 0;
    final hasStarted = section.scannedStudents > 0;
    final progressColor = isComplete
        ? AppColors.brandGreen
        : hasStarted
            ? const Color(0xFFF59E0B)
            : AppColors.brandGreenDark;
    final statusLabel = section.totalStudents == 0
        ? 'Needs roster'
        : isComplete
            ? 'Complete'
            : hasStarted
                ? 'In progress'
                : 'Not started';
    final statusColor = isComplete
        ? AppColors.brandGreen
        : hasStarted
            ? const Color(0xFFD97706)
            : AppColors.brandGreenDark;
    final statusBackground = isComplete
        ? AppColors.brandGreen.withValues(alpha: 0.12)
        : hasStarted
            ? const Color(0xFFFEF3C7)
            : AppColors.brandGreen.withValues(alpha: 0.12);
    final progressLabel = section.totalStudents == 0
        ? '0 students — import roster or assign an answer key'
        : '${(section.progress * 100).round()}% graded';
    final subjectLabel = section.totalSubjects == 0
        ? 'No subjects linked yet'
        : section.subjectProgressLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: isComplete ? AppColors.brandSurface : Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openSection(section.name),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isComplete
                    ? AppColors.brandGreen.withValues(alpha: 0.22)
                    : AppColors.brandBorder,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: progressColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        isComplete
                            ? Icons.check_circle_rounded
                            : Icons.groups_rounded,
                        color: progressColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${section.totalStudents} students - ${section.scannedStudents} graded',
                            style: const TextStyle(
                              color: AppColors.brandMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Manage class',
                      onSelected: (action) =>
                          _handleSectionMenuAction(section, action),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename section'),
                        ),
                        if (_sections.length > 1)
                          const PopupMenuItem(
                            value: 'merge',
                            child: Text('Merge into another section'),
                          ),
                        if (section.totalStudents == 0)
                          const PopupMenuItem(
                            value: 'delete_empty',
                            child: Text('Delete empty section'),
                          ),
                        if (section.totalStudents > 0)
                          const PopupMenuItem(
                            value: 'delete_class',
                            child: Text('Delete class'),
                          ),
                      ],
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: AppColors.brandMuted.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _ClassMetric(
                        label: 'Pending',
                        value: '${section.pending}',
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ClassMetric(
                        label: 'Subjects',
                        value: section.totalSubjects == 0
                            ? '0'
                            : '${section.scannedSubjects}/${section.totalSubjects}',
                        color: AppColors.brandGreenDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: section.progress,
                    minHeight: 8,
                    backgroundColor: AppColors.brandSurface,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      progressLabel,
                      style: TextStyle(
                        color: progressColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        subjectLabel,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brandMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.brandMuted.withValues(alpha: 0.7),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReviewQueueSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _ReviewQueueSheet(
          scrollController: scrollController,
          onReviewComplete: () {
            unawaited(_loadDashboardData());
          },
          onRescan: _openRescanFromReview,
        ),
      ),
    );
  }

  /// Opens the scanner for the same subject as a flagged scan (from review queue).
  Future<void> _openRescanFromReview(ScanResult scan) async {
    if (!mounted) return;
    Navigator.of(context).pop();

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    Subject? subject;
    for (final s in globalSubjects) {
      if (s.id == scan.subjectId) {
        subject = s;
        break;
      }
    }
    if (subject == null) {
      _showSnackBar(
        'Could not find that subject. Try scanning from the subject list.',
        backgroundColor: Colors.red,
      );
      return;
    }
    final targetSubject = subject;

    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          _showSnackBar(
            'No camera available on this device.',
            backgroundColor: Colors.red,
          );
        }
        return;
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => ScannerPage(
            availableCameras: cams,
            targetSubject: targetSubject,
          ),
        ),
      );
      if (mounted) {
        await _loadDashboardData();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          UserErrorMessages.friendlyError(e),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Widget _buildSetupChecklist() {
    final hasStudents = globalStudentDatabase.isNotEmpty;
    final hasSubjects = globalSubjects.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Complete setup',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.brandText,
            ),
          ),
          const SizedBox(height: 10),
          _setupBullet(
            done: hasStudents,
            label: 'Import your student roster',
          ),
          _setupBullet(
            done: hasSubjects,
            label: 'Create an answer key',
          ),
          _setupBullet(
            done: globalScanResults.isNotEmpty,
            label: 'Scan your first answer sheet',
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: hasStudents ? _createNewSubject : _handleImport,
            child: const Text('Complete setup'),
          ),
        ],
      ),
    );
  }

  Widget _setupBullet({required bool done, required String label}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18,
            color: done ? AppColors.brandGreen : AppColors.brandMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done ? AppColors.brandMuted : AppColors.brandText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildContinueCard(List<_SectionSnapshot> sections) {
    // Find section user was working on (has some but not all graded)
    final inProgress = sections
        .where(
            (s) => s.scannedStudents > 0 && s.scannedStudents < s.totalStudents)
        .toList();

    if (inProgress.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sort by most recently active (most scanned)
    inProgress.sort((a, b) => b.scannedStudents.compareTo(a.scannedStudents));
    final section = inProgress.first;

    return Column(
      children: [
        Material(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _navigateToSection(section.name),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.play_circle_rounded,
                      color: Color(0xFFD97706),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Continue Grading',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${section.name} · ${section.pending} sheets remaining',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildItemAnalysisCard({int? limit}) {
    // Class comparison - which sections are performing better
    final sectionStats = _calculateSectionStats();

    if (sectionStats.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sort by average score (descending)
    final ranked = sectionStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final visibleRanked =
        limit == null ? ranked : ranked.take(limit).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.leaderboard_rounded,
                  size: 20, color: Color(0xFF8B5CF6)),
              SizedBox(width: 8),
              Text(
                'Class Performance',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Ranked by average score',
            style: TextStyle(fontSize: 12, color: AppColors.brandMuted),
          ),
          const SizedBox(height: 16),
          ...visibleRanked.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final sectionName = entry.value.key;
            final avgScore = entry.value.value;
            final isTop = rank == 1;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: isTop
                    ? AppColors.brandGreen.withValues(alpha: 0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _navigateToSection(sectionName),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color:
                                isTop ? const Color(0xFFFEF3C7) : AppColors.brandSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color:
                                  isTop ? const Color(0xFFD97706) : AppColors.brandMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            sectionName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brandText,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _getScoreColor(avgScore.round())
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${avgScore.round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _getScoreColor(avgScore.round()),
                            ),
                          ),
                        ),
                        if (isTop) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.emoji_events_rounded,
                              size: 18, color: Color(0xFFD97706)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Map<String, double> _calculateSectionStats() {
    final sectionScores = <String, List<double>>{};

    for (final scan in globalScanResults) {
      // Find the student to get their section
      final student = findStudentByOmrId(scan.studentOmrId);
      if (student == null || student.section.isEmpty) continue;

      final percentage = scan.totalQuestions > 0
          ? (scan.score / scan.totalQuestions) * 100
          : 0.0;

      sectionScores.putIfAbsent(student.section, () => []);
      sectionScores[student.section]!.add(percentage);
    }

    // Calculate averages
    final stats = <String, double>{};
    for (final entry in sectionScores.entries) {
      if (entry.value.isNotEmpty) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        stats[entry.key] = avg;
      }
    }

    return stats;
  }

  // ignore: unused_element
  Widget _buildRecentScansCard({int limit = 5}) {
    // Get last 5 scans
    final recentScans = globalScanResults.toList()
      ..sort((a, b) => b.scanTime.compareTo(a.scanTime));
    final visibleScans = recentScans.take(limit).toList();

    if (visibleScans.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, size: 20, color: AppColors.brandMuted),
              SizedBox(width: 8),
              Text(
                'Recent Scans',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Review for accuracy',
            style: TextStyle(fontSize: 12, color: AppColors.brandMuted),
          ),
          const SizedBox(height: 16),
          ...visibleScans.map((scan) {
            final student = findStudentByOmrId(scan.studentOmrId);
            final percentage = scan.totalQuestions > 0
                ? (scan.score / scan.totalQuestions * 100).round()
                : 0;
            final timeAgo = _formatTimeAgo(scan.scanTime);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getScoreColor(percentage).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$percentage%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _getScoreColor(percentage),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student?.name ?? 'OMR ${scan.studentOmrId}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${scan.scoreDisplay}/${scan.totalQuestions} · $timeAgo',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.brandMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    percentage >= 70
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _getScoreColor(percentage),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.month}/${timestamp.day}';
  }

  Color _getScoreColor(int percentage) {
    if (percentage >= 90) return const Color(0xFF16A34A);
    if (percentage >= 80) return const Color(0xFF2DD4BF);
    if (percentage >= 70) return const Color(0xFFF59E0B);
    if (percentage >= 60) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  void _navigateToSection(String sectionName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SectionDetailPage(sectionName: sectionName),
      ),
    ).then((_) async {
      if (mounted) {
        await _loadDashboardData();
      }
    });
  }

  Widget _buildSectionsTab(List<_SectionSnapshot> sections) {
    return _buildClassesPage(sections);
  }

  Widget _buildEmptyClassesCard() {
    return AppCard(
      child: Column(
        children: [
          const AppEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No classes yet',
            message:
                'Import a roster or create a section manually to begin.',
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 360;
              final importButton = ElevatedButton.icon(
                onPressed: _handleImport,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: const Text('Import Students'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              final sectionButton = OutlinedButton.icon(
                onPressed: _createNewSection,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Section'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    importButton,
                    const SizedBox(height: 10),
                    sectionButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: importButton),
                  const SizedBox(width: 10),
                  Expanded(child: sectionButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalClassCard(_SectionSnapshot section) {
    return _buildClassListCard(section);
  }

  Widget _buildToolsTab(_DashboardStats stats) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _buildTopBar(
          title: 'Tools',
          subtitle: 'Set up answer keys, sheets, and rosters before scanning.',
        ),
        const SizedBox(height: 20),
        _buildToolsSection('Exam setup', _examSetupToolActions),
        const SizedBox(height: 20),
        _buildToolsSection('Roster & results', _dataToolActions),
      ],
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title, style: AppTextStyles.sectionLabel),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.brandBorder),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildToolsSection(String title, List<_DashboardAction> actions) {
    return DashboardToolSection(
      title: title,
      children: actions
          .map(
            (action) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ToolTile(
                action: action,
                isBusy: action.label == 'Import Roster' && _isImporting,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSettingsTab(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _buildTopBar(
          title: 'Settings',
          subtitle: 'Workspace overview, cloud sync, backup, and account.',
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: 'Workspace',
          child: Column(
            children: [
              const _SettingsRow(
                icon: Icons.school_rounded,
                label: 'Workspace',
                value: 'PHINMA COC',
              ),
              const Divider(height: 24),
              _SettingsRow(
                icon: Icons.key_rounded,
                label: 'Answer Keys',
                value: '${stats.subjects}',
              ),
              const Divider(height: 24),
              _SettingsRow(
                icon: Icons.groups_rounded,
                label: 'Students',
                value: '${stats.students}',
              ),
              const Divider(height: 24),
              _SettingsRow(
                icon: Icons.grid_view_rounded,
                label: 'Sections',
                value: '${sections.length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: 'Cloud sync',
          child: Column(
            children: [
              _SettingsRow(
                icon: Icons.cloud_sync_rounded,
                label: 'Pending upload',
                value: _isSyncing ? 'Syncing...' : '$_pendingSyncCount',
              ),
              const Divider(height: 24),
              _SettingsRow(
                icon: Icons.history_rounded,
                label: 'Last sync',
                value: _formatLastSync(_lastSyncAt),
              ),
              const Divider(height: 24),
              _SettingsRow(
                icon: Icons.download_done_rounded,
                label: 'Last upload batch',
                value: _lastSyncSummary == null
                    ? 'None yet'
                    : '${_lastSyncSummary!.total} item${_lastSyncSummary!.total == 1 ? '' : 's'}',
              ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.wifi_rounded, color: AppColors.brandGreen),
                title: const Text(
                  'Auto-sync on Wi-Fi',
                  style: TextStyle(
                    color: AppColors.brandText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: const Text(
                  'Upload pending scores automatically when Wi-Fi is available.',
                  style: TextStyle(color: AppColors.brandMuted, fontSize: 12, height: 1.3),
                ),
                activeThumbColor: AppColors.brandGreen,
                value: _autoSyncOnWifi,
                onChanged: (value) async {
                  setState(() => _autoSyncOnWifi = value);
                  await SyncPreferencesService.setAutoSyncOnWifi(value);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSyncing ? null : _handleSyncNow,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(_isSyncing ? 'Syncing' : 'Sync Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandGreen,
                    disabledBackgroundColor: AppColors.brandGreen.withValues(alpha: 0.65),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              if (!SupabaseService.hasActiveSession &&
                  _pendingSyncCount > 0 &&
                  SupabaseService.isReady) ...[
                const SizedBox(height: 12),
                const Text(
                  'You are signed out. Sign in online to upload pending changes to the cloud.',
                  style: TextStyle(color: Colors.orange, fontSize: 13, height: 1.35),
                ),
              ],
              if (!SupabaseService.isReady) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cloud sync needs Supabase credentials. Scanning still works offline.',
                  style: TextStyle(color: AppColors.brandMuted, fontSize: 13, height: 1.35),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: 'Backup & restore',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export or restore a JSON backup when cloud sync is unavailable. Scan images stay on this device only.',
                style: TextStyle(color: AppColors.brandMuted, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleExportBackup,
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('Export JSON Backup'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandGreen,
                    side: const BorderSide(color: AppColors.brandGreen),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleRestoreBackup,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Restore JSON Backup'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandText,
                    side: const BorderSide(color: AppColors.brandBorder),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSettingsSection(
          title: 'Account',
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _handleSignOut();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandGreen,
                side: const BorderSide(color: AppColors.brandGreen),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar({
    required String title,
    required String subtitle,
  }) {
    return DashboardTopBar(
      title: title,
      subtitle: subtitle,
      onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
    );
  }

  Widget _buildSectionSpotlightCard(
    _SectionSnapshot section, {
    bool compact = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openSection(section.name),
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.brandBorder),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 40 : 46,
                height: compact ? 40 : 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.brandGreenDark, AppColors.brandGreen],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(compact ? 13 : 15),
                ),
                child: Icon(
                  Icons.class_rounded,
                  color: Colors.white,
                  size: compact ? 20 : 22,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            section.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          section.pending == 0
                              ? 'Done'
                              : '${section.pending} left',
                          style: TextStyle(
                            color:
                                section.pending == 0 ? AppColors.brandGreen : AppColors.brandMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${section.scannedStudents}/${section.totalStudents} students graded',
                      style: const TextStyle(
                        color: AppColors.brandMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: compact ? 5 : 6,
                        value: section.progress,
                        backgroundColor: const Color(0xFFEAF3ED),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AppColors.brandGreen),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.brandMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardStats {
  const _DashboardStats({
    required this.students,
    required this.scans,
    required this.scannedStudents,
    required this.pending,
    required this.subjects,
  });

  final int students;
  final int scans;
  final int scannedStudents;
  final int pending;
  final int subjects;

  double get progress => students == 0 ? 0 : scannedStudents / students;
}

class _SectionSnapshot {
  const _SectionSnapshot({
    required this.name,
    required this.totalStudents,
    required this.scannedStudents,
    required this.totalSubjects,
    required this.scannedSubjects,
  });

  final String name;
  final int totalStudents;
  final int scannedStudents;
  final int totalSubjects;
  final int scannedSubjects;

  int get pending =>
      totalStudents > scannedStudents ? totalStudents - scannedStudents : 0;

  double get progress =>
      totalStudents == 0 ? 0 : scannedStudents / totalStudents;

  double get subjectProgress =>
      totalSubjects == 0 ? 0 : scannedSubjects / totalSubjects;

  String get subjectProgressLabel =>
      '$scannedSubjects/$totalSubjects subjects scanned';
}

class _DashboardAction {
  const _DashboardAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;
}

class _DashboardDrawer extends StatelessWidget {
  const _DashboardDrawer({
    required this.selectedIndex,
    required this.onSelectTab,
    required this.onSignOut,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.brandGreenDark,
                    AppColors.brandGreen,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const CocSealLogo(size: 56),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COC OMR Hub',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Core dashboard shell',
                          style: TextStyle(
                            color: Color(0xFFE8F8EC),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Use the bottom bar to switch tabs. This menu is for account actions.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _DrawerTile(
              icon: Icons.settings_rounded,
              label: 'Open Settings',
              selected: selectedIndex == 3,
              onTap: () => onSelectTab(3),
            ),
            const Spacer(),
            const Divider(height: 1),
            _DrawerTile(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              selected: false,
              onTap: onSignOut,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        selected: selected,
        selectedTileColor: AppColors.brandGreen.withValues(
          alpha: 0.08,
        ),
        leading: Icon(
          icon,
          color: selected
              ? AppColors.brandGreen
              : AppColors.brandMuted,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected
                ? AppColors.brandGreen
                : AppColors.brandText,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.action,
    required this.isBusy,
  });

  final _DashboardAction action;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          action.onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.brandBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: isBusy
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: LoadingIndicators.primary(color: action.color),
                      )
                    : Icon(action.icon, color: action.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.subtitle,
                      style: const TextStyle(
                        color: AppColors.brandMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppColors.brandMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.brandText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.brandMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.brandGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: AppColors.brandGreen),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.brandText,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.brandGreen,
          ),
        ),
      ],
    );
  }
}

class _SubjectGroup {
  const _SubjectGroup({
    required this.name,
    required this.subjects,
  });

  final String name;
  final List<Subject> subjects;
}

class _SectionChoice {
  const _SectionChoice({
    required this.subject,
    required this.sectionName,
  });

  final Subject subject;
  final String sectionName;
}

class _AnswerKeyRow {
  const _AnswerKeyRow({
    required this.subject,
    this.sectionName,
  });

  final Subject subject;
  final String? sectionName;
}

class _CompactActionData {
  const _CompactActionData({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isBusy = false,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isBusy;
}

class _CompactActionTile extends StatelessWidget {
  const _CompactActionTile({required this.action});

  final _CompactActionData action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: action.isBusy ? null : action.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.brandBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: action.isBusy
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: LoadingIndicators.primary(color: action.color),
                      )
                    : Icon(
                        action.icon,
                        color: action.color,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.brandMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: action.color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  filled ? Colors.white : Colors.white.withValues(alpha: 0.26),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color:
                    filled ? AppColors.brandGreenDark : Colors.white,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: filled
                        ? AppColors.brandGreenDark
                        : Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePriorityAction {
  const _HomePriorityAction({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  final String tag;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;
}

class _HomePriorityActionCard extends StatelessWidget {
  const _HomePriorityActionCard({required this.action});

  final _HomePriorityAction action;

  @override
  Widget build(BuildContext context) {
    final foreground =
        action.isPrimary ? Colors.white : AppColors.brandText;
    final mutedForeground = action.isPrimary
        ? const Color(0xFFE7FFF4)
        : AppColors.brandMuted;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: action.onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: action.isPrimary
                ? LinearGradient(
                    colors: [
                      action.color,
                      AppColors.brandGreenDark,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: action.isPrimary ? null : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: action.isPrimary
                  ? Colors.transparent
                  : AppColors.brandBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: action.isPrimary
                    ? action.color.withValues(alpha: 0.18)
                    : const Color(0x0F0F172A),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: action.isPrimary
                          ? Colors.white.withValues(alpha: 0.16)
                          : action.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      action.tag,
                      style: TextStyle(
                        color: action.isPrimary ? Colors.white : action.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: action.isPrimary
                          ? Colors.white.withValues(alpha: 0.16)
                          : action.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      action.icon,
                      color: action.isPrimary ? Colors.white : action.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                action.title,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                action.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: mutedForeground,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: action.isPrimary
                      ? Colors.white
                      : action.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.buttonLabel,
                      style: TextStyle(
                        color: action.isPrimary
                            ? AppColors.brandGreenDark
                            : action.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: action.isPrimary
                          ? AppColors.brandGreenDark
                          : action.color,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivitySummaryTile extends StatelessWidget {
  const _ActivitySummaryTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.brandBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandText,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.brandMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardStatusBanner extends StatelessWidget {
  const _DashboardStatusBanner({
    required this.message,
    required this.onRetry,
    this.isRetrying = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isRetrying ? null : onRetry,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.brandText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isRetrying)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityScanRow extends StatelessWidget {
  const _ActivityScanRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.valueColor,
  });

  final String title;
  final String subtitle;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.brandBorder),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: valueColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
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
}

class _ImportStatLine extends StatelessWidget {
  const _ImportStatLine({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Color color;
  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.brandText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassMetric extends StatelessWidget {
  const _ClassMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.brandMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Review queue sheet for flagged scans
class _ReviewQueueSheet extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onReviewComplete;
  final Future<void> Function(ScanResult scan) onRescan;

  const _ReviewQueueSheet({
    required this.scrollController,
    required this.onReviewComplete,
    required this.onRescan,
  });

  @override
  State<_ReviewQueueSheet> createState() => _ReviewQueueSheetState();
}

class _ReviewQueueSheetState extends State<_ReviewQueueSheet> {
  @override
  Widget build(BuildContext context) {
    final flaggedScans = globalScanResults
        .where((s) => s.requiresReview)
        .toList()
      ..sort((a, b) => b.scanTime.compareTo(a.scanTime));

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.brandBorder,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Text(
                'Review Queue',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const Spacer(),
              if (flaggedScans.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Approve all without review?'),
                        content: Text(
                          'This marks all ${flaggedScans.length} flagged '
                          'scan${flaggedScans.length == 1 ? '' : 's'} as correct '
                          'without checking each one. Scores may be wrong.\n\n'
                          'Review individually when you can.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFD97706),
                            ),
                            onPressed: () =>
                                Navigator.pop(dialogContext, true),
                            child: const Text('Approve all anyway'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) {
                      return;
                    }
                    await LocalDataStore.instance.clearScanReviewFlags(
                      flaggedScans,
                    );
                    setState(() {});
                    widget.onReviewComplete();
                  },
                  child: const Text('Approve all'),
                ),
            ],
          ),
        ),
        Expanded(
          child: flaggedScans.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 48, color: AppColors.brandGreen),
                      SizedBox(height: 16),
                      Text('All clear!',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      SizedBox(height: 8),
                      Text('No scans need review',
                          style:
                              TextStyle(color: AppColors.brandMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: flaggedScans.length,
                  itemBuilder: (context, index) => _buildFlaggedScanItem(
                    flaggedScans[index],
                    onRescan: widget.onRescan,
                  ),
                ),
        ),
      ],
    );
  }

  void _showSnapshotPreview(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(File(path))),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlaggedScanItem(
    ScanResult scan, {
    required Future<void> Function(ScanResult scan) onRescan,
  }) {
    final student = findStudentByOmrId(scan.studentOmrId);
    final confidencePercent = (scan.confidence * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.brandBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scan.isLowConfidence
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    scan.studentOmrId,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scan.isLowConfidence
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFD97706),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student?.name ?? 'Unknown Student',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scan.subjectName,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.brandMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${scan.scoreDisplay}/${scan.totalQuestions}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          scan.isLowConfidence
                              ? Icons.warning_rounded
                              : Icons.flag_rounded,
                          size: 14,
                          color: scan.isLowConfidence
                              ? const Color(0xFFDC2626)
                              : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          scan.isLowConfidence
                              ? '$confidencePercent%'
                              : 'Flagged',
                          style: TextStyle(
                            fontSize: 12,
                            color: scan.isLowConfidence
                                ? const Color(0xFFDC2626)
                                : const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (scan.reviewReasons.isNotEmpty || scan.flaggedQuestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (scan.reviewReasons.isNotEmpty)
                      ...scan.reviewReasons.map(
                        (reason) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ',
                                  style: TextStyle(color: Color(0xFF92400E))),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (scan.flaggedQuestions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Check question${scan.flaggedQuestions.length == 1 ? '' : 's'}: '
                          '${(scan.flaggedQuestions.toList()..sort()).join(', ')}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (scan.scannedImagePath != null &&
                scan.scannedImagePath!.isNotEmpty &&
                File(scan.scannedImagePath!).existsSync()) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _showSnapshotPreview(context, scan.scannedImagePath!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Image.file(
                        File(scan.scannedImagePath!),
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      const Positioned(
                        right: 8,
                        bottom: 8,
                        child: Icon(
                          Icons.zoom_out_map_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await onRescan(scan);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandGreen,
                      side: const BorderSide(
                          color: AppColors.brandGreen),
                    ),
                    child: const Text('Rescan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await LocalDataStore.instance.setScanReviewStatus(
                        result: scan,
                        needsReview: false,
                      );
                      setState(() {});
                      widget.onReviewComplete();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
