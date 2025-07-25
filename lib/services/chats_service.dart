import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat.dart';

class ChatsService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

  Future<List<Chat>> fetchChats(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/chats/$userId'));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((chatJson) => Chat.fromJson(chatJson)).toList();
    } else {
      throw Exception('Не удалось загрузить чаты');
    }
  }

  Future<Chat> createChat(String name, List<String> userIds) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chats'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'userIds': userIds,
      }),
    );

    if (response.statusCode == 201) {
      return Chat.fromJson(jsonDecode(response.body));
    } else {
      print('Create chat response status: ${response.statusCode}');
      print('Create chat response body: ${response.body}');
      throw Exception('Не удалось создать чат');
    }
  }

}
