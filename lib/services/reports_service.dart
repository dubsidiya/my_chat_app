import 'dart:convert';
import 'dart:math';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import '../models/report.dart';
import '../models/monthly_salary_report.dart';
import 'storage_service.dart';

class ReportsService {
  final String baseUrl = ApiConfig.baseUrl;
  final Random _rnd = Random();
  static const int _idempotencyRandomMax = 1000000000;
  static const bool _enableIdempotencyHeaders =
      bool.fromEnvironment('ENABLE_IDEMPOTENCY_HEADERS', defaultValue: true);

  String _newIdempotencyKey(String scope) {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = _rnd.nextInt(_idempotencyRandomMax);
    return '$scope-$t-$r';
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
      return data.map((json) => Report.fromJson(json)).toList();
    } else if (response.statusCode == 403) {
      try {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Требуется приватный доступ');
      } catch (_) {
        throw Exception('Требуется приватный доступ');
      }
    } else {
      throw Exception('Не удалось загрузить отчеты: ${response.statusCode}');
    }
  }

  /// Список всех отчётов для бухгалтера/суперпользователя (кто сдал, фильтры).
  /// Параметры: dateFrom/dateTo — границы по дате отчёта, isLate — только поздние/только вовремя/null — все.
  Future<List<Report>> getAllReportsList({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? isLate,
  }) async {
    final headers = await _getAuthHeaders();
    final query = <String, String>{};
    if (dateFrom != null) query['date_from'] = _dateToIso(dateFrom);
    if (dateTo != null) query['date_to'] = _dateToIso(dateTo);
    if (isLate == true) query['is_late'] = 'true';
    if (isLate == false) query['is_late'] = 'false';

    final uri = Uri.parse('$baseUrl/reports/list').replace(queryParameters: query.isEmpty ? null : query);
    final response = await timedGet(
      uri,
      headers: headers,
      timeout: const Duration(seconds: 15),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Report.fromJson(json)).toList();
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось загрузить список отчётов');
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
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось загрузить отчет');
    }
  }

  // Создание отчета
  Future<Report> createReport({
    required DateTime reportDate,
    required String content,
  }) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('report-create');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/reports'),
      headers: headers,
      body: jsonEncode({
        'report_date': reportDate.toIso8601String().split('T')[0],
        'content': content,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return Report.fromJson(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось создать отчет');
    }
  }

  /// Создание отчета через конструктор (структурные slots)
  /// slots: [{ timeStart: "14:00", timeEnd: "16:00", students: [{studentId: 1, price: 2000.0}, ...]}]
  Future<Report> createReportStructured({
    required DateTime reportDate,
    required List<Map<String, dynamic>> slots,
  }) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('report-create-structured');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/reports'),
      headers: headers,
      body: jsonEncode({
        'report_date': reportDate.toIso8601String().split('T')[0],
        'slots': slots,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return Report.fromJson(data);
    }

    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось создать отчет');
  }

  // Обновление отчета
  Future<Report> updateReport({
    required int id,
    required DateTime reportDate,
    required String content,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await timedPut(
      Uri.parse('$baseUrl/reports/$id'),
      headers: headers,
      body: jsonEncode({
        'report_date': reportDate.toIso8601String().split('T')[0],
        'content': content,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return Report.fromJson(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось обновить отчет');
    }
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

    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось обновить отчет');
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
      try {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Требуется приватный доступ');
      } catch (_) {
        throw Exception('Требуется приватный доступ');
      }
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось загрузить отчёт по зарплате');
    }
  }

  // Удаление отчета
  Future<void> deleteReport(int id) async {
    final headers = await _getAuthHeaders();
    final response = await timedDelete(
      Uri.parse('$baseUrl/reports/$id'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить отчет');
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
    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось снять пометку «поздний отчёт»');
  }
}

