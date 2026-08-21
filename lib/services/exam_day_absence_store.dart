import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local absences for one exam + section. Not synced to the cloud.
class ExamDayAbsenceStore {
  ExamDayAbsenceStore._();

  static final ExamDayAbsenceStore instance = ExamDayAbsenceStore._();

  static String storageKey({
    required String subjectId,
    required String sectionName,
  }) {
    final owner = ApiService.currentUserId ?? 'local';
    return 'exam_day_absent|$owner|$subjectId|${normalizeSectionName(sectionName)}';
  }

  Future<Set<String>> load({
    required String subjectId,
    required String sectionName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(
          storageKey(subjectId: subjectId, sectionName: sectionName),
        ) ??
        const <String>[];
    return values.toSet();
  }

  Future<void> setAbsent({
    required String subjectId,
    required String sectionName,
    required String omrId,
    required bool absent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = storageKey(subjectId: subjectId, sectionName: sectionName);
    final next = {...prefs.getStringList(key) ?? const <String>[]};
    if (absent) {
      next.add(omrId);
    } else {
      next.remove(omrId);
    }
    await prefs.setStringList(key, next.toList());
  }
}
