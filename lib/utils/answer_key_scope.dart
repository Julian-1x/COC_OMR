import 'package:omr_app/models/exam_data.dart';

/// How an answer key relates to class sections.
///
/// Teachers must never confuse:
/// - **shared** — one key grades every linked section (same answers)
/// - **sectionOnly** — this key is for one section; a same-named key may
///   exist for another section with different answers
enum AnswerKeyScopeKind {
  /// No section linked yet — print/scan should not proceed as exam-ready.
  unassigned,

  /// Exactly one section — "personal" / per-section key.
  sectionOnly,

  /// Two or more sections share this key.
  shared,
}

/// Immutable view of [Subject.sectionNames] for badges, print, and scan copy.
class AnswerKeyScope {
  const AnswerKeyScope._({
    required this.kind,
    required this.sections,
  });

  final AnswerKeyScopeKind kind;

  /// Display-order section names (trimmed, non-empty).
  final List<String> sections;

  factory AnswerKeyScope.of(Subject subject) {
    final sections = (subject.sectionNames ?? const <String>[])
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (sections.isEmpty) {
      return const AnswerKeyScope._(
        kind: AnswerKeyScopeKind.unassigned,
        sections: <String>[],
      );
    }
    if (sections.length == 1) {
      return AnswerKeyScope._(
        kind: AnswerKeyScopeKind.sectionOnly,
        sections: sections,
      );
    }
    return AnswerKeyScope._(
      kind: AnswerKeyScopeKind.shared,
      sections: sections,
    );
  }

  bool get isShared => kind == AnswerKeyScopeKind.shared;
  bool get isSectionOnly => kind == AnswerKeyScopeKind.sectionOnly;
  bool get isUnassigned => kind == AnswerKeyScopeKind.unassigned;

  /// Compact chip: `Shared` / `One section` / `No section`.
  String get shortBadge {
    switch (kind) {
      case AnswerKeyScopeKind.unassigned:
        return 'No section';
      case AnswerKeyScopeKind.sectionOnly:
        return 'One section';
      case AnswerKeyScopeKind.shared:
        return 'Shared';
    }
  }

  /// Chip with count or section name when space allows.
  String get badgeLabel {
    switch (kind) {
      case AnswerKeyScopeKind.unassigned:
        return 'No section';
      case AnswerKeyScopeKind.sectionOnly:
        return 'One section · ${sections.first}';
      case AnswerKeyScopeKind.shared:
        return 'Shared · ${sections.length} sections';
    }
  }

  /// One line under a subject title on lists.
  String get listSubtitle {
    switch (kind) {
      case AnswerKeyScopeKind.unassigned:
        return 'No sections assigned — add a section before printing or scanning.';
      case AnswerKeyScopeKind.sectionOnly:
        return 'Section-only key — grades ${sections.first} only. '
            'Other sections need their own key if answers differ.';
      case AnswerKeyScopeKind.shared:
        return 'Shared key — same answers for ${sections.join(', ')}.';
    }
  }

  /// Scanner / grading context (which classes this open key covers).
  String get gradingContextLabel {
    switch (kind) {
      case AnswerKeyScopeKind.unassigned:
        return 'No section on this key';
      case AnswerKeyScopeKind.sectionOnly:
        return 'Grading ${sections.first} only';
      case AnswerKeyScopeKind.shared:
        return 'Shared key · ${sections.join(', ')}';
    }
  }

  /// PDF header tag next to SECTION: …
  ///
  /// [printedSection] is the section printed on this sheet (QR / roster pack).
  String printScopeTag({String? printedSection}) {
    switch (kind) {
      case AnswerKeyScopeKind.unassigned:
        return 'NO SECTION';
      case AnswerKeyScopeKind.sectionOnly:
        return 'THIS SECTION ONLY';
      case AnswerKeyScopeKind.shared:
        final printed = printedSection?.trim() ?? '';
        if (printed.isNotEmpty && sections.length > 1) {
          return 'SHARED KEY';
        }
        return 'SHARED KEY';
    }
  }

  /// Subject title that includes scope so same names stay distinct.
  ///
  /// Examples: `Math · BSIT-01 only` / `Math · Shared (2 sections)`.
  String describeSubject(Subject subject) {
    final name = subject.displayName.trim().isEmpty
        ? 'Answer key'
        : subject.displayName.trim();
    switch (kind) {
      case AnswerKeyScopeKind.unassigned:
        return '$name · no section';
      case AnswerKeyScopeKind.sectionOnly:
        return '$name · ${sections.first} only';
      case AnswerKeyScopeKind.shared:
        if (sections.length <= 2) {
          return '$name · Shared (${sections.join(', ')})';
        }
        return '$name · Shared (${sections.length} sections)';
    }
  }

  /// Hard-block copy when sheet QR subject id is a sibling key (same name,
  /// different section ownership).
  static String wrongKeyMessage({
    required Subject scannerSubject,
    required Subject sheetSubject,
  }) {
    final scannerScope = AnswerKeyScope.of(scannerSubject);
    final sheetScope = AnswerKeyScope.of(sheetSubject);
    return 'This sheet belongs to ${sheetScope.describeSubject(sheetSubject)}, '
        'but you are grading ${scannerScope.describeSubject(scannerSubject)}.\n\n'
        'Same subject name can have different keys per section. '
        'Open the answer key that matches this sheet\'s section, or reprint '
        'from the key you are grading now.';
  }

  /// When QR section is not on the open key.
  static String wrongSectionForOpenKeyMessage({
    required Subject scannerSubject,
    required String sheetSection,
  }) {
    final scope = AnswerKeyScope.of(scannerSubject);
    switch (scope.kind) {
      case AnswerKeyScopeKind.unassigned:
        return 'This sheet is for $sheetSection, but the open answer key has '
            'no section assigned. Add a section to the key or open the correct key.';
      case AnswerKeyScopeKind.sectionOnly:
        return 'This sheet is for $sheetSection, but you opened a '
            'section-only key for ${scope.sections.first}.\n\n'
            'Open the answer key for $sheetSection, or print sheets from '
            '${scope.sections.first}\'s key.';
      case AnswerKeyScopeKind.shared:
        return 'This sheet is for $sheetSection, which is not on this shared key '
            '(${scope.sections.join(', ')}).\n\n'
            'Print from this key for one of its sections, or open the key that '
            'includes $sheetSection.';
    }
  }
}
