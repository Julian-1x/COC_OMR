import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/cloud_snapshot.dart';
import 'package:omr_app/utils/sync_activity_message.dart';

void main() {
  test('unchanged library is not reported as a download', () {
    expect(
      describeSyncActivity(
        uploadedNotes: const [],
        failureNotes: const [],
        uploadedSections: 0,
        uploadedStudents: 0,
        uploadedScanResults: 0,
        uploadedDeadlines: 0,
        downloadedNotes: const [],
        downloadedSections: 0,
        downloadedStudents: 0,
        downloadedScanResults: 0,
        downloadedDeadlines: 0,
      ),
      'Everything is already synced.',
    );
  });

  test('sharing an answer key names the classes', () {
    expect(
      uploadedSubjectSentence(
        name: 'Math',
        sections: const ['COC-FA-ME2-02', 'COC-FA-ME2-03'],
      ),
      'Uploaded the shared answer key Math for COC-FA-ME2-02 and COC-FA-ME2-03.',
    );
  });

  test('cloud merge says when a key becomes shared', () {
    final merged = CloudSnapshotMerger.merge(
      localSections: const <Section>[],
      localStudents: const <Student>[],
      localSubjects: [
        Subject(
          id: 'math',
          name: 'Math',
          answerKey: const {1: ['A']},
          sectionNames: const ['COC-FA-ME2-02'],
          cloudId: 'sub-1',
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime.utc(2026, 10, 14, 6),
        ),
      ],
      localScanResults: const <ScanResult>[],
      localDeadlines: const <Deadline>[],
      cloud: CloudPullSnapshot(
        subjects: [
          Subject(
            id: 'math',
            name: 'Math',
            answerKey: const {1: ['A']},
            sectionNames: const ['COC-FA-ME2-02', 'COC-FA-ME2-03'],
            cloudId: 'sub-1',
            syncStatus: SyncStatus.synced,
            updatedAt: DateTime.utc(2026, 10, 14, 6, 5),
          ),
        ],
      ),
    );

    expect(
      merged.summary.notes,
      [
        'Math is now a shared key for COC-FA-ME2-02 and COC-FA-ME2-03.',
      ],
    );
  });

  test('a failed upload is not described as zero changes', () {
    expect(
      describeSyncActivity(
        uploadedNotes: const [],
        failureNotes: const [
          'The answer key Math did not upload. Tap Sync now again.',
        ],
        uploadedSections: 0,
        uploadedStudents: 0,
        uploadedScanResults: 0,
        uploadedDeadlines: 0,
        downloadedNotes: const [],
        downloadedSections: 0,
        downloadedStudents: 0,
        downloadedScanResults: 0,
        downloadedDeadlines: 0,
      ),
      'The answer key Math did not upload. Tap Sync now again.',
    );
  });
}
