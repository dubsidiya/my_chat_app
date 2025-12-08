import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class MessagesService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

  Future<List<Message>> fetchMessages(String chatId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/messages/$chatId'));

      print('Fetch messages status: ${response.statusCode}');
      print('Fetch messages response: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(response.body);
          
          // Безопасный парсинг с обработкой ошибок
          final List<Message> messages = [];
          for (var msgJson in data) {
            try {
              messages.add(Message.fromJson(msgJson as Map<String, dynamic>));
            } catch (e) {
              print('Error parsing message: $e');
              print('Message JSON: $msgJson');
              // Пропускаем проблемное сообщение, но продолжаем обработку
            }
          }
          return messages;
        } catch (e) {
          print('Error decoding messages JSON: $e');
          throw Exception('Ошибка парсинга сообщений: $e');
        }
      } else {
        print('Error fetching messages: ${response.statusCode} - ${response.body}');
        throw Exception('Ошибка при получении сообщений: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in fetchMessages: $e');
      rethrow;
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

  Future<void> clearChat(String chatId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/messages/$chatId?userId=$userId');
      print('Clearing chat: $chatId');
      
      final response = await http.delete(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при очистке чата');
        },
      );

      print('Clear chat status: ${response.statusCode}');
      print('Clear chat response: ${response.body}');

      if (response.statusCode == 200) {
        print('Chat cleared successfully: $chatId');
        return;
      } else if (response.statusCode == 403) {
        String errorMessage = 'Недостаточно прав для очистки чата';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      } else if (response.statusCode == 404) {
        throw Exception('Чат не найден');
      } else {
        String errorMessage = 'Не удалось очистить чат';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        print('Clear chat error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in clearChat: $e');
      throw Exception('Неожиданная ошибка при очистке чата: $e');
    }
  }
}
