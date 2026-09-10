import 'dart:convert';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import '../utils/idempotency_retry_store.dart';
import '../models/report.dart';
import '../models/report_author_option.dart';
import '../models/monthly_salary_report.dart';
import '../models/report_audit_event.dart';
import 'storage_service.dart';

class ReportsService {
  final String baseUrl = ApiConfig.baseUrl;
  static const bool _enableIdempotencyHeaders =
      bool.fromEnvironment('ENABLE_IDEMPOTENCY_HEADERS', defaultValue: true);

  void _putIdempotencyHeader(
    Map<String, String> headers, {
    required String scope,
    required String fingerprint,
  }) {
    if (!_enableIdempotencyHeaders) return;
    headers['Idempotency-Key'] =
        IdempotencyRetryStore.keyFor(scope: scope, fingerprint: fingerprint);
  }

  void _completeIdempotency({required String scope, required String fingerprint}) {
    if (!_enableIdempotencyHeaders) return;
    IdempotencyRetryStore.complete(scope: scope, fingerprint: fingerprint);
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  String _extractErrorMessage(String body, String fallback) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        final msg = decoded['message'].toString().trim();
        if (msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    final plain = body.trim();
    if (plain.isNotEmpty) return '$fallback: $plain';
    return fallback;
  }

  // Получение всех отчетов
  Future<List<Report>> getAllReports() async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/reports'),
      headers: headers,
      timeout: const Duration(seconds: 15),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return _parseReportRows(data);
    } else if (response.statusCode == 403) {
      throw Exception(
        _extractErrorMessage(response.body, 'Требуется приватный доступ'),
      );
    } else {
      throw Exception(
        _extractErrorMessage(response.body, 'Не удалось загрузить отчеты'),
      );
    }
  }

  /// Разбор списка отчётов: одна битая строка не должна ронять весь список
  /// (как это уже делает getReportAuthors) — пропускаем непарсящиеся элементы.
  List<Report> _parseReportRows(List<dynamic> data) {
    final out = <Report>[];
    for (final item in data) {
      if (item is! Map) continue;
      try {
        out.add(Report.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        /* skip malformed row */
      }
    }
    return out;
  }

  /// Авторы отчётов для фильтра по преподавателю (суперпользователь).
  Future<List<ReportAuthorOption>> getReportAuthors({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final headers = await _getAuthHeaders();
    final query = <String, String>{};
    if (dateFrom != null) query['date_from'] = _dateToIso(dateFrom);
    if (dateTo != null) query['date_to'] = _dateToIso(dateTo);
    final uri = Uri.parse('$baseUrl/reports/list/teachers')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await timedGet(
      uri,
      headers: headers,
      timeout: const Duration(seconds: 15),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return [];
      final out = <ReportAuthorOption>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(
            ReportAuthorOption.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        } catch (_) {
          /* skip malformed row */
        }
      }
      return out;
    }
    if (response.statusCode == 404) {
      throw Exception(
        'Сервер не поддерживает список преподавателей. Обновите backend (GET /reports/list/teachers).',
      );
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(
      _extractErrorMessage(response.body, 'Не удалось загрузить преподавателей'),
    );
  }

  /// Список всех отчётов для бухгалтера/суперпользователя (кто сдал, фильтры).
  /// Параметры: dateFrom/dateTo — границы по дате отчёта, isLate — только поздние/только вовремя/null — все.
  /// [createdBy] — id преподавателя; null — все.
  Future<List<Report>> getAllReportsList({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isLate,
    int? createdBy,
  }) async {
    final headers = await _getAuthHeaders();
    final query = <String, String>{};
    if (dateFrom != null) query['date_from'] = _dateToIso(dateFrom);
    if (dateTo != null) query['date_to'] = _dateToIso(dateTo);
    if (isLate == true) query['is_late'] = 'true';
    if (isLate == false) query['is_late'] = 'false';
    if (createdBy != null) query['created_by'] = createdBy.toString();

    final uri = Uri.parse('$baseUrl/reports/list').replace(queryParameters: query.isEmpty ? null : query);
    final response = await timedGet(
      uri,
      headers: headers,
      timeout: const Duration(seconds: 15),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return _parseReportRows(data);
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(
      _extractErrorMessage(response.body, 'Не удалось загрузить список отчётов'),
    );
  }

  static String _dateToIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Получение одного отчета
  Future<Report> getReport(int id) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/reports/$id'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Report.fromJson(data);
    } else {
      throw Exception(
        _extractErrorMessage(response.body, 'Не удалось загрузить отчет'),
      );
    }
  }

  /// Создание отчета через конструктор (структурные slots)
  /// slots: [{ timeStart: "14:00", timeEnd: "16:00", students: [{studentId: 1, price: 2000.0}, ...]}]
  Future<Report> createReportStructured({
    required DateTime reportDate,
    required List<Map<String, dynamic>> slots,
  }) async {
    final headers = await _getAuthHeaders();
    const scope = 'report-create-structured';
    final fingerprint = jsonEncode({
      'report_date': reportDate.toIso8601String().split('T')[0],
      'slots': slots,
    });
    _putIdempotencyHeader(headers, scope: scope, fingerprint: fingerprint);
    final response = await timedPost(
      Uri.parse('$baseUrl/reports'),
      headers: headers,
      body: jsonEncode({
        'report_date': reportDate.toIso8601String().split('T')[0],
        'slots': slots,
      }),
    );

    if (response.statusCode == 201) {
      _completeIdempotency(scope: scope, fingerprint: fingerprint);
      final data = jsonDecode(response.body);
      return Report.fromJson(data);
    }

    throw Exception(
      _extractErrorMessage(response.body, 'Не удалось создать отчет'),
    );
  }

  /// Обновление отчета через конструктор (структурные slots)
  Future<Report> updateReportStructured({
    required int id,
    required DateTime reportDate,
    required List<Map<String, dynamic>> slots,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await timedPut(
      Uri.parse('$baseUrl/reports/$id'),
      headers: headers,
      body: jsonEncode({
        'report_date': reportDate.toIso8601String().split('T')[0],
        'slots': slots,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Report.fromJson(data);
    }

    throw Exception(
      _extractErrorMessage(response.body, 'Не удалось обновить отчет'),
    );
  }

  /// Зарплата за месяц: 50% от дохода, поздние отчёты не входят в доход.
  /// [year] — год, [month] — 1–12.
  Future<MonthlySalaryReport> getMonthlySalaryReport(int year, int month) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/reports/salary').replace(queryParameters: {
        'year': year.toString(),
        'month': month.toString(),
      }),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return MonthlySalaryReport.fromJson(data);
    } else if (response.statusCode == 403) {
      throw Exception(
        _extractErrorMessage(response.body, 'Требуется приватный доступ'),
      );
    } else {
      throw Exception(
        _extractErrorMessage(response.body, 'Не удалось загрузить отчёт по зарплате'),
      );
    }
  }

  /// Журнал аудита по отчёту (события из audit_events).
  /// [serverMessage] — опциональный текст с сервера (например, если таблица audit_events не развёрнута).
  Future<({List<ReportAuditEvent> events, String? serverMessage})> getReportAudit(int reportId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/reports/$reportId/audit'),
      headers: headers,
      timeout: const Duration(seconds: 15),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _extractErrorMessage(response.body, 'Не удалось загрузить журнал'),
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['events'] as List<dynamic>? ?? [];
    final events = list
        .whereType<Map>()
        .map(
          (e) => ReportAuditEvent.fromJson(
            Map<String, dynamic>.from(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          ),
        )
        .toList();
    final msg = data['message']?.toString().trim();
    return (
      events: events,
      serverMessage: (msg != null && msg.isNotEmpty) ? msg : null,
    );
  }

  // Удаление отчета
  Future<void> deleteReport(int id) async {
    final headers = await _getAuthHeaders();
    final response = await timedDelete(
      Uri.parse('$baseUrl/reports/$id'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception(_deleteErrorMessage(response.statusCode, response.body));
    }
  }

  /// Отдельные сообщения по статусам, чтобы UI мог отличить «нет прав» от
  /// «уже удалён» и от сетевой ошибки (последнюю ловит networkErrorMessage).
  String _deleteErrorMessage(int statusCode, String body) {
    switch (statusCode) {
      case 401:
        return 'Сессия истекла. Войдите снова и повторите удаление.';
      case 403:
        return 'Недостаточно прав для удаления этого отчёта.';
      case 404:
        return 'Отчёт не найден — возможно, он уже удалён.';
      case 409:
        return _extractErrorMessage(
          body,
          'Отчёт нельзя удалить: есть связанные записи.',
        );
      default:
        return _extractErrorMessage(body, 'Не удалось удалить отчет');
    }
  }

  /// Снять пометку «поздний отчёт» (только суперпользователь). Отчёт начнёт учитываться в доходе/зарплате.
  Future<Report> setReportNotLate(int reportId) async {
    final headers = await _getAuthHeaders();
    final response = await timedPatch(
      Uri.parse('$baseUrl/reports/$reportId/set-not-late'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Report.fromJson(data);
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(
      _extractErrorMessage(response.body, 'Не удалось снять пометку «поздний отчёт»'),
    );
  }
}

