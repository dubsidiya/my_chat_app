import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class MessagesService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

  Future<List<Message>> fetchMessages(String chatId) async {
    final response = await http.get(Uri.parse('$baseUrl/messages/$chatId'));

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => Message.fromJson(json)).toList();
    } else {
      throw Exception('Ошибка при получении сообщений');
    }
  }

  Future<void> sendMessage(String userId, String chatId, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'chat_id': chatId,
        'content': content,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Ошибка при отправке сообщения');
    }
  }
}
