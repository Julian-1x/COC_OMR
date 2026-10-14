/// What the teacher should read after Sync now.
///
/// Counts only rows that changed. A full cloud library is not a download.
String describeSyncActivity({
  required List<String> uploadedNotes,
  required List<String> failureNotes,
  required int uploadedSections,
  required int uploadedStudents,
  required int uploadedScanResults,
  required int uploadedDeadlines,
  required List<String> downloadedNotes,
  required int downloadedSections,
  required int downloadedStudents,
  required int downloadedScanResults,
  required int downloadedDeadlines,
}) {
  final lines = <String>[
    ...failureNotes,
    ...uploadedNotes,
    ..._countLines(
      verb: 'Uploaded',
      sections: uploadedSections,
      students: uploadedStudents,
      scanResults: uploadedScanResults,
      deadlines: uploadedDeadlines,
    ),
    ...downloadedNotes,
    ..._countLines(
      verb: 'Downloaded',
      sections: downloadedSections,
      students: downloadedStudents,
      scanResults: downloadedScanResults,
      deadlines: downloadedDeadlines,
    ),
  ];

  if (lines.isEmpty) {
    return 'Everything is already synced.';
  }
  return lines.join(' ');
}

String uploadedSubjectSentence({
  required String name,
  required List<String>? sections,
}) {
  final linked = _cleanSections(sections);
  if (linked.length > 1) {
    return 'Uploaded the shared answer key $name for ${joinSyncNames(linked)}.';
  }
  if (linked.length == 1) {
    return 'Uploaded the answer key $name for ${linked.first}.';
  }
  return 'Uploaded the answer key $name.';
}

String cloudSubjectSentence({
  required String name,
  required List<String>? sections,
  required bool isNew,
  required bool sectionsChanged,
}) {
  final linked = _cleanSections(sections);
  if (sectionsChanged && linked.length > 1) {
    return '$name is now a shared key for ${joinSyncNames(linked)}.';
  }
  if (isNew && linked.length > 1) {
    return 'Downloaded the shared answer key $name for ${joinSyncNames(linked)}.';
  }
  if (isNew && linked.length == 1) {
    return 'Downloaded the answer key $name for ${linked.first}.';
  }
  if (isNew) {
    return 'Downloaded the answer key $name.';
  }
  if (linked.length == 1) {
    return 'Updated the answer key $name for ${linked.first} from the cloud.';
  }
  return 'Updated the answer key $name from the cloud.';
}

String failedUploadSentence(String label) {
  return '$label did not upload. Tap Sync now again.';
}

String joinSyncNames(List<String> names) {
  if (names.length <= 1) {
    return names.isEmpty ? '' : names.first;
  }
  if (names.length == 2) {
    return '${names[0]} and ${names[1]}';
  }
  return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
}

String lastUploadBatchLabel({
  required bool hasSummary,
  required int total,
  required int subjects,
  required bool failed,
}) {
  if (!hasSummary) {
    return 'None yet';
  }
  if (failed && total == 0) {
    return 'Did not upload';
  }
  if (total == 0) {
    return 'Nothing new';
  }
  if (subjects > 0 && total == subjects) {
    return subjects == 1 ? '1 answer key' : '$subjects answer keys';
  }
  return '$total item${total == 1 ? '' : 's'}';
}

List<String> _cleanSections(List<String>? sections) {
  return (sections ?? const <String>[])
      .map((section) => section.trim())
      .where((section) => section.isNotEmpty)
      .toList();
}

List<String> _countLines({
  required String verb,
  required int sections,
  required int students,
  required int scanResults,
  required int deadlines,
}) {
  final parts = <String>[
    if (sections > 0) _plural(sections, 'class', 'classes'),
    if (students > 0) _plural(students, 'student', 'students'),
    if (scanResults > 0) _plural(scanResults, 'graded sheet', 'graded sheets'),
    if (deadlines > 0) _plural(deadlines, 'deadline', 'deadlines'),
  ];
  if (parts.isEmpty) {
    return const <String>[];
  }
  return <String>['$verb ${joinSyncNames(parts)}.'];
}

String _plural(int count, String one, String many) {
  return '$count ${count == 1 ? one : many}';
}
