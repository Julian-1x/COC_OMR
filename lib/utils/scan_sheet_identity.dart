import 'package:omr_app/models/exam_data.dart';

/// Result when a sheet fails teacher-ownership checks before grading.
class ScanSheetOwnershipFailure {
  const ScanSheetOwnershipFailure({
    required this.message,
    required this.failureReason,
  });

  final String message;
  final String failureReason;
}

/// Validates that a scanned sheet belongs to the signed-in teacher's account.
class ScanSheetIdentity {
  const ScanSheetIdentity._();

  static String? _sheetOwnerLabel(SubjectSheetQrPayload qrPayload) {
    final email = qrPayload.ownerTeacherEmail?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    final name = qrPayload.ownerTeacherName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return null;
  }

  static String? _currentTeacherLabel({
    String? currentTeacherEmail,
    String? currentTeacherName,
  }) {
    final email = currentTeacherEmail?.trim();
    if (email != null && email.isNotEmpty) {
      return email;
    }
    final name = currentTeacherName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return null;
  }

  static String wrongTeacherMessage({
    required SubjectSheetQrPayload qrPayload,
    String? currentTeacherEmail,
    String? currentTeacherName,
  }) {
    final sheetOwner = _sheetOwnerLabel(qrPayload);
    final you = _currentTeacherLabel(
      currentTeacherEmail: currentTeacherEmail,
      currentTeacherName: currentTeacherName,
    );
    final subject = qrPayload.subjectName.trim().isEmpty
        ? 'this exam'
        : qrPayload.subjectName.trim();
    final section = qrPayload.sectionName?.trim();
    final examLabel = (section != null && section.isNotEmpty)
        ? '$subject ($section)'
        : subject;

    if (sheetOwner != null && you != null) {
      return 'This sheet for $examLabel was printed by $sheetOwner. '
          'You are signed in as $you. '
          'Only $sheetOwner should scan this sheet.';
    }
    if (sheetOwner != null) {
      return 'This sheet for $examLabel was printed by $sheetOwner, '
          'not your account. Only that teacher should scan this sheet.';
    }
    if (you != null) {
      return 'This sheet for $examLabel was printed from another teacher\'s '
          'account. You are signed in as $you. '
          'Only scan sheets you printed from your own Prepare → Print Sheets.';
    }
    return 'This answer sheet was printed from another teacher\'s account. '
        'Only scan sheets you printed from your own Prepare → Print Sheets.';
  }

  static ScanSheetOwnershipFailure? ownershipFailure({
    required Subject targetSubject,
    SubjectSheetQrPayload? qrPayload,
    String? currentUserId,
    String? currentTeacherEmail,
    String? currentTeacherName,
    List<Subject>? ownedSubjects,
  }) {
    final trimmedUserId = currentUserId?.trim();
    final enforceTaggedSheets =
        trimmedUserId != null && trimmedUserId.isNotEmpty;

    if (qrPayload == null) {
      if (!enforceTaggedSheets) {
        return null;
      }
      return const ScanSheetOwnershipFailure(
        failureReason: 'QR_REQUIRED',
        message:
            'The sheet QR code could not be read. This sheet may have been '
            'printed before the security update. Reprint from Prepare → Print '
            'Sheets, then scan with the QR square fully visible in the frame.',
      );
    }

    if (!qrPayload.isCocIssued) {
      return const ScanSheetOwnershipFailure(
        failureReason: 'FOREIGN_SHEET',
        message:
            'This does not look like a COC OMR answer sheet. Print sheets '
            'from this app (Prepare → Print Sheets), then scan again.',
      );
    }

    final qrOwner = qrPayload.ownerTeacherId?.trim();

    if (enforceTaggedSheets) {
      if (qrOwner == null || qrOwner.isEmpty) {
        return const ScanSheetOwnershipFailure(
          failureReason: 'REPRINT_REQUIRED',
          message:
              'This answer sheet was printed before the security update. '
              'Reprint it from Prepare → Print Sheets on this phone, then scan '
              'the new copy.',
        );
      }

      if (qrOwner != trimmedUserId) {
        return ScanSheetOwnershipFailure(
          failureReason: 'WRONG_TEACHER',
          message: wrongTeacherMessage(
            qrPayload: qrPayload,
            currentTeacherEmail: currentTeacherEmail,
            currentTeacherName: currentTeacherName,
          ),
        );
      }
    } else if (qrOwner != null && qrOwner.isNotEmpty) {
      return ScanSheetOwnershipFailure(
        failureReason: 'WRONG_TEACHER',
        message: wrongTeacherMessage(
          qrPayload: qrPayload,
          currentTeacherEmail: currentTeacherEmail,
          currentTeacherName: currentTeacherName,
        ),
      );
    } else {
      final subjects = ownedSubjects ?? globalSubjects;
      final sheetSubjectId = qrPayload.subjectId.trim();
      if (sheetSubjectId.isNotEmpty) {
        final ownedLocally =
            subjects.any((subject) => subject.id == sheetSubjectId);
        if (!ownedLocally) {
          return ScanSheetOwnershipFailure(
            failureReason: 'WRONG_TEACHER',
            message: wrongTeacherMessage(
              qrPayload: qrPayload,
              currentTeacherEmail: currentTeacherEmail,
              currentTeacherName: currentTeacherName,
            ),
          );
        }
      } else {
        final resolved = qrPayload.resolveSubject();
        if (resolved == null && qrPayload.subjectName.trim().isNotEmpty) {
          return ScanSheetOwnershipFailure(
            failureReason: 'WRONG_TEACHER',
            message: wrongTeacherMessage(
              qrPayload: qrPayload,
              currentTeacherEmail: currentTeacherEmail,
              currentTeacherName: currentTeacherName,
            ),
          );
        }
      }
    }

    final qrCloudId = qrPayload.subjectCloudId?.trim();
    final targetCloudId = targetSubject.cloudId?.trim();
    if (qrCloudId != null &&
        qrCloudId.isNotEmpty &&
        targetCloudId != null &&
        targetCloudId.isNotEmpty &&
        qrCloudId != targetCloudId) {
      return const ScanSheetOwnershipFailure(
        failureReason: 'WRONG_TEACHER',
        message:
            'This answer sheet belongs to another exam. Open the correct '
            'answer key before scanning, or print new sheets from your '
            'Prepare → Print Sheets.',
      );
    }

    return null;
  }
}
