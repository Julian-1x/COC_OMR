import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/pages/scanner_page.dart';
import 'package:omr_app/services/exam_day_absence_store.dart';
import 'package:omr_app/services/exam_day_board_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_page_transitions.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/theme/app_typography.dart';
import 'package:omr_app/utils/scanner_launch.dart';
import 'package:omr_app/utils/user_error_messages.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/widgets/loading_indicators.dart';

class ExamDayBoardPage extends StatefulWidget {
  const ExamDayBoardPage({
    super.key,
    required this.sectionName,
    required this.subject,
  });

  final String sectionName;
  final Subject subject;

  @override
  State<ExamDayBoardPage> createState() => _ExamDayBoardPageState();
}

enum _BoardFilter { all, missing, review, duplicate, done, absent }

class _ExamDayBoardPageState extends State<ExamDayBoardPage> {
  ExamDayBoardReport? _report;
  String? _error;
  bool _loading = true;
  _BoardFilter _filter = _BoardFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final students = await LocalDataStore.instance.fetchStudents();
      final scans = await LocalDataStore.instance.fetchScanResults(
        subjectId: widget.subject.id,
      );
      final absent = await ExamDayAbsenceStore.instance.load(
        subjectId: widget.subject.id,
        sectionName: widget.sectionName,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _report = ExamDayBoardService.build(
          subject: widget.subject,
          sectionName: widget.sectionName,
          students: students,
          scans: scans,
          absentOmrIds: absent,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = UserErrorMessages.friendlyError(error);
      });
    }
  }

  List<ExamDayBoardRow> _visibleRows(ExamDayBoardReport report) {
    final needle = _search.trim().toLowerCase();
    return report.rows.where((row) {
      switch (_filter) {
        case _BoardFilter.all:
          break;
        case _BoardFilter.missing:
          if (row.status != ExamDayStatus.missing) return false;
        case _BoardFilter.review:
          if (row.status != ExamDayStatus.needsReview) return false;
        case _BoardFilter.duplicate:
          if (row.status != ExamDayStatus.duplicate) return false;
        case _BoardFilter.done:
          if (row.status != ExamDayStatus.done) return false;
        case _BoardFilter.absent:
          if (row.status != ExamDayStatus.absent) return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      return row.displayName.toLowerCase().contains(needle) ||
          row.omrId.contains(needle);
    }).toList();
  }

  Future<void> _openScanner() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _toast('No camera available on this device.', isError: true);
        return;
      }
      if (!mounted) {
        return;
      }
      final engineReady = await prepareScannerEngineForExam(context);
      if (!engineReady || !mounted) {
        return;
      }
      await Navigator.push<void>(
        context,
        AppPageTransitions.fadeSlide(
          ScannerPage(
            availableCameras: cams,
            targetSubject: widget.subject,
          ),
        ),
      );
      if (mounted) {
        await _reload();
      }
    } catch (error) {
      _toast(UserErrorMessages.friendlyError(error), isError: true);
    }
  }

  Future<void> _setAbsent(ExamDayBoardRow row, bool absent) async {
    await ExamDayAbsenceStore.instance.setAbsent(
      subjectId: widget.subject.id,
      sectionName: widget.sectionName,
      omrId: row.omrId,
      absent: absent,
    );
    await _reload();
  }

  Future<void> _approve(ExamDayBoardRow row) async {
    final scan = row.latestScan;
    if (scan == null) {
      return;
    }
    await LocalDataStore.instance.setScanReviewStatus(
      result: scan,
      needsReview: false,
    );
    await _reload();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.brandGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: AppColors.appCanvas,
      appBar: AppBar(
        title: const Text('Exam-day board'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        backgroundColor: AppColors.brandGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scan sheets'),
      ),
      body: _loading && report == null
          ? Center(child: LoadingIndicators.primary(size: 32))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTypography.body,
                    ),
                  ),
                )
              : report == null
                  ? const SizedBox.shrink()
                  : _buildBoard(report),
    );
  }

  Widget _buildBoard(ExamDayBoardReport report) {
    final rows = _visibleRows(report);
    return Column(
      children: [
        _buildHeader(report),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search name or OMR ID',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip(_BoardFilter.all, 'All', report.rosterCount),
              _chip(_BoardFilter.missing, 'Missing', report.missingCount),
              _chip(_BoardFilter.review, 'Review', report.reviewCount),
              _chip(_BoardFilter.duplicate, 'Duplicate', report.duplicateCount),
              _chip(_BoardFilter.done, 'Done', report.doneCount),
              _chip(_BoardFilter.absent, 'Absent', report.absentCount),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.brandGreen,
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Text(
                      report.rosterCount == 0
                          ? 'No students in this section yet. Import the roster first.'
                          : 'No students in this filter.',
                      textAlign: TextAlign.center,
                      style: AppTypography.captionMuted,
                    ),
                  )
                else
                  ...rows.map(_buildRow),
                if (report.unmatchedScans.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Sheets not on this roster (${report.unmatchedCount})',
                    style: AppTypography.sectionTitle,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'These OMR IDs were scanned for this exam but do not match a student in this section.',
                    style: AppTypography.captionMuted,
                  ),
                  const SizedBox(height: 8),
                  ...report.unmatchedScans.map(_buildUnmatched),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ExamDayBoardReport report) {
    final ready = report.isReadyToClose;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subject.displayName, style: AppTypography.sectionTitle),
          const SizedBox(height: 2),
          Text(
            '${report.sectionName} · ${report.rosterCount} on roster',
            style: AppTypography.captionMuted,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statPill('${report.doneCount} done', AppColors.statusSuccessBg, AppColors.statusSuccess),
              _statPill('${report.missingCount} missing', AppColors.statusDangerBg, AppColors.statusDanger),
              _statPill('${report.reviewCount} review', AppColors.statusWarningBg, AppColors.statusWarning),
              _statPill('${report.duplicateCount} duplicate', AppColors.statusWarningBg, AppColors.warningText),
              if (report.absentCount > 0)
                _statPill('${report.absentCount} absent', AppColors.neutralFill, AppColors.brandMuted),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ready ? AppColors.statusSuccessBg : AppColors.statusWarningBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ready
                    ? AppColors.statusSuccessBorder
                    : AppColors.statusWarningBorder,
              ),
            ),
            child: Text(
              ready
                  ? 'Ready to close this exam. Every roster name is scanned, reviewed, or marked absent.'
                  : 'Do not post final grades yet. Finish missing papers, review flags, and duplicates first.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ready ? AppColors.statusSuccess : AppColors.warningText,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(_BoardFilter filter, String label, int count) {
    final selected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label $count'),
        selected: selected,
        selectedColor: AppColors.brandGreen.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.brandGreenDark : AppColors.brandText,
        ),
        onSelected: (_) => setState(() => _filter = filter),
      ),
    );
  }

  Widget _statPill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12),
      ),
    );
  }

  Widget _buildRow(ExamDayBoardRow row) {
    final colors = _statusColors(row.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => unawaited(_showRowActions(row)),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.$3),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.$1,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    row.omrId,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colors.$2,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.displayName, style: AppTypography.listTitle),
                      const SizedBox(height: 2),
                      Text(
                        _statusLabel(row.status),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: colors.$2,
                          fontSize: 12,
                        ),
                      ),
                      if (row.statusDetail != null) ...[
                        const SizedBox(height: 2),
                        Text(row.statusDetail!, style: AppTypography.captionMuted),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.brandMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnmatched(ScanResult scan) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.statusDangerBorder),
        ),
        child: Text(
          'OMR ${scan.studentOmrId} · scanned, not on this roster',
          style: AppTypography.listTitle,
        ),
      ),
    );
  }

  Future<void> _showRowActions(ExamDayBoardRow row) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(row.displayName, style: AppTypography.sectionTitle),
                const SizedBox(height: 4),
                Text(
                  'OMR ${row.omrId} · ${_statusLabel(row.status)}',
                  style: AppTypography.captionMuted,
                ),
                if (row.statusDetail != null) ...[
                  const SizedBox(height: 8),
                  Text(row.statusDetail!, style: AppTypography.body),
                ],
                const SizedBox(height: 16),
                if (row.status == ExamDayStatus.missing ||
                    row.status == ExamDayStatus.absent ||
                    row.status == ExamDayStatus.needsReview ||
                    row.status == ExamDayStatus.duplicate)
                  AppPrimaryButton(
                    label: 'Scan this paper',
                    icon: Icons.document_scanner_rounded,
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_openScanner());
                    },
                  ),
                if (row.status == ExamDayStatus.needsReview ||
                    row.status == ExamDayStatus.duplicate) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_approve(row));
                    },
                    child: const Text('Approve this scan'),
                  ),
                ],
                if (row.status == ExamDayStatus.missing) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_setAbsent(row, true));
                    },
                    child: const Text('Mark absent'),
                  ),
                ],
                if (row.status == ExamDayStatus.absent) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_setAbsent(row, false));
                    },
                    child: const Text('Clear absent — still looking for paper'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(ExamDayStatus status) {
    switch (status) {
      case ExamDayStatus.done:
        return 'Done';
      case ExamDayStatus.missing:
        return 'Not scanned';
      case ExamDayStatus.needsReview:
        return 'Needs review';
      case ExamDayStatus.duplicate:
        return 'Duplicate sheet';
      case ExamDayStatus.absent:
        return 'Absent';
    }
  }

  (Color, Color, Color) _statusColors(ExamDayStatus status) {
    switch (status) {
      case ExamDayStatus.done:
        return (
          AppColors.statusSuccessBg,
          AppColors.statusSuccess,
          AppColors.statusSuccessBorder,
        );
      case ExamDayStatus.missing:
        return (
          AppColors.statusDangerBg,
          AppColors.statusDanger,
          AppColors.statusDangerBorder,
        );
      case ExamDayStatus.needsReview:
      case ExamDayStatus.duplicate:
        return (
          AppColors.statusWarningBg,
          AppColors.statusWarning,
          AppColors.statusWarningBorder,
        );
      case ExamDayStatus.absent:
        return (
          AppColors.neutralFill,
          AppColors.brandMuted,
          AppColors.borderLight,
        );
    }
  }
}
