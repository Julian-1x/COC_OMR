import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/phone_archive_pack.dart';

void main() {
  test('PhoneArchivePack round-trips scores without photo paths', () {
    final pack = PhoneArchivePack(
      id: 'arch_1',
      kind: PhoneArchivePack.kindStudent,
      title: 'Juan Dela Cruz',
      createdAt: DateTime.utc(2026, 9, 19),
      omrIds: const ['0001'],
      sectionNames: const ['BSIT-01'],
      students: [
        Student(
          schoolId: 'S1',
          omrId: '0001',
          name: 'Juan Dela Cruz',
          section: 'BSIT-01',
          score: 42,
        ),
      ],
      scanResults: [
        ScanResult(
          studentOmrId: '0001',
          subjectName: 'Math',
          detectedAnswers: const {1: 'A'},
          correctnessMap: const {1: 1.0},
          score: 42,
          totalQuestions: 50,
          confidence: 0.9,
          scanTime: DateTime.utc(2026, 9, 1),
          scannedImagePath: '/tmp/should-not-persist.jpg',
        ),
      ],
    );

    final restored = PhoneArchivePack.fromJson(pack.toJson());
    expect(restored.title, 'Juan Dela Cruz');
    expect(restored.scanCount, 1);
    expect(restored.scanResults.first.scannedImagePath, isNull);
    expect(restored.scanResults.first.score, 42);
  });
}
