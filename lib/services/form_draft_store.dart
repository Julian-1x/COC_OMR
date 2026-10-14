import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny JSON draft store for mid-edit teacher forms (phone).
class FormDraftStore {
  FormDraftStore._();

  static Future<Map<String, dynamic>?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> save(String key, Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        ...json,
        'updatedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> clearPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Newest draft whose key starts with [prefix], if any.
  static Future<Map<String, dynamic>?> loadNewestWithPrefix(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? newest;
    DateTime? newestAt;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final draft = await load(key);
      if (draft == null) continue;
      final at = DateTime.tryParse(draft['updatedAt']?.toString() ?? '');
      if (newest == null ||
          (at != null && (newestAt == null || at.isAfter(newestAt)))) {
        newest = draft;
        newestAt = at;
      }
    }
    return newest;
  }
}
