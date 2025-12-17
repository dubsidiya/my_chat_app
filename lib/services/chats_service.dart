import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat.dart';
import 'storage_service.dart';

class ChatsService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<Chat>> fetchChats(String userId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/chats/$userId'),
        headers: headers,
      );

      print('Fetch chats status: ${response.statusCode}');
      print('Fetch chats response: ${response.body}');

    if (response.statusCode == 200) {
        try {
      final List<dynamic> data = jsonDecode(response.body);
          print('Parsed ${data.length} chats');
          
          // Безопасный парсинг с обработкой ошибок
          final List<Chat> chats = [];
          for (var chatJson in data) {
            try {
              chats.add(Chat.fromJson(chatJson as Map<String, dynamic>));
            } catch (e) {
              print('Error parsing chat: $e');
              print('Chat JSON: $chatJson');
              // Пропускаем проблемный чат, но продолжаем обработку
            }
          }
          return chats;
        } catch (e) {
          print('Error decoding JSON: $e');
          throw Exception('Ошибка парсинга ответа сервера: $e');
        }
    } else {
        print('Error fetching chats: ${response.statusCode} - ${response.body}');
        throw Exception('Не удалось загрузить чаты: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in fetchChats: $e');
      rethrow;
    }
  }

  Future<Chat> createChat(String name, List<String> userIds) async {
    try {
      final url = Uri.parse('$baseUrl/chats');
      print('Creating chat at: $url');
      print('Request body: name=$name, userIds=$userIds');
      
      final headers = await _getAuthHeaders();
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'name': name,
          'userIds': userIds,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при создании чата');
        },
    );

      print('Create chat status: ${response.statusCode}');
      print('Create chat response: ${response.body}');

    if (response.statusCode == 201) {
        try {
          final responseData = jsonDecode(response.body);
          if (responseData is! Map<String, dynamic>) {
            throw Exception('Неверный формат ответа сервера: ожидается объект');
          }
          final chat = Chat.fromJson(responseData);
          print('Chat created successfully: ${chat.id} - ${chat.name}');
          return chat;
        } catch (e) {
          print('Error parsing created chat: $e');
          print('Response body: ${response.body}');
          throw Exception('Ошибка парсинга созданного чата: $e');
        }
      } else if (response.statusCode == 404) {
        print('ERROR: Endpoint not found. Check server routes.');
        print('Tried URL: $url');
        throw Exception('Эндпоинт не найден (404). Проверьте, что сервер обрабатывает POST /chats');
      } else {
        // Пытаемся распарсить сообщение об ошибке
        String errorMessage = 'Не удалось создать чат';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        print('Create chat error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in createChat: $e');
      throw Exception('Неожиданная ошибка при создании чата: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers(String excludeUserId) async {
    try {
      final url = Uri.parse('$baseUrl/auth/users');
      print('Fetching all users (excluding: $excludeUserId)');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при получении списка пользователей');
        },
      );

      print('Get users status: ${response.statusCode}');
      print('Get users response: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(response.body);
          // Фильтруем текущего пользователя
          final List<Map<String, dynamic>> users = [];
          for (var user in data) {
            if (user['id'].toString() != excludeUserId) {
              users.add({
                'id': user['id'].toString(),
                'email': user['email'] ?? '',
              });
            }
          }
          return users;
        } catch (e) {
          print('Error decoding users JSON: $e');
          throw Exception('Ошибка парсинга списка пользователей: $e');
        }
      } else {
        print('Error fetching users: ${response.statusCode} - ${response.body}');
        throw Exception('Не удалось получить список пользователей: ${response.statusCode}');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in getAllUsers: $e');
      throw Exception('Неожиданная ошибка при получении списка пользователей: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getChatMembers(String chatId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/members');
      print('Fetching chat members for chat: $chatId');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при получении участников чата');
        },
      );

      print('Get chat members status: ${response.statusCode}');
      print('Get chat members response: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(response.body);
          final List<Map<String, dynamic>> members = [];
          for (var user in data) {
            members.add({
              'id': user['id'].toString(),
              'email': user['email'] ?? '',
            });
          }
          return members;
        } catch (e) {
          print('Error decoding chat members JSON: $e');
          throw Exception('Ошибка парсинга участников чата: $e');
        }
      } else {
        print('Error fetching chat members: ${response.statusCode} - ${response.body}');
        throw Exception('Не удалось получить участников чата: ${response.statusCode}');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in getChatMembers: $e');
      throw Exception('Неожиданная ошибка при получении участников чата: $e');
    }
  }

  Future<void> addMembersToChat(String chatId, List<String> userIds) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/members');
      print('Adding members to chat: $chatId');
      print('User IDs: $userIds');
      
      final headers = await _getAuthHeaders();
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'userIds': userIds,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при добавлении участников');
        },
      );

      print('Add members status: ${response.statusCode}');
      print('Add members response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Members added successfully to chat: $chatId');
        return;
      } else if (response.statusCode == 404) {
        throw Exception('Чат не найден');
      } else {
        String errorMessage = 'Не удалось добавить участников';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        print('Add members error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in addMembersToChat: $e');
      throw Exception('Неожиданная ошибка при добавлении участников: $e');
    }
  }

  Future<void> removeMemberFromChat(String chatId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/members/$userId');
      print('Removing member from chat: $chatId, userId: $userId');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении участника');
        },
      );

      print('Remove member status: ${response.statusCode}');
      print('Remove member response: ${response.body}');

      if (response.statusCode == 200) {
        print('Member removed successfully from chat: $chatId');
        return;
      } else if (response.statusCode == 404) {
        throw Exception('Участник не найден в чате');
      } else {
        String errorMessage = 'Не удалось удалить участника';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        print('Remove member error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in removeMemberFromChat: $e');
      throw Exception('Неожиданная ошибка при удалении участника: $e');
    }
  }

  Future<void> deleteChat(String chatId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId');
      print('Deleting chat at: $url');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении чата');
        },
      );

      print('Delete chat status: ${response.statusCode}');
      print('Delete chat response: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('Chat deleted successfully: $chatId');
        return;
      } else if (response.statusCode == 403) {
        String errorMessage = 'Недостаточно прав для удаления чата';
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
        String errorMessage = 'Не удалось удалить чат';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        print('Delete chat error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in deleteChat: $e');
      throw Exception('Неожиданная ошибка при удалении чата: $e');
    }
  }

}

