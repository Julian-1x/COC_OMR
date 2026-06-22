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
import 'package:omr_app/pages/welcome_onboarding_page.dart';
import 'package:flutter/services.dart';
import 'package:omr_app/services/app_update_service.dart';
import 'package:omr_app/services/cloud_auth_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:omr_app/services/backup_service.dart';
import 'package:omr_app/services/export_service.dart';
import 'package:omr_app/services/import_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/local_auth_service.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:omr_app/services/supabase_sync_service.dart';
import 'package:omr_app/services/sync_preferences_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_page_transitions.dart';
import 'package:omr_app/theme/app_shadows.dart';
import 'package:omr_app/widgets/app_card.dart';
import 'package:omr_app/widgets/app_empty_state.dart';
import 'package:omr_app/widgets/dashboard/classes_search_filters.dart';
import 'package:omr_app/widgets/dashboard/teacher_hub_drawer.dart';
import 'package:omr_app/widgets/dashboard/dashboard_top_bar.dart';
import 'package:omr_app/widgets/dashboard/home_status_panel.dart';
import 'package:omr_app/widgets/dashboard/review_queue_card.dart';
import 'package:omr_app/widgets/pressable_scale.dart';
import 'package:omr_app/widgets/app_bottom_sheet.dart';
import 'package:omr_app/utils/section_program.dart';
import 'package:omr_app/utils/academic_term.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/loading_indicators.dart';
import 'package:omr_app/widgets/answer_key_delete_dialog.dart';
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
  String? _classesProgramFilter;
  final Set<String> _expandedSettingsSections = <String>{};
  final Set<String> _expandedPrepareSections = <String>{};

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
  String _teacherName = 'Teacher';
  String _teacherSchool = 'PHINMA COC';
  String? _teacherEmail;
  String _appVersion = '';
  bool _isOnline = true;

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
    unawaited(_loadTeacherHubMeta());
    _initConnectivityListener();
  }

  Future<void> _loadTeacherHubMeta() async {
    final profile = await LocalAuthService.instance.loadProfile();
    final packageInfo = await PackageInfo.fromPlatform();
    final email = SupabaseService.client?.auth.currentUser?.email;
    if (!mounted) {
      return;
    }
    setState(() {
      if (profile != null) {
        _teacherName = profile.name;
        _teacherSchool = profile.school;
        _teacherEmail = profile.email ?? email;
      } else if (email != null) {
        _teacherEmail = email;
      }
      _appVersion = packageInfo.version;
    });
  }

  int get _reviewScanCount =>
      globalScanResults.where((scan) => scan.requiresReview).length;

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
        backgroundColor: AppColors.warningAccent,
      );
      return;
    }

    final studentCount = globalStudentDatabase.length;
    final sectionCount = _sections.length;
    if (studentCount == 0) {
      _showSnackBar(
        'No saved students found yet. Import your roster under Prepare.',
        backgroundColor: AppColors.warningAccent,
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

  String _sectionGroupKey(String sectionName) =>
      SectionProgram.programKey(sectionName);

  List<String> _distinctProgramKeys(List<_SectionSnapshot> sections) {
    return SectionProgram.sortedProgramKeys(
      sections.map((section) => section.name),
    );
  }

  bool _sectionMatchesClassesProgram(_SectionSnapshot section) {
    final filter = _classesProgramFilter;
    if (filter == null) {
      return true;
    }
    return _sectionGroupKey(section.name) == filter;
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
              _sectionMatchesClassesProgram(section) &&
              _sectionMatchesClassesSearch(section) &&
              _sectionMatchesClassesStatus(section),
        )
        .toList();
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
          subtitle: 'View & export per section',
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
        backgroundColor: AppColors.warningAccent,
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
    _isOnline = !_wasOffline;

    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final isOnline = _hasNetworkConnection(results);
      if (mounted) {
        setState(() => _isOnline = isOnline);
      }
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
      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
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

    if (!mounted) {
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

  Future<SubjectDeletionSummary?> _performAnswerKeyDeletion({
    required Subject subject,
    String? sectionName,
  }) async {
    final choice = await showAnswerKeyDeleteDialog(
      context: context,
      subject: subject,
      sectionName: sectionName,
    );
    if (choice == AnswerKeyDeleteChoice.cancelled || !mounted) {
      return null;
    }

    if (choice == AnswerKeyDeleteChoice.sectionOnly) {
      if (sectionName == null) {
        return null;
      }
      return LocalDataStore.instance.deleteSubjectFromSection(
        subject: subject,
        sectionName: sectionName,
      );
    }

    return LocalDataStore.instance.deleteSubjectCascade(subject);
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
                      if (deletionSummary != null) {
                        _showSnackBar(
                          deletionSummary.removedFromSectionOnly
                              ? 'Removed $subjectName from ${deletionSummary.detachedSectionName}.'
                              : 'Deleted $subjectName. Removed ${deletionSummary.removedScans} scan${deletionSummary.removedScans == 1 ? '' : 's'}.',
                          backgroundColor: Colors.red,
                        );
                      } else {
                        _showSnackBar(
                          'Deleted $subjectName.',
                          backgroundColor: Colors.red,
                        );
                      }
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

            Future<void> deleteAnswerKeyRow({
              required Subject subject,
              String? sectionName,
            }) async {
              final summary = await _performAnswerKeyDeletion(
                subject: subject,
                sectionName: sectionName,
              );
              if (summary == null || !mounted) {
                return;
              }

              await _loadDashboardData();
              if (!mounted) {
                return;
              }
              setModalState(() {});
              _showSnackBar(
                answerKeyDeletionMessage(subject: subject, summary: summary),
                backgroundColor: Colors.red,
              );
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
                                                    sectionFilter: sectionName,
                                                  ),
                                                ),
                                              );
                                            } else if (value == 'delete') {
                                              deleteAnswerKeyRow(
                                                subject: row.subject,
                                                sectionName: sectionName,
                                              );
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
                                                    'Delete...',
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
    if (!mounted) {
      return;
    }
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

  void _openHowItWorksGuide() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => WelcomeOnboardingPage(
          reviewMode: true,
          onFinished: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _handleSyncNow() async {
    if (_isSyncing) {
      return;
    }
    if (!SupabaseService.hasActiveSession) {
      _showSnackBar(
        'Sign in online to sync your data to the cloud.',
        backgroundColor: AppColors.warningAccent,
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

  Future<void> _handleArchiveSectionEndOfTerm() async {
    await _refreshSyncStatus();
    if (!mounted) {
      return;
    }

    if (!SupabaseService.hasActiveSession) {
      _showSnackBar(
        'Sign in while online before archiving. Your scores must be in the cloud first.',
        backgroundColor: AppColors.warningAccent,
      );
      return;
    }

    if (_pendingSyncCount > 0) {
      final syncFirst = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sync before archiving'),
          content: Text(
            '$_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'} still waiting to upload. '
            'Sync now so archived scores are safe in the cloud.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
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
        await _refreshSyncStatus();
      }
      if (!mounted || _pendingSyncCount > 0) {
        return;
      }
    }

    final sections = _sections;
    if (sections.isEmpty) {
      _showSnackBar('No sections to archive.', backgroundColor: AppColors.warningAccent);
      return;
    }

    final picked = await showDialog<_SectionSnapshot>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Archive which section?'),
        children: sections
            .map(
              (section) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, section),
                child: Text(
                  '${section.name} · ${section.totalStudents} student${section.totalStudents == 1 ? '' : 's'}',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${picked.name}?'),
        content: const Text(
          'Scores and roster stay in the cloud and on the web portal.\n\n'
          'This section will be removed from this phone to save space. '
          'You can import a fresh roster next term.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final summary =
          await SupabaseSyncService.instance.archiveSectionEndOfTerm(picked.name);
      if (!mounted) {
        return;
      }
      await _loadDashboardData();
      _showSnackBar(
        'Archived ${picked.name}. Removed ${summary.removedStudents} student${summary.removedStudents == 1 ? '' : 's'} from this phone. View history on the web portal.',
        backgroundColor: AppColors.brandGreen,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
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
      success
          ? 'Backup file ready. Save it somewhere safe and private.'
          : 'Could not create backup. Please try again.',
      backgroundColor: success ? AppColors.brandGreen : Colors.red,
    );
  }

  Future<void> _handleRestoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load this backup file?'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will replace your answer keys, class lists, and grades on this device '
                'with the information from the file you pick.',
                style: TextStyle(height: 1.4),
              ),
              SizedBox(height: 14),
              Text(
                'Before you continue:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                '• Make sure you chose the correct backup file.',
                style: TextStyle(height: 1.4),
              ),
              Text(
                '• Your current work on this device will be replaced.',
                style: TextStyle(height: 1.4),
              ),
              Text(
                '• Other teachers who use this tablet will keep their own data.',
                style: TextStyle(height: 1.4),
              ),
              Text(
                '• Scanned paper photos are not in backup files—they stay on this device.',
                style: TextStyle(height: 1.4),
              ),
              SizedBox(height: 14),
              Text(
                'Only tap Load if you are sure this is the file you want.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Load backup'),
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
      restored
          ? 'Your data was loaded from the backup file.'
          : 'Backup load was cancelled or could not finish.',
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
                'Select the subject to scan. One photo reads the whole sheet — QR, student ID, and answers.',
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
                            backgroundColor: AppColors.warningAccent,
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
                          AppPageTransitions.fadeSlide(
                            ScannerPage(
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
    var selectedYear = AcademicTerm.schoolYearForDate();
    var selectedTerm = AcademicTerm.defaultTermLabel();
    final yearOptions = AcademicTerm.schoolYearOptions();

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Section'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _sectionController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'e.g. BSIT-1A',
                    labelText: 'Section name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'School year',
                    border: OutlineInputBorder(),
                  ),
                  items: yearOptions
                      .map(
                        (year) => DropdownMenuItem(
                          value: year,
                          child: Text(year),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => selectedYear = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedTerm,
                  decoration: const InputDecoration(
                    labelText: 'Term',
                    border: OutlineInputBorder(),
                  ),
                  items: AcademicTerm.commonTermLabels
                      .map(
                        (term) => DropdownMenuItem(
                          value: term,
                          child: Text(term),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => selectedTerm = value);
                  },
                ),
              ],
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
                    Section(
                      name: sectionName,
                      schoolYear: selectedYear,
                      termLabel: selectedTerm,
                    ),
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
        backgroundColor: AppColors.warningAccent,
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
        title: const Text('Delete empty section permanently?'),
        content: Text(
          'Remove $sectionName from this phone and the cloud.\n\n'
          'Use Settings → End of term → Archive if you only want to free phone space.',
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
        title: Text('Delete ${section.name} permanently?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete ${section.name} and all ${section.totalStudents} student${section.totalStudents == 1 ? '' : 's'} '
              'from this phone and the cloud.',
            ),
            const SizedBox(height: 12),
            const Text(
              'To keep scores online but remove from this phone, use Settings → End of term → Archive.',
              style: TextStyle(color: AppColors.brandMuted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Permanent delete cannot be undone. Export a backup first if unsure.',
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
      drawer: TeacherHubDrawer(
        teacherName: _teacherName,
        school: _teacherSchool,
        email: _teacherEmail,
        isOnline: _isOnline,
        hasCloudSession: SupabaseService.hasActiveSession,
        studentCount: stats.students,
        scannedCount: stats.scannedStudents,
        pendingCount: stats.pending,
        reviewCount: _reviewScanCount,
        pendingSyncCount: _pendingSyncCount,
        isSyncing: _isSyncing,
        appVersion: _appVersion.isEmpty ? '—' : _appVersion,
        onScan: () {
          Navigator.pop(context);
          _startScanning();
        },
        onReview: () {
          Navigator.pop(context);
          _showReviewQueueSheet();
        },
        onSync: () {
          Navigator.pop(context);
          unawaited(_handleSyncNow());
        },
        onHelp: () {
          Navigator.pop(context);
          _openHowItWorksGuide();
        },
        onSignOut: () {
          Navigator.pop(context);
          _handleSignOut();
        },
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _selectedIndex == 1
            ? FloatingActionButton.extended(
                key: const ValueKey('classes-fab'),
                onPressed: _createNewSection,
                backgroundColor: AppColors.brandGreen,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Section'),
              )
            : const SizedBox.shrink(key: ValueKey('no-fab')),
      ),
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
              icon: Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment_rounded),
              label: 'Prepare',
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
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final slide = Tween<Offset>(
                        begin: const Offset(0, 0.03),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
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
        return _buildPrepareTab(stats);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        children: [
          _buildHomeTopBar(stats, sections),
          const SizedBox(height: 14),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildHomeStatusPanel(stats, sections)),
                const SizedBox(height: 12),
                _buildHomeExamPrepCard(compact: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildHomeScanButton(),
        ],
      ),
    );
  }

  Widget _buildHomeTopBar(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    return DashboardTopBar(
      title: 'Dashboard',
      subtitle: 'Grading progress at a glance.',
      notificationCount: _homeNotificationCount(stats, sections),
      onNotificationTap: () => _showHomeNotificationsSheet(stats, sections),
      onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
    );
  }

  int _homeNotificationCount(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    var count = _buildHomeActionCenterItems(stats, sections).length;
    if (_pendingSyncCount > 0) {
      count++;
    }
    if (_updateInfo != null) {
      count++;
    }
    return count;
  }

  void _showHomeNotificationsSheet(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    final actions = _buildHomeActionCenterItems(stats, sections);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _homeNotificationCount(stats, sections) == 0
                    ? 'Nothing needs your attention right now.'
                    : 'Tap an item below to take action.',
                style: const TextStyle(
                  color: AppColors.brandMuted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              if (_updateInfo != null)
                _buildNotificationTile(
                  icon: Icons.system_update_rounded,
                  color: AppColors.brandGreen,
                  title: _updateInfo!.latestVersion == null
                      ? 'App update available'
                      : 'Update available: ${_updateInfo!.latestVersion}',
                  subtitle: _updateInfo!.notes?.trim().isNotEmpty == true
                      ? _updateInfo!.notes!.trim()
                      : 'Ask your admin for the latest APK.',
                  actionLabel: 'Dismiss',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _updateInfo = null);
                  },
                ),
              if (_pendingSyncCount > 0)
                _buildNotificationTile(
                  icon: Icons.cloud_upload_rounded,
                  color: AppColors.brandGreen,
                  title: '$_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'} waiting to sync',
                  subtitle: !SupabaseService.hasActiveSession
                      ? 'Sign in while online to upload your work.'
                      : 'Upload pending scores to the cloud.',
                  actionLabel: _isSyncing ? 'Syncing…' : 'Sync',
                  onTap: _isSyncing
                      ? null
                      : () {
                          Navigator.pop(context);
                          unawaited(_handleSyncNow());
                        },
                ),
              ...actions.map(
                (action) => _buildNotificationTile(
                  icon: action.icon,
                  color: action.color,
                  title: action.title,
                  subtitle: action.tag,
                  actionLabel: action.buttonLabel,
                  onTap: () {
                    Navigator.pop(context);
                    action.onTap();
                  },
                ),
              ),
              if (_homeNotificationCount(stats, sections) == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 40,
                        color: AppColors.brandMuted,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'You\'re all caught up.',
                        style: TextStyle(
                          color: AppColors.brandMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.brandText,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.brandMuted),
        ),
        trailing: TextButton(
          onPressed: onTap,
          child: Text(
            actionLabel,
            style: TextStyle(
              color: onTap == null ? AppColors.brandMuted : color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildHomeStatusPanel(
    _DashboardStats stats,
    List<_SectionSnapshot> sections,
  ) {
    final prioritySections = _prioritySectionsForHome(sections);
    final allComplete = sections.isNotEmpty &&
        sections.every(
          (section) => section.pending == 0 && section.totalStudents > 0,
        );
    final actions = _buildHomeActionCenterItems(stats, sections);
    HomeStatusNextAction? nextAction;
    if (actions.isNotEmpty) {
      final action = actions.first;
      nextAction = HomeStatusNextAction(
        message: action.title,
        icon: action.icon,
        onTap: action.onTap,
      );
    }

    return HomeStatusPanel(
      totalStudents: stats.students,
      scannedStudents: stats.scannedStudents,
      pending: stats.pending,
      progress: stats.progress,
      sections: prioritySections.map(_homeStatusSectionRow).toList(),
      allClassesComplete: allComplete,
      onSectionTap: _openSection,
      nextAction: nextAction,
    );
  }

  List<_SectionSnapshot> _prioritySectionsForHome(
    List<_SectionSnapshot> sections,
  ) {
    final inProgress = sections
        .where((section) => section.scannedStudents > 0 && section.pending > 0)
        .toList()
      ..sort((a, b) => b.pending.compareTo(a.pending));
    final notStarted = sections
        .where(
          (section) =>
              section.scannedStudents == 0 && section.totalStudents > 0,
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final picked = <_SectionSnapshot>[...inProgress, ...notStarted];
    if (picked.length >= 3) {
      return picked.take(3).toList();
    }

    final complete = sections
        .where(
          (section) => section.pending == 0 && section.totalStudents > 0,
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    picked.addAll(complete);
    return picked.take(3).toList();
  }

  HomeStatusSectionRow _homeStatusSectionRow(_SectionSnapshot section) {
    final isComplete = section.pending == 0 && section.totalStudents > 0;
    final hasStarted = section.scannedStudents > 0;
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

    return HomeStatusSectionRow(
      name: section.name,
      pending: section.pending,
      totalStudents: section.totalStudents,
      scannedStudents: section.scannedStudents,
      statusLabel: statusLabel,
      statusColor: statusColor,
      statusBackground: statusBackground,
    );
  }

  Widget _buildHomeScanButton() {
    return PressableScale(
      onTap: _startScanning,
      child: Material(
        color: AppColors.brandGreen,
        borderRadius: BorderRadius.circular(22),
        elevation: 2,
        shadowColor: AppColors.brandGreenDark.withValues(alpha: 0.35),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 26,
              ),
              SizedBox(width: 10),
              Text(
                'Tap to scan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeExamPrepCard({bool compact = false}) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, compact ? 14 : 16, 16, compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.brandBorder),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Exam prep',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.brandText,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            const Text(
              'Set up rosters, keys, and printable sheets before scanning.',
              style: TextStyle(
                color: AppColors.brandMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          SizedBox(height: compact ? 12 : 14),
          Row(
            children: [
              Expanded(
                child: _HomePrepButton(
                  icon: Icons.file_upload_rounded,
                  label: 'Import',
                  color: AppColors.brandGreenDark,
                  isBusy: _isImporting,
                  onTap: _handleImport,
                  compact: compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomePrepButton(
                  icon: Icons.edit_note_rounded,
                  label: 'Keys',
                  color: AppColors.brandGreenDark,
                  onTap: _createNewSubject,
                  compact: compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HomePrepButton(
                  icon: Icons.print_rounded,
                  label: 'Print',
                  color: const Color(0xFFB45309),
                  onTap: _showBatchPrintModal,
                  compact: compact,
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

    if (flaggedScans > 0) {
      actions.add(
        _HomePriorityAction(
          tag: 'Needs review',
          title:
              '$flaggedScans scan${flaggedScans == 1 ? '' : 's'} need a manual check',
          subtitle: '',
          buttonLabel: 'Review',
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
          title:
              '${section.name}: ${section.pending} sheet${section.pending == 1 ? '' : 's'} left',
          subtitle: '',
          buttonLabel: 'Open',
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
              : '${exportReadySections.length} classes ready to export',
          subtitle: '',
          buttonLabel: 'Export',
          icon: Icons.download_rounded,
          color: AppColors.brandGreen,
          onTap: _handleExport,
          isPrimary: actions.isEmpty,
        ),
      );
    }

    return actions.take(2).toList();
  }

  Widget _buildClassesPage(List<_SectionSnapshot> sections) {
    final programKeys = _distinctProgramKeys(sections);
    final filteredSections = _filteredClassSections(sections);
    final hasMixedPrograms = programKeys.length > 1;
    final inProgressCount = sections
        .where((section) => section.scannedStudents > 0 && section.pending > 0)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      children: [
        _buildTopBar(
          title: 'Classes',
          subtitle: sections.isEmpty
              ? 'Import students to unlock class tracking and grading progress.'
              : hasMixedPrograms
                  ? '${sections.length} classes across ${programKeys.length} programs · ${globalStudentDatabase.length} students · tap a class to open'
                  : '${sections.length} ${sections.length == 1 ? 'class' : 'classes'} · ${globalStudentDatabase.length} students · tap to open roster',
        ),
        if (sections.isNotEmpty && inProgressCount > 0 && _classesStatusFilter == 0) ...[
          const SizedBox(height: 14),
          _buildClassesInProgressHint(inProgressCount),
        ],
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
          if (hasMixedPrograms) ...[
            const SizedBox(height: 12),
            ClassesProgramFilterChips(
              programs: programKeys,
              selectedProgram: _classesProgramFilter,
              onSelected: (program) {
                setState(() {
                  _classesProgramFilter = program;
                });
              },
            ),
          ],
          const SizedBox(height: 12),
          ClassesFilterChips(
            selectedIndex: _classesStatusFilter,
            onSelected: (index) => setState(() => _classesStatusFilter = index),
          ),
        ],
        const SizedBox(height: 16),
        if (_isLoadingData && sections.isEmpty)
          const ClassesListSkeleton()
        else if (sections.isEmpty)
          _buildEmptyClassesCard()
        else if (filteredSections.isEmpty)
          const ClassesNoMatchesCard()
        else
          ...filteredSections.map(_buildCompactClassRow),
      ],
    );
  }

  Widget _buildClassesInProgressHint(int count) {
    return Material(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => setState(() => _classesStatusFilter = 1),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 20,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'class' : 'classes'} still grading — tap to show',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFD97706),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactClassRow(_SectionSnapshot section) {
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
    final detailLine = section.totalStudents == 0
        ? 'No students — import a roster'
        : section.totalSubjects == 0
            ? '${section.totalStudents} students · ${section.scannedStudents} graded'
            : '${section.totalStudents} students · ${section.scannedStudents} graded · ${section.subjectProgressLabel}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openSection(section.name),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.brandBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: progressColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isComplete
                            ? Icons.check_circle_rounded
                            : Icons.groups_rounded,
                        color: progressColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detailLine,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.brandMuted,
                              fontSize: 12,
                              height: 1.3,
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
                        color: statusBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
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
                            child: Text('Delete empty section permanently'),
                          ),
                        if (section.totalStudents > 0)
                          const PopupMenuItem(
                            value: 'delete_class',
                            child: Text('Delete class permanently'),
                          ),
                      ],
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: AppColors.brandMuted.withValues(alpha: 0.9),
                        size: 20,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.brandMuted.withValues(alpha: 0.7),
                      size: 22,
                    ),
                  ],
                ),
                if (section.totalStudents > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: section.progress,
                      minHeight: 4,
                      backgroundColor: AppColors.brandSurface,
                      valueColor: AlwaysStoppedAnimation<Color>(progressColor),
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
        AppPageTransitions.fadeSlide(
          ScannerPage(
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

  Widget _buildPrepareTab(_DashboardStats stats) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _buildTopBar(
          title: 'Prepare',
          subtitle: 'Set up answer keys, sheets, and rosters before scanning.',
        ),
        const SizedBox(height: 16),
        _buildCollapsibleSection(
          expandedSet: _expandedPrepareSections,
          sectionId: 'exam_setup',
          icon: Icons.edit_note_rounded,
          title: 'Exam setup',
          summary:
              '${globalSubjects.length} answer key${globalSubjects.length == 1 ? '' : 's'} · print sheets & OMR IDs',
          child: _buildPrepareActionList(_examSetupToolActions),
        ),
        _buildCollapsibleSection(
          expandedSet: _expandedPrepareSections,
          sectionId: 'roster_results',
          icon: Icons.groups_rounded,
          title: 'Roster & results',
          summary:
              '${stats.students} students · ${globalScanResults.length} scan${globalScanResults.length == 1 ? '' : 's'}',
          child: _buildPrepareActionList(_dataToolActions),
        ),
      ],
    );
  }

  Widget _buildPrepareActionList(List<_DashboardAction> actions) {
    return Column(
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

  Widget _buildCollapsibleSection({
    required Set<String> expandedSet,
    required String sectionId,
    required IconData icon,
    required String title,
    required String summary,
    required Widget child,
  }) {
    final expanded = expandedSet.contains(sectionId);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brandBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (expanded) {
                  expandedSet.remove(sectionId);
                } else {
                  expandedSet.add(sectionId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: AppColors.brandGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.brandText,
                          ),
                        ),
                        if (!expanded) ...[
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            style: const TextStyle(
                              color: AppColors.brandMuted,
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: AppColors.brandMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: child,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsibleSettingsSection({
    required String sectionId,
    required IconData icon,
    required String title,
    required String summary,
    required Widget child,
  }) {
    return _buildCollapsibleSection(
      expandedSet: _expandedSettingsSections,
      sectionId: sectionId,
      icon: icon,
      title: title,
      summary: summary,
      child: child,
    );
  }

  Widget _buildSettingsTipBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brandGreen.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            size: 20,
            color: AppColors.brandGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.brandText,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              color: AppColors.brandMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.brandMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSubheading(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.brandText,
        fontWeight: FontWeight.w800,
        fontSize: 14,
      ),
    );
  }

  String _cloudSyncSettingsSummary() {
    if (_isSyncing) {
      return 'Syncing now…';
    }
    if (_pendingSyncCount > 0) {
      return '$_pendingSyncCount item${_pendingSyncCount == 1 ? '' : 's'} waiting to upload';
    }
    if (_lastSyncAt != null) {
      return 'Up to date · Last sync ${_formatLastSync(_lastSyncAt)}';
    }
    return 'Tap to manage online backup';
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
          subtitle: 'Tap a section to open it.',
        ),
        const SizedBox(height: 16),
        _buildCollapsibleSettingsSection(
          sectionId: 'workspace',
          icon: Icons.school_rounded,
          title: 'Workspace',
          summary:
              'PHINMA COC · ${sections.length} section${sections.length == 1 ? '' : 's'} · ${stats.students} students',
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
        _buildCollapsibleSettingsSection(
          sectionId: 'help',
          icon: Icons.help_outline_rounded,
          title: 'Help',
          summary: 'Quick tour for new teachers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New to the app? Open the short guide to learn how scanning, answer keys, and class lists work together.',
                style: TextStyle(
                  color: AppColors.brandMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openHowItWorksGuide,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('Open how-it-works guide'),
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
            ],
          ),
        ),
        _buildCollapsibleSettingsSection(
          sectionId: 'cloud',
          icon: Icons.cloud_sync_rounded,
          title: 'Cloud sync',
          summary: _cloudSyncSettingsSummary(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsTipBox(
                'Cloud sync saves your grades online when you are signed in and connected. '
                'Use it on your usual phone or tablet so your work is backed up automatically.',
              ),
              const SizedBox(height: 16),
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
                  label: Text(_isSyncing ? 'Syncing…' : 'Sync now'),
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
                  'You are signed out. Sign in while online to upload your pending changes.',
                  style: TextStyle(color: Colors.orange, fontSize: 13, height: 1.35),
                ),
              ],
              if (!SupabaseService.isReady) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cloud sync is not set up on this build. Scanning and grading still work offline.',
                  style: TextStyle(color: AppColors.brandMuted, fontSize: 13, height: 1.35),
                ),
              ],
            ],
          ),
        ),
        _buildCollapsibleSettingsSection(
          sectionId: 'archive',
          icon: Icons.inventory_2_outlined,
          title: 'End of term',
          summary: 'Archive finished classes to free phone space',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsTipBox(
                'When a semester ends, archive a section here. Scores stay in the cloud and on the web portal. '
                'The section is removed from this phone only — sync first so nothing is lost.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSyncing ? null : _handleArchiveSectionEndOfTerm,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive a section'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandGreenDark,
                    side: const BorderSide(color: AppColors.brandGreen),
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
        _buildCollapsibleSettingsSection(
          sectionId: 'backup',
          icon: Icons.folder_special_rounded,
          title: 'Backup & restore',
          summary: 'Save or load a copy of your data',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsTipBox(
                'Think of a backup like photocopying your gradebook. You save a file to your phone '
                'or Google Drive so you can recover your work later.',
              ),
              const SizedBox(height: 18),
              _buildSettingsSubheading('Cloud sync vs backup file'),
              const SizedBox(height: 8),
              _buildSettingsBullet(
                'Cloud sync (above) updates online when you tap Sync now or when Wi‑Fi auto-sync runs.',
              ),
              _buildSettingsBullet(
                'A backup file is something you save and open yourself—helpful with no internet, a new phone, or extra safety.',
              ),
              const SizedBox(height: 18),
              _buildSettingsSubheading('How to save a backup'),
              const SizedBox(height: 8),
              _buildSettingsBullet('Tap Save backup file below.'),
              _buildSettingsBullet('Choose where to store it (Files, Drive, etc.).'),
              _buildSettingsBullet('Keep the file private—anyone with it can see your class data.'),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleExportBackup,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Save backup file'),
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
              const SizedBox(height: 22),
              _buildSettingsSubheading('How to load a backup'),
              const SizedBox(height: 8),
              _buildSettingsBullet('Only use this if you need to recover from a file you saved earlier.'),
              _buildSettingsBullet('It replaces your grades and keys on this device—not other teachers\' data.'),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Loading a backup replaces your current work on this device. '
                        'Double-check that you picked the right file.',
                        style: TextStyle(
                          color: AppColors.brandText,
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _handleRestoreBackup,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Load backup file'),
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
              const SizedBox(height: 12),
              const Text(
                'Scanned answer sheet photos are not included in backup files—they stay on this device only.',
                style: TextStyle(color: AppColors.brandMuted, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
        _buildCollapsibleSettingsSection(
          sectionId: 'account',
          icon: Icons.person_outline_rounded,
          title: 'Account',
          summary: SupabaseService.hasActiveSession
              ? 'Signed in · Tap to sign out'
              : 'Sign out of this device',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                SupabaseService.hasActiveSession
                    ? 'You are signed in. Sign out if you are done on this device or switching accounts.'
                    : 'You are using the app with your PIN on this device. Sign out to return to the login screen.',
                style: const TextStyle(
                  color: AppColors.brandMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
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
                  label: const Text('Sign out'),
                ),
              ),
            ],
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

class _HomePrepButton extends StatelessWidget {
  const _HomePrepButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isBusy = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isBusy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: isBusy ? null : onTap,
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
          child: Column(
            children: [
              if (isBusy)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: LoadingIndicators.primary(color: color),
                )
              else
                Icon(icon, color: color, size: compact ? 20 : 22),
              SizedBox(height: compact ? 6 : 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 12 : 13,
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
              ? const AppEmptyState(
                  icon: Icons.check_circle_rounded,
                  title: 'All clear!',
                  message: 'No scans need review right now.',
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

    return ReviewQueueCard(
      scan: scan,
      studentName: student?.name ?? 'Unknown Student',
      onRescan: () => onRescan(scan),
      onApprove: () async {
        await LocalDataStore.instance.setScanReviewStatus(
          result: scan,
          needsReview: false,
        );
        if (mounted) {
          setState(() {});
          widget.onReviewComplete();
        }
      },
      onPreviewImage: scan.scannedImagePath != null &&
              scan.scannedImagePath!.isNotEmpty
          ? () => _showSnapshotPreview(context, scan.scannedImagePath!)
          : null,
    );
  }
}
