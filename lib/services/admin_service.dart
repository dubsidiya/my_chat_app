import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class AdminService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

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

    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    if (response.statusCode == 200) {
      return (body as Map).cast<String, dynamic>();
    }

    if (body is Map && body['message'] != null) {
      throw Exception(body['message']);
    }
    throw Exception('Не удалось получить выгрузку: ${response.statusCode}');
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
      final error = jsonDecode(response.body);
      if (error is Map && error['message'] != null) {
        throw Exception(error['message']);
      }
    } catch (_) {}

    throw Exception('Не удалось получить CSV: ${response.statusCode}');
  }
}

