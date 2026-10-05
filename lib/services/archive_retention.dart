/// Soft-archived phone packs and cloud sections/students older than this
/// are permanently deleted (restore before the deadline).
class ArchiveRetention {
  ArchiveRetention._();

  static const int months = 4;

  static DateTime cutoff([DateTime? now]) {
    final base = now ?? DateTime.now();
    // Calendar months, clamped (e.g. Jan 31 → Sep 30).
    final year = base.year;
    final month = base.month - months;
    final target = DateTime(year, month, 1);
    final day = base.day.clamp(1, _daysInMonth(target.year, target.month));
    return DateTime(
      target.year,
      target.month,
      day,
      base.hour,
      base.minute,
      base.second,
      base.millisecond,
      base.microsecond,
    );
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  static DateTime deleteAfter(DateTime archivedAt) {
    final year = archivedAt.year;
    final month = archivedAt.month + months;
    final target = DateTime(year, month, 1);
    final day =
        archivedAt.day.clamp(1, _daysInMonth(target.year, target.month));
    return DateTime(
      target.year,
      target.month,
      day,
      archivedAt.hour,
      archivedAt.minute,
      archivedAt.second,
      archivedAt.millisecond,
      archivedAt.microsecond,
    );
  }

  static bool isExpired(DateTime archivedAt, [DateTime? now]) {
    return !archivedAt.isAfter(cutoff(now));
  }
}
