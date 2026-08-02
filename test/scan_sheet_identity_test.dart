import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/utils/scan_sheet_identity.dart';

void main() {
  setUp(() {
    globalSubjects = <Subject>[];
  });

  Subject _subject({
    String id = 'SUB-0001',
    String? cloudId,
    String? ownerTeacherId,
  }) {
    return Subject(
      id: id,
      name: 'HUM-232',
      answerKey: <int, String>{for (int i = 1; i <= 50; i++) i: 'A'},
      totalQuestions: 50,
      sectionNames: const <String>['BSIT-1A'],
      ownerTeacherId: ownerTeacherId,
      cloudId: cloudId,
    );
  }

  SubjectSheetQrPayload _payload({
    String subjectId = 'SUB-0001',
    String? ownerTeacherId,
    String? ownerTeacherEmail,
    String? ownerTeacherName,
    String? subjectCloudId,
    String subjectName = 'HUM-232',
  }) {
    return SubjectSheetQrPayload(
      version: 2,
      sheetId: 'SHEET-1',
      subjectId: subjectId,
      subjectName: subjectName,
      totalQuestions: 50,
      passingScore: 30,
      sectionName: 'BSIT-1A',
      ownerTeacherId: ownerTeacherId,
      ownerTeacherEmail: ownerTeacherEmail,
      ownerTeacherName: ownerTeacherName,
      subjectCloudId: subjectCloudId,
    );
  }

  ScanSheetOwnershipFailure? _failure({
    required Subject target,
    required SubjectSheetQrPayload payload,
    String? currentUserId,
    String? currentTeacherEmail,
    String? currentTeacherName,
    List<Subject>? ownedSubjects,
  }) {
    return ScanSheetIdentity.ownershipFailure(
      targetSubject: target,
      qrPayload: payload,
      currentUserId: currentUserId,
      currentTeacherEmail: currentTeacherEmail,
      currentTeacherName: currentTeacherName,
      ownedSubjects: ownedSubjects,
    );
  }

  test('blocks when QR ownerTeacherId differs from signed-in teacher', () {
    final target = _subject(ownerTeacherId: 'teacher-a');
    final failure = _failure(
      target: target,
      payload: _payload(
        ownerTeacherId: 'teacher-b',
        ownerTeacherEmail: 'maria@coc.edu.ph',
        ownerTeacherName: 'Maria Santos',
      ),
      currentUserId: 'teacher-a',
      currentTeacherEmail: 'juan@coc.edu.ph',
      ownedSubjects: <Subject>[target],
    );

    expect(failure?.failureReason, 'WRONG_TEACHER');
    expect(failure?.message, contains('printed by maria@coc.edu.ph'));
    expect(failure?.message, contains('signed in as juan@coc.edu.ph'));
    expect(failure?.message, contains('HUM-232'));
  });

  test('allows when QR ownerTeacherId matches signed-in teacher', () {
    final target = _subject(ownerTeacherId: 'teacher-a', cloudId: 'cloud-1');
    final failure = _failure(
      target: target,
      payload: _payload(
        ownerTeacherId: 'teacher-a',
        subjectCloudId: 'cloud-1',
      ),
      currentUserId: 'teacher-a',
      ownedSubjects: <Subject>[target],
    );

    expect(failure, isNull);
  });

  test('signed-in teacher must reprint legacy sheets without owner tag', () {
    final target = _subject(ownerTeacherId: 'teacher-a');
    final failure = _failure(
      target: target,
      payload: _payload(),
      currentUserId: 'teacher-a',
      ownedSubjects: <Subject>[target],
    );

    expect(failure?.failureReason, 'REPRINT_REQUIRED');
    expect(failure?.message, contains('security update'));
  });

  test('signed-in teacher blocks when QR payload is missing', () {
    final target = _subject(ownerTeacherId: 'teacher-a');
    final missingQr = ScanSheetIdentity.ownershipFailure(
      targetSubject: target,
      qrPayload: null,
      currentUserId: 'teacher-a',
      ownedSubjects: <Subject>[target],
    );
    expect(missingQr?.failureReason, 'QR_REQUIRED');
  });

  test('legacy QR without sign-in still blocks foreign subjectId', () {
    final target = _subject();
    final failure = _failure(
      target: target,
      payload: _payload(subjectId: 'SUB-9999'),
      ownedSubjects: <Subject>[target],
    );

    expect(failure?.failureReason, 'WRONG_TEACHER');
    expect(failure?.message.toLowerCase(), contains('another teacher'));
  });

  test('blocks when cloud subject id does not match scanner subject', () {
    final target = _subject(cloudId: 'cloud-a');
    final failure = _failure(
      target: target,
      payload: _payload(
        ownerTeacherId: 'teacher-a',
        subjectCloudId: 'cloud-b',
      ),
      currentUserId: 'teacher-a',
      ownedSubjects: <Subject>[target],
    );

    expect(failure?.failureReason, 'WRONG_TEACHER');
    expect(failure?.message, contains('another exam'));
  });
}
