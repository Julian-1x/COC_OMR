import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';

enum AnswerKeyDeleteChoice {
  cancelled,
  sectionOnly,
  entireSubject,
}

Future<AnswerKeyDeleteChoice> showAnswerKeyDeleteDialog({
  required BuildContext context,
  required Subject subject,
  String? sectionName,
}) {
  final sections = List<String>.from(subject.sectionNames ?? const <String>[])
    ..sort();
  final focusSection = sectionName?.trim();
  final normalizedFocus =
      focusSection == null ? null : normalizeSectionName(focusSection);
  final isShared = normalizedFocus != null &&
      sections.any((name) => normalizeSectionName(name) == normalizedFocus) &&
      sections.length > 1;

  final scansForSection = normalizedFocus == null
      ? findScansBySubject(subject.id)
      : globalScanResults.where((result) {
          if (result.subjectId != subject.id) {
            return false;
          }
          final student = findStudentByOmrId(result.studentOmrId);
          return student != null &&
              normalizeSectionName(student.section) == normalizedFocus;
        }).toList();

  final linkedScans = isShared ? scansForSection.length : findScansBySubject(subject.id).length;
  final linkedDeadlines = globalDeadlines
      .where((deadline) => deadline.subjectId == subject.id)
      .length;

  if (!isShared) {
    return showDialog<AnswerKeyDeleteChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Answer Key?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              focusSection == null
                  ? 'This will permanently delete ${subject.displayName}.'
                  : 'This will permanently delete ${subject.displayName} for $focusSection.',
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
                '$linkedScans saved scan result${linkedScans == 1 ? '' : 's'} tied to this answer key will also be removed.',
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
            onPressed: () =>
                Navigator.pop(context, AnswerKeyDeleteChoice.cancelled),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, AnswerKeyDeleteChoice.entireSubject),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((value) => value ?? AnswerKeyDeleteChoice.cancelled);
  }

  return showDialog<AnswerKeyDeleteChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove ${subject.displayName}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This answer key is shared across ${sections.length} sections: '
            '${sections.join(', ')}.',
          ),
          const SizedBox(height: 12),
          Text(
            'Choose what to delete for $focusSection:',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            '• Remove from this section only — other sections keep the same key.',
          ),
          const SizedBox(height: 8),
          const Text(
            '• Delete entire answer key — removes it from every assigned section.',
          ),
          if (linkedScans > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$linkedScans scan result${linkedScans == 1 ? '' : 's'} from $focusSection will be removed if you unlink this section.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, AnswerKeyDeleteChoice.cancelled),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, AnswerKeyDeleteChoice.sectionOnly),
          child: Text('Remove from $focusSection'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(context, AnswerKeyDeleteChoice.entireSubject),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete entire key'),
        ),
      ],
    ),
  ).then((value) => value ?? AnswerKeyDeleteChoice.cancelled);
}

String answerKeyDeletionMessage({
  required Subject subject,
  required SubjectDeletionSummary summary,
}) {
  if (summary.removedFromSectionOnly) {
    final section = summary.detachedSectionName ?? 'section';
    return 'Removed ${subject.displayName} from $section. '
        'Deleted ${summary.removedScans} scan${summary.removedScans == 1 ? '' : 's'}.';
  }

  return 'Deleted ${subject.displayName}. '
      'Removed ${summary.removedScans} scan${summary.removedScans == 1 ? '' : 's'}.';
}
