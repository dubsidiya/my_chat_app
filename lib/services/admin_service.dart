import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

class AdminService {
  final String baseUrl = ApiConfig.baseUrl;

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
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/admin/accounting/export?from=$from&to=$to&format=json');
    final response = await http.get(uri, headers: headers);

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
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/admin/accounting/export?from=$from&to=$to&format=csv');
    final response = await http.get(uri, headers: headers);

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
}

