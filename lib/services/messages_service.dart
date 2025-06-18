import 'dart:convert';
import 'package:http/http.dart' as http;

class Message {
  final int id;
  final String content;
  final DateTime createdAt;
  final String senderEmail;

  Message({required this.id, required this.content, required this.createdAt, required this.senderEmail});

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
      senderEmail: json['sender_email'],
    );
  }
}

class MessagesService {
  final _baseUrl = 'https://my-server-chat.onrender.com';

  Future<List<Message>> fetchMessages() async {
    final response = await http.get(Uri.parse('$_baseUrl/messages'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Message.fromJson(json)).toList();
    } else {
      throw Exception('Ошибка при загрузке сообщений');
    }
  }

  Future<void> sendMessage(String userId, String content) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': int.parse(userId), 'content': content}),
    );

    if (response.statusCode != 201) {
      throw Exception('Ошибка при отправке сообщения');
    }
  }
}
