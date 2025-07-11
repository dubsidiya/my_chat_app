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
}
