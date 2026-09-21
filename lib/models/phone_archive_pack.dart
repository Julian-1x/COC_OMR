import 'package:omr_app/models/exam_data.dart';

/// Soft-deleted roster/scores kept on the phone until uploaded to the web.
/// After a successful upload the pack is purged (frees storage). Offline restore
/// only works while the pack is still local.
class PhoneArchivePack {
  const PhoneArchivePack({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.omrIds,
    required this.sectionNames,
    required this.students,
    required this.scanResults,
    this.section,
  });

  static const String kindStudent = 'student';
  static const String kindSection = 'section';

  final String id;
  final String kind;
  final String title;
  final DateTime createdAt;
  final List<String> omrIds;
  final List<String> sectionNames;
  final List<Student> students;
  final List<ScanResult> scanResults;
  final Section? section;

  int get studentCount => students.length;
  int get scanCount => scanResults.length;

  String get subtitle {
    final scans = scanCount == 1 ? '1 score' : '$scanCount scores';
    if (kind == kindSection) {
      return 'Class · $studentCount student${studentCount == 1 ? '' : 's'} · $scans';
    }
    return 'Student · $scans · waiting to upload';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'omrIds': omrIds,
        'sectionNames': sectionNames,
        'students': students.map((s) => s.toJson()).toList(),
        'scanResults': scanResults.map(_scanForArchive).toList(),
        if (section != null) 'section': section!.toJson(),
      };

  factory PhoneArchivePack.fromJson(Map<String, dynamic> json) {
    final students = (json['students'] as List? ?? const [])
        .map((row) => Student.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    final scans = (json['scanResults'] as List? ?? const [])
        .map(
          (row) => ScanResult.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    final sectionJson = json['section'];
    return PhoneArchivePack(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? kindStudent,
      title: json['title']?.toString() ?? 'Archived item',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      omrIds: (json['omrIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      sectionNames: (json['sectionNames'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      students: students,
      scanResults: scans,
      section: sectionJson is Map
          ? Section.fromJson(Map<String, dynamic>.from(sectionJson))
          : null,
    );
  }

  /// Drop review photo paths — photos stay phone-only and eat storage.
  static Map<String, dynamic> _scanForArchive(ScanResult scan) {
    final json = scan.toJson();
    json['scannedImagePath'] = null;
    return json;
  }
}

class PhoneArchiveMoveSummary {
  const PhoneArchiveMoveSummary({
    required this.pack,
    required this.removedStudents,
    required this.removedScans,
    required this.removedReviewImages,
  });

  final PhoneArchivePack pack;
  final int removedStudents;
  final int removedScans;
  final int removedReviewImages;
}
