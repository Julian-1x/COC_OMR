/// Helpers for grouping class sections by program (BSIT, BSECE, etc.).
class SectionProgram {
  SectionProgram._();

  static const Map<String, String> _friendlyLabels = <String, String>{
    'BSIT': 'Information Technology',
    'BSCS': 'Computer Science',
    'BSECE': 'Electronics Engineering',
    'BSEE': 'Electrical Engineering',
    'BSME': 'Mechanical Engineering',
    'BSCE': 'Civil Engineering',
    'BSIE': 'Industrial Engineering',
    'BSCPE': 'Computer Engineering',
    'BSTM': 'Tourism Management',
    'BSHM': 'Hospitality Management',
    'BSA': 'Accountancy',
    'BSBA': 'Business Administration',
    'BSED': 'Secondary Education',
    'BEED': 'Elementary Education',
    'BSN': 'Nursing',
    'BSP': 'Psychology',
  };

  /// Program code inferred from a section name such as `BSIT-01` or `BSECE 2A`.
  static String programKey(String sectionName) {
    final trimmed = sectionName.trim();
    if (trimmed.isEmpty) {
      return 'OTHER';
    }

    final programMatch = RegExp(r'^([A-Za-z]{2,})').firstMatch(trimmed);
    if (programMatch != null) {
      return programMatch.group(1)!.toUpperCase();
    }

    final prefix = trimmed.split(RegExp(r'[-\s_/]')).first.trim();
    return prefix.isEmpty ? 'OTHER' : prefix.toUpperCase();
  }

  /// Short chip label, e.g. `BSIT`.
  static String chipLabel(String programKey) => programKey.toUpperCase();

  /// Teacher-friendly heading, e.g. `BSIT · Information Technology`.
  static String groupTitle(String programKey) {
    final key = programKey.toUpperCase();
    final friendly = _friendlyLabels[key];
    if (friendly == null) {
      return key == 'OTHER' ? 'Other sections' : key;
    }
    return '$key · $friendly';
  }

  static List<String> sortedProgramKeys(Iterable<String> sectionNames) {
    return sectionNames.map(programKey).toSet().toList()..sort();
  }
}
