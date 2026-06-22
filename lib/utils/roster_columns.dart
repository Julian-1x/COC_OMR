/// Flexible column detection for student roster imports (CSV / Excel).
class RosterColumnMap {
  const RosterColumnMap({
    required this.schoolIdIndex,
    required this.nameIndex,
    required this.sectionIndex,
    this.firstNameIndex = -1,
    this.lastNameIndex = -1,
  });

  final int schoolIdIndex;
  final int nameIndex;
  final int sectionIndex;
  final int firstNameIndex;
  final int lastNameIndex;

  bool get usesSplitName => firstNameIndex != -1 && lastNameIndex != -1;

  /// Normalized header cell: lowercase, collapsed spaces, stripped punctuation.
  static String normalizeHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static int detectHeaderRow(List<List<dynamic>> rows, String Function(dynamic) readCell) {
    final maxRows = rows.length < 8 ? rows.length : 8;
    var bestIndex = -1;
    var bestScore = 0;

    for (var i = 0; i < maxRows; i++) {
      final normalized = rows[i].map((cell) => normalizeHeader(readCell(cell))).toList();
      var score = 0;
      if (_headerHasId(normalized)) {
        score++;
      }
      if (_headerHasName(normalized)) {
        score++;
      }
      if (_headerHasSection(normalized)) {
        score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    return bestScore >= 2 ? bestIndex : -1;
  }

  static RosterColumnMap fromHeader(List<String> header) {
    final idIdx = _findHeaderIndex(header, _schoolIdHeaderKeys);
    final nameIdx = _findHeaderIndex(header, _nameHeaderKeys);
    final sectionIdx = _findHeaderIndex(header, _sectionHeaderKeys);
    final firstNameIdx = _findHeaderIndex(header, _firstNameHeaderKeys);
    final lastNameIdx = _findHeaderIndex(header, _lastNameHeaderKeys);

    return RosterColumnMap(
      schoolIdIndex: idIdx != -1 ? idIdx : 0,
      nameIndex: nameIdx != -1 ? nameIdx : 1,
      sectionIndex: sectionIdx != -1 ? sectionIdx : 2,
      firstNameIndex: firstNameIdx,
      lastNameIndex: lastNameIdx,
    );
  }

  /// Guess columns from cell content when headers are missing or unusual.
  static RosterColumnMap? inferFromRows(
    List<List<dynamic>> rows,
    String Function(dynamic) readCell, {
    int startIndex = 0,
  }) {
    if (rows.isEmpty) {
      return null;
    }

    final sample = rows
        .skip(startIndex)
        .take(25)
        .map((row) => row.map(readCell).toList())
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    if (sample.isEmpty) {
      return null;
    }

    final maxCols = sample.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (maxCols < 2) {
      return null;
    }

    final schoolScores = List<int>.filled(maxCols, 0);
    final sectionScores = List<int>.filled(maxCols, 0);
    final nameScores = List<int>.filled(maxCols, 0);

    for (final row in sample) {
      for (var col = 0; col < row.length; col++) {
        final value = row[col].trim();
        if (value.isEmpty) {
          continue;
        }
        if (looksLikeSchoolId(value)) {
          schoolScores[col]++;
        } else if (looksLikeSection(value)) {
          sectionScores[col]++;
        } else if (looksLikeName(value)) {
          nameScores[col]++;
        }
      }
    }

    final schoolIdIndex = _bestDistinctColumn(schoolScores);
    final sectionIndex = _bestDistinctColumn(sectionScores, exclude: {schoolIdIndex});
    final nameIndex = _bestDistinctColumn(nameScores, exclude: {schoolIdIndex, sectionIndex});

    if (schoolIdIndex == -1 || nameIndex == -1) {
      return null;
    }

    return RosterColumnMap(
      schoolIdIndex: schoolIdIndex,
      nameIndex: nameIndex,
      sectionIndex: sectionIndex != -1 ? sectionIndex : 2,
    );
  }

  static bool looksLikeSchoolId(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 4) {
      return false;
    }
    if (RegExp(r'^\d{2}-\d{4}-\d{3,6}$').hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(r'^[A-Z0-9][A-Z0-9\-]{3,}$').hasMatch(trimmed.toUpperCase()) &&
        trimmed.contains(RegExp(r'\d')) &&
        !looksLikeSection(trimmed)) {
      return true;
    }
    return false;
  }

  static bool looksLikeSection(String value) {
    final upper = value.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2,12}-\d{1,2}[A-Z]?$').hasMatch(upper) ||
        RegExp(r'^[A-Z]{2,12}\s*\d{1,2}[A-Z]?$').hasMatch(upper);
  }

  static bool looksLikeName(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      return false;
    }
    if (looksLikeSchoolId(trimmed) || looksLikeSection(trimmed)) {
      return false;
    }
    return RegExp(r"^[A-Za-z .'\-]+$").hasMatch(trimmed);
  }

  static int _bestDistinctColumn(List<int> scores, {Set<int> exclude = const {}}) {
    var bestIndex = -1;
    var bestScore = 0;
    for (var i = 0; i < scores.length; i++) {
      if (exclude.contains(i)) {
        continue;
      }
      if (scores[i] > bestScore) {
        bestScore = scores[i];
        bestIndex = i;
      }
    }
    return bestScore > 0 ? bestIndex : -1;
  }

  static bool _headerHasId(List<String> cells) =>
      _findHeaderIndex(cells, _schoolIdHeaderKeys) != -1;

  static bool _headerHasName(List<String> cells) =>
      _findHeaderIndex(cells, _nameHeaderKeys) != -1 ||
      (_findHeaderIndex(cells, _firstNameHeaderKeys) != -1 &&
          _findHeaderIndex(cells, _lastNameHeaderKeys) != -1);

  static bool _headerHasSection(List<String> cells) =>
      _findHeaderIndex(cells, _sectionHeaderKeys) != -1;

  static int _findHeaderIndex(List<String> header, List<String> keys) {
    for (final key in keys) {
      final exact = header.indexOf(key);
      if (exact != -1) {
        return exact;
      }
    }
    for (var i = 0; i < header.length; i++) {
      final cell = header[i];
      if (cell.isEmpty) {
        continue;
      }
      for (final key in keys) {
        if (cell == key || cell.contains(key)) {
          return i;
        }
      }
    }
    return -1;
  }

  static const _schoolIdHeaderKeys = [
    'student id',
    'studentid',
    'student number',
    'student no',
    'studentno',
    'school id',
    'schoolid',
    'learner reference number',
    'lrn',
    'id number',
    'id no',
    'id',
  ];

  static const _nameHeaderKeys = [
    'student name',
    'full name',
    'fullname',
    'name',
    'complete name',
    'learner name',
  ];

  static const _sectionHeaderKeys = [
    'section name',
    'year and section',
    'year & section',
    'yr and section',
    'yr & section',
    'class section',
    'section',
    'class',
    'block',
    'course',
    'group',
    'strand',
  ];

  static const _firstNameHeaderKeys = [
    'first name',
    'firstname',
    'given name',
    'given',
    'fname',
  ];

  static const _lastNameHeaderKeys = [
    'last name',
    'lastname',
    'surname',
    'family name',
    'lname',
  ];
}
