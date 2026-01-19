import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/report.dart';
import 'storage_service.dart';

class ReportsService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

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
    final response = await http.get(
      Uri.parse('$baseUrl/reports'),
      headers: headers,
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

  // Получение одного отчета
  Future<Report> getReport(int id) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
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
    final response = await http.post(
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

  // Обновление отчета
  Future<Report> updateReport({
    required int id,
    required DateTime reportDate,
    required String content,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await http.put(
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

  // Удаление отчета
  Future<void> deleteReport(int id) async {
    final headers = await _getAuthHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/reports/$id'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить отчет');
    }
  }
}

