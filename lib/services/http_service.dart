import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

/// Обёртка над HTTP API с таймаутами. Используйте напрямую или через сервисы с [timedGet]/[timedPost] и т.д.
class HttpService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (includeAuth) {
      final token = await StorageService.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  Future<http.Response> get(String endpoint, {bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return timedGet(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body, {bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return timedPost(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> put(String endpoint, Map<String, dynamic> body, {bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return timedPut(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint, {Map<String, dynamic>? body, bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return timedDelete(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
  }
}
