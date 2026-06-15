import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/cloud_snapshot.dart';

void main() {
  test('cloud merge adds missing rows on empty local state', () {
    final cloud = CloudPullSnapshot(
      sections: [
        Section(
          name: 'STEM-A',
          cloudId: 'sec-1',
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime(2026, 4, 1),
        ),
      ],
      students: [
        Student(
          schoolId: 'S1',
          omrId: '0001',
          name: 'Ana',
          section: 'STEM-A',
          cloudId: 'stu-1',
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime(2026, 4, 1),
        ),
      ],
    );

    final merged = CloudSnapshotMerger.merge(
      localSections: const <Section>[],
      localStudents: const <Student>[],
      localSubjects: const <Subject>[],
      localScanResults: const <ScanResult>[],
      localDeadlines: const <Deadline>[],
      cloud: cloud,
    );

    expect(merged.sections.length, 1);
    expect(merged.students.length, 1);
    expect(merged.summary.total, greaterThan(0));
  });

  test('cloud merge keeps newer pending local row', () {
    final localUpdated = DateTime(2026, 4, 10);
    final cloudUpdated = DateTime(2026, 4, 8);

    final merged = CloudSnapshotMerger.merge(
      localSections: const <Section>[],
      localStudents: [
        Student(
          schoolId: 'S1',
          omrId: '0001',
          name: 'Ana Local',
          section: 'STEM-A',
          cloudId: 'stu-1',
          syncStatus: SyncStatus.pending,
          updatedAt: localUpdated,
        ),
      ],
      localSubjects: const <Subject>[],
      localScanResults: const <ScanResult>[],
      localDeadlines: const <Deadline>[],
      cloud: CloudPullSnapshot(
        students: [
          Student(
            schoolId: 'S1',
            omrId: '0001',
            name: 'Ana Cloud',
            section: 'STEM-A',
            cloudId: 'stu-1',
            syncStatus: SyncStatus.synced,
            updatedAt: cloudUpdated,
          ),
        ],
      ),
    );

    expect(merged.students.single.name, 'Ana Local');
  });

  test('cloud merge prefers cloud when local has no cloud id', () {
    final merged = CloudSnapshotMerger.merge(
      localSections: const <Section>[],
      localStudents: [
        Student(
          schoolId: 'S1',
          omrId: '0001',
          name: 'Ana Local',
          section: 'STEM-A',
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime(2026, 4, 10),
        ),
      ],
      localSubjects: const <Subject>[],
      localScanResults: const <ScanResult>[],
      localDeadlines: const <Deadline>[],
      cloud: CloudPullSnapshot(
        students: [
          Student(
            schoolId: 'S1',
            omrId: '0001',
            name: 'Ana Cloud',
            section: 'STEM-A',
            cloudId: 'stu-1',
            syncStatus: SyncStatus.synced,
            updatedAt: DateTime(2026, 4, 1),
          ),
        ],
      ),
    );

    expect(merged.students.single.name, 'Ana Cloud');
    expect(merged.students.single.cloudId, 'stu-1');
  });

  test('cloud merge keeps old and new section names when cloud was not tombstoned', () {
    final merged = CloudSnapshotMerger.merge(
      localSections: [
        Section(
          name: 'BSIT-1B',
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime(2026, 4, 10),
        ),
      ],
      localStudents: const <Student>[],
      localSubjects: const <Subject>[],
      localScanResults: const <ScanResult>[],
      localDeadlines: const <Deadline>[],
      cloud: CloudPullSnapshot(
        sections: [
          Section(
            name: 'BSIT-1A',
            cloudId: 'sec-old',
            syncStatus: SyncStatus.synced,
            updatedAt: DateTime(2026, 4, 1),
          ),
        ],
      ),
    );

    expect(merged.sections.map((section) => section.name), containsAll([
      'BSIT-1A',
      'BSIT-1B',
    ]));
  });
}
