import 'package:omr_app/services/form_draft_store.dart';

/// Draft keys + helpers for answer key / scan review / print / custom sheet.
class TeacherFormDrafts {
  TeacherFormDrafts._();

  static String answerKeyKey({String? subjectId, String? sectionsFingerprint}) {
    final id = (subjectId ?? 'new').trim();
    final sections = (sectionsFingerprint ?? '').trim();
    return 'answer_key_draft_v1_${id}_$sections';
  }

  static String scanReviewKey({
    required String subjectId,
    required String omrId,
    String? sheetId,
  }) {
    final sheet = (sheetId ?? 'nosheet').trim();
    return 'scan_review_draft_v1_${subjectId.trim()}_${omrId.trim()}_$sheet';
  }

  static const printSheetsKey = 'print_sheets_draft_v1';
  static const importPrefsKey = 'import_prefs_draft_v1';

  static String customSheetEditorKey({String? layoutId}) {
    final id = (layoutId ?? 'new').trim();
    return 'custom_sheet_editor_draft_v1_$id';
  }

  static Future<Map<String, dynamic>?> load(String key) =>
      FormDraftStore.load(key);

  static Future<void> save(String key, Map<String, dynamic> json) =>
      FormDraftStore.save(key, json);

  static Future<void> clear(String key) => FormDraftStore.clear(key);

  static Map<String, List<String>> encodeAnswerMap(Map<int, Set<String>> map) {
    final out = <String, List<String>>{};
    for (final entry in map.entries) {
      if (entry.value.isEmpty) continue;
      out['${entry.key}'] = entry.value.toList()..sort();
    }
    return out;
  }

  static Map<int, Set<String>> decodeAnswerMap(Object? raw) {
    final out = <int, Set<String>>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final q = int.tryParse(key.toString());
      if (q == null) return;
      if (value is List) {
        out[q] = value.map((e) => e.toString()).toSet();
      } else if (value is String && value.isNotEmpty) {
        out[q] = value.split(RegExp(r'[+,]')).map((e) => e.trim()).toSet();
      }
    });
    return out;
  }

  static Map<String, String> encodeStringIntMap(Map<int, String> map) {
    return {
      for (final e in map.entries)
        if (e.value.trim().isNotEmpty) '${e.key}': e.value,
    };
  }

  static Map<int, String> decodeStringIntMap(Object? raw) {
    final out = <int, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      final q = int.tryParse(key.toString());
      if (q == null) return;
      final text = value.toString().trim();
      if (text.isNotEmpty) out[q] = text;
    });
    return out;
  }
}
