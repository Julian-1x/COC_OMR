import 'dart:io';

import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/scan_reassign_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_typography.dart';

/// Teacher flow: move a saved scan to the correct student when OMR bubbles
/// were wrong. Never silently replaces an existing score.
Future<bool> showReassignScanSheet(
  BuildContext context, {
  required ScanResult scan,
  String? preferSection,
}) async {
  final moved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (context) {
      return _ReassignScanSheet(
        scan: scan,
        preferSection: preferSection,
      );
    },
  );
  return moved == true;
}

class _ReassignScanSheet extends StatefulWidget {
  const _ReassignScanSheet({
    required this.scan,
    this.preferSection,
  });

  final ScanResult scan;
  final String? preferSection;

  @override
  State<_ReassignScanSheet> createState() => _ReassignScanSheetState();
}

class _ReassignScanSheetState extends State<_ReassignScanSheet> {
  final _query = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Student> get _candidates {
    final current = widget.scan.studentOmrId;
    final q = _query.text.trim().toLowerCase();
    final prefer = (widget.preferSection ?? '').trim().toUpperCase();

    var list = globalStudentDatabase
        .where((s) => s.omrId != current)
        .toList();

    if (prefer.isNotEmpty) {
      final sameSection = list
          .where((s) => s.section.trim().toUpperCase() == prefer)
          .toList();
      if (sameSection.isNotEmpty) {
        list = sameSection;
      }
    }

    if (q.isNotEmpty) {
      list = list
          .where(
            (s) =>
                s.name.toLowerCase().contains(q) ||
                s.omrId.contains(q) ||
                s.schoolId.toLowerCase().contains(q) ||
                s.section.toLowerCase().contains(q),
          )
          .toList();
    }

    list.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.omrId.compareTo(b.omrId);
    });
    return list;
  }

  Future<void> _onPick(Student target) async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final plan = ScanReassignService.plan(
      scan: widget.scan,
      targetOmrId: target.omrId,
      students: globalStudentDatabase,
      scans: globalScanResults,
    );

    try {
      switch (plan.status) {
        case ScanReassignStatus.sameStudent:
          setState(() {
            _error = 'That paper is already on this student.';
            _busy = false;
          });
          return;
        case ScanReassignStatus.targetNotFound:
          setState(() {
            _error = 'Student not found on your roster.';
            _busy = false;
          });
          return;
        case ScanReassignStatus.targetHasExistingScore:
          setState(() => _busy = false);
          final replace = await _confirmConflict(
            target: target,
            existing: plan.existingOnTarget!,
          );
          if (replace != true || !mounted) {
            return;
          }
          setState(() => _busy = true);
          await LocalDataStore.instance.reassignScan(
            scan: widget.scan,
            targetOmrId: target.omrId,
            replaceExisting: true,
          );
          if (!mounted) return;
          Navigator.pop(context, true);
          return;
        case ScanReassignStatus.ready:
          final ok = await _confirmMove(target);
          if (ok != true || !mounted) {
            setState(() => _busy = false);
            return;
          }
          await LocalDataStore.instance.reassignScan(
            scan: widget.scan,
            targetOmrId: target.omrId,
          );
          if (!mounted) return;
          Navigator.pop(context, true);
          return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is StateError
            ? e.message
            : 'Could not reassign this scan. Try again.';
      });
    }
  }

  Future<bool?> _confirmMove(Student target) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move this scan?'),
        content: Text(
          'Assign this paper’s answers to ${target.name} (OMR ${target.omrId}).\n\n'
          'The student who currently has this scan will no longer have it for '
          '${widget.scan.subjectName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Move scan'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmConflict({
    required Student target,
    required ScanResult existing,
  }) {
    final imagePath = widget.scan.scannedImagePath;
    final hasImage = imagePath != null &&
        imagePath.isNotEmpty &&
        File(imagePath).existsSync();

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This student already has a score'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${target.name} (OMR ${target.omrId}) already has a saved scan '
                'for ${widget.scan.subjectName} '
                '(${existing.scoreDisplay}/${existing.totalQuestions}).',
                style: AppTypography.body,
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusWarningBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.statusWarningBorder),
                ),
                child: const Text(
                  'Before replacing anything, check the handwritten name on '
                  'this paper (the name blank) to confirm who it really belongs to.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              if (hasImage) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog(
                        insetPadding: const EdgeInsets.all(16),
                        backgroundColor: Colors.black,
                        child: Stack(
                          children: [
                            InteractiveViewer(
                              maxScale: 5,
                              child: Center(
                                child: Image.file(File(imagePath)),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('View sheet to check name'),
                ),
              ],
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text("I've checked the name — replace score"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = findStudentByOmrId(widget.scan.studentOmrId);
    final candidates = _candidates;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Reassign scan', style: AppTypography.sectionTitle),
            const SizedBox(height: 4),
            Text(
              'Currently on ${current?.name ?? 'Unknown'} '
              '(OMR ${widget.scan.studentOmrId}) · ${widget.scan.subjectName}',
              style: AppTypography.captionMuted,
            ),
            const SizedBox(height: 8),
            const Text(
              'Pick who this paper belongs to. If they already have a score, '
              'you will be asked to check the name blank first — we will not '
              'replace a grade silently.',
              style: AppTypography.body,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              enabled: !_busy,
              decoration: const InputDecoration(
                hintText: 'Search name or OMR ID',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTypography.body.copyWith(color: AppColors.statusDanger),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : candidates.isEmpty
                      ? const Center(
                          child: Text('No matching students on your roster.'),
                        )
                      : ListView.separated(
                          itemCount: candidates.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final student = candidates[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                student.name,
                                style: AppTypography.listTitle,
                              ),
                              subtitle: Text(
                                'OMR ${student.omrId} · ${student.section}',
                                style: AppTypography.captionMuted,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _onPick(student),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
