import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

class ModerationService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> reportMessage(String messageId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/moderation/report-message/$messageId'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Ошибка отправки жалобы');
    }
  }

  Future<void> blockUser(String userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/moderation/block-user'),
      headers: await _headers(),
      body: jsonEncode({'user_id': userId}),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['message'] ?? 'Ошибка блокировки');
    }
  }

  Future<List<String>> getBlockedUserIds() async {
    final response = await http.get(
      Uri.parse('$baseUrl/moderation/blocked-ids'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body);
    final list = data['blocked_ids'];
    if (list is! List) return [];
    return list.map((e) => e.toString()).toList();
  }
}
