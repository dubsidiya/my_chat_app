import 'dart:convert';
import 'dart:typed_data';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';
import '../models/report_author_option.dart';
import '../models/teacher_schedule_heatmap.dart';
import '../models/teacher_schedule_overview.dart';
import '../models/teacher_placement_plan.dart';

class AdminService {
  final String baseUrl = ApiConfig.baseUrl;

  /// Сбросить пароль пользователя (только суперпользователь)
  Future<void> resetUserPassword(String username, String newPassword) async {
    final headers = await _getAuthHeaders();
    final response = await timedPost(
      Uri.parse('$baseUrl/admin/reset-user-password'),
      headers: headers,
      body: jsonEncode({'username': username.trim(), 'newPassword': newPassword}),
    );
    if (response.statusCode == 200) return;
    final body = _tryDecodeJson(utf8.decode(response.bodyBytes));
    throw Exception(body?['message'] ?? 'Ошибка сброса пароля (${response.statusCode})');
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    if (body.isEmpty) return null;
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>> exportAccountingJson({
    required String from, // YYYY-MM-DD
    required String to, // YYYY-MM-DD
    bool bankTransferOnly = false,
  }) async {
    final headers = await _getAuthHeaders();
    final bank = bankTransferOnly ? '&bank_transfer_only=true' : '';
    final uri = Uri.parse('$baseUrl/admin/accounting/export?from=$from&to=$to&format=json$bank');
    final response = await timedGet(uri, headers: headers);

    final bodyText = utf8.decode(response.bodyBytes);
    final body = _tryDecodeJson(bodyText);

    if (response.statusCode == 200) {
      if (body == null) {
        throw Exception('Сервер вернул не-JSON (возможно, 404/HTML). Проверь деплой бэкенда.');
      }
      return body;
    }

    if (body != null && body['message'] != null) {
      throw Exception('${body['message']} (HTTP ${response.statusCode})');
    }

    // Часто это 404 от прокси/необновленного сервера, отдающий HTML
    final snippet = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = snippet.length > 180 ? '${snippet.substring(0, 180)}…' : snippet;
    throw Exception('Не удалось получить выгрузку (HTTP ${response.statusCode}). Ответ: $short');
  }

  Future<String> exportAccountingCsv({
    required String from, // YYYY-MM-DD
    required String to, // YYYY-MM-DD
    bool bankTransferOnly = false,
  }) async {
    final headers = await _getAuthHeaders();
    final bank = bankTransferOnly ? '&bank_transfer_only=true' : '';
    final uri = Uri.parse('$baseUrl/admin/accounting/export?from=$from&to=$to&format=csv$bank');
    final response = await timedGet(uri, headers: headers);

    if (response.statusCode == 200) {
      return utf8.decode(response.bodyBytes);
    }

    try {
      final bodyText = utf8.decode(response.bodyBytes);
      final error = _tryDecodeJson(bodyText);
      if (error != null && error['message'] != null) {
        throw Exception('${error['message']} (HTTP ${response.statusCode})');
      }
    } catch (_) {}

    throw Exception('Не удалось получить CSV: ${response.statusCode}');
  }

  /// Красивая выписка для бухгалтерии в формате XLSX (Excel).
  /// Возвращает байты файла; экран сам решает, сохранить или предложить браузеру.
  Future<Uint8List> exportAccountingXlsxBytes({
    required String from, // YYYY-MM-DD
    required String to, // YYYY-MM-DD
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/admin/accounting/export-xlsx?from=$from&to=$to');
    final response = await timedGet(uri, headers: headers);

    if (response.statusCode == 200) {
      return Uint8List.fromList(response.bodyBytes);
    }

    try {
      final bodyText = utf8.decode(response.bodyBytes);
      final error = _tryDecodeJson(bodyText);
      if (error != null && error['message'] != null) {
        throw Exception('${error['message']} (HTTP ${response.statusCode})');
      }
    } catch (_) {}

    throw Exception('Не удалось получить Excel-выгрузку: ${response.statusCode}');
  }

  static String _dateToIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Преподаватели с занятиями в периоде (суперпользователь).
  Future<List<ReportAuthorOption>> getTeacherScheduleTeachers({
    required DateTime from,
    required DateTime to,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule/teachers?from=${_dateToIso(from)}&to=${_dateToIso(to)}',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 20));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return [];
      final list = decoded['teachers'];
      if (list is! List) return [];
      final out = <ReportAuthorOption>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          out.add(
            ReportAuthorOption.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        } catch (_) {}
      }
      return out;
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(
      _extractMessage(response, 'Не удалось загрузить преподавателей'),
    );
  }

  /// Теплокарта: день недели × время (суперпользователь).
  Future<TeacherScheduleHeatmap> getTeacherScheduleHeatmap({
    required DateTime from,
    required DateTime to,
    required int teacherId,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule?from=${_dateToIso(from)}&to=${_dateToIso(to)}&teacher_id=$teacherId',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 25));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return TeacherScheduleHeatmap.fromJson(decoded);
      }
      if (decoded is Map) {
        return TeacherScheduleHeatmap.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить график'));
  }

  /// Планировщик: куда поставить ребёнка по дням/времени (1–5 преподавателей, суперпользователь).
  Future<TeacherPlacementPlan> getTeacherPlacementPlan({
    required DateTime from,
    required DateTime to,
    required List<int> teacherIds,
  }) async {
    if (teacherIds.isEmpty) {
      throw Exception('Выберите хотя бы одного преподавателя');
    }
    if (teacherIds.length > 5) {
      throw Exception('Не более 5 преподавателей');
    }
    final headers = await _getAuthHeaders();
    final ids = teacherIds.join(',');
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule/placement?from=${_dateToIso(from)}&to=${_dateToIso(to)}&teacher_ids=$ids',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 40));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return TeacherPlacementPlan.fromJson(decoded);
      }
      if (decoded is Map) {
        return TeacherPlacementPlan.fromJson(decoded.cast<String, dynamic>());
      }
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить планировщик'));
  }

  /// Сводная теплокарта 1–5 преподавателей (суперпользователь).
  Future<TeacherScheduleOverview> getTeacherScheduleOverview({
    required DateTime from,
    required DateTime to,
    required List<int> teacherIds,
  }) async {
    if (teacherIds.isEmpty) {
      throw Exception('Выберите хотя бы одного преподавателя');
    }
    if (teacherIds.length > 5) {
      throw Exception('Не более 5 преподавателей');
    }
    final headers = await _getAuthHeaders();
    final ids = teacherIds.join(',');
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule/overview?from=${_dateToIso(from)}&to=${_dateToIso(to)}&teacher_ids=$ids',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 35));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return TeacherScheduleOverview.fromJson(decoded);
      }
      if (decoded is Map) {
        return TeacherScheduleOverview.fromJson(decoded.cast<String, dynamic>());
      }
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить сводный график'));
  }

  /// Сводка nagavisor1.0 (суперпользователь).
  Future<Map<String, dynamic>> getNagavisor({
    required int teacherId,
    required DateTime from,
    required DateTime to,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/nagavisor?teacher_id=$teacherId&from=${_dateToIso(from)}&to=${_dateToIso(to)}',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 45));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить карточку преподавателя'));
  }

  String _extractMessage(dynamic response, String fallback) {
    try {
      final status = response.statusCode as int;
      final body = utf8.decode(response.bodyBytes as List<int>);
      final err = _tryDecodeJson(body);
      if (err?['message'] != null) {
        return '${err!['message']} (HTTP $status)';
      }
      return '$fallback (HTTP $status)';
    } catch (_) {
      return fallback;
    }
  }
}

