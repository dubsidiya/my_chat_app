import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Черновик конструктора отчёта (локально, по userId).
class ReportBuilderDraftStorage {
  static String _key(String userId) => 'report_builder_draft_v1_$userId';

  static Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String userId, Map<String, dynamic> draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), jsonEncode(draft));
    } catch (_) {}
  }
}
