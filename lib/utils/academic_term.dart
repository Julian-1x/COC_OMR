/// School year and term helpers (Philippines-style: year starts around June).
class AcademicTerm {
  AcademicTerm._();

  /// e.g. "2025-2026" for SY that includes the given date.
  static String schoolYearForDate([DateTime? date]) {
    final local = (date ?? DateTime.now()).toLocal();
    final startYear = local.month >= 6 ? local.year : local.year - 1;
    return '$startYear-${startYear + 1}';
  }

  static const List<String> commonTermLabels = <String>[
    '1st Sem',
    '2nd Sem',
    'Summer',
  ];

  static String defaultTermLabel([DateTime? date]) {
    final month = (date ?? DateTime.now()).toLocal().month;
    if (month >= 6 && month <= 10) {
      return '1st Sem';
    }
    if (month >= 11 || month <= 3) {
      return '2nd Sem';
    }
    return 'Summer';
  }

  static List<String> schoolYearOptions({int past = 2, int future = 1}) {
    final currentStart = int.parse(schoolYearForDate().split('-').first);
    return List<String>.generate(
      past + 1 + future,
      (index) {
        final start = currentStart - past + index;
        return '$start-${start + 1}';
      },
    );
  }
}
