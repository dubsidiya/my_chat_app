import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

class HttpService {
  final String baseUrl = ApiConfig.baseUrl;

  // Получение заголовков с токеном
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

  // GET запрос
  Future<http.Response> get(String endpoint, {bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
  }

  // POST запрос
  Future<http.Response> post(String endpoint, Map<String, dynamic> body, {bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  // PUT запрос
  Future<http.Response> put(String endpoint, Map<String, dynamic> body, {bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return await http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  // DELETE запрос
  Future<http.Response> delete(String endpoint, {Map<String, dynamic>? body, bool requireAuth = true}) async {
    final headers = await _getHeaders(includeAuth: requireAuth);
    return await http.delete(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
  }
}

