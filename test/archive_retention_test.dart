import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/services/archive_retention.dart';

void main() {
  test('archive packs expire after 4 months', () {
    final archived = DateTime(2026, 1, 15, 10);
    expect(ArchiveRetention.isExpired(archived, DateTime(2026, 5, 14, 10)), isFalse);
    expect(ArchiveRetention.isExpired(archived, DateTime(2026, 5, 15, 10)), isTrue);
    expect(ArchiveRetention.isExpired(archived, DateTime(2026, 6, 1)), isTrue);
  });

  test('deleteAfter is about 4 months later', () {
    final archived = DateTime(2026, 1, 31);
    final deadline = ArchiveRetention.deleteAfter(archived);
    expect(deadline.year, 2026);
    expect(deadline.month, 5);
  });
}
