/// Canonical school identity for this COC deployment.
abstract final class CocSchool {
  static const String name = 'Cagayan de Oro College';

  /// COC academic departments shown on registration.
  static const List<String> departments = <String>[
    'COE',
    'SCCJ',
    'CMA',
    'CIT',
    'CEA',
    'CAHS',
  ];

  static bool isValidDepartment(String value) {
    return departments.contains(value.trim().toUpperCase());
  }
}
