import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/chat.dart';
import '../models/chat_folder.dart';
import '../config/api_config.dart';
import 'storage_service.dart';

class ChatsService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      if (kDebugMode) {
        // ignore: avoid_print
        print('ChatsService: request without token');
      }
    }
    
    return headers;
  }

  Future<List<Chat>> fetchChats(String userId) async {
    try {
      final headers = await _getAuthHeaders();
      
      final response = await http.get(
        Uri.parse('$baseUrl/chats'),
        headers: headers,
      );

    if (response.statusCode == 200) {
        try {
      final List<dynamic> data = jsonDecode(response.body);
          
          // Безопасный парсинг с обработкой ошибок
          final List<Chat> chats = [];
          for (var chatJson in data) {
            try {
              chats.add(Chat.fromJson(chatJson as Map<String, dynamic>));
            } catch (e) {
              if (kDebugMode) {
                // ignore: avoid_print
                print('ChatsService: error parsing chat: $e');
              }
              // Пропускаем проблемный чат, но продолжаем обработку
            }
          }
          return chats;
        } catch (e) {
          throw Exception('Ошибка парсинга ответа сервера: $e');
        }
    } else {
        throw Exception('Не удалось загрузить чаты: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Chat> createChat(String name, List<String> userIds, {bool isGroup = false}) async {
    try {
      final url = Uri.parse('$baseUrl/chats');
      
      final headers = await _getAuthHeaders();
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'name': name,
          'userIds': userIds,
          'is_group': isGroup,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при создании чата');
        },
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          if (responseData is! Map<String, dynamic>) {
            throw Exception('Неверный формат ответа сервера: ожидается объект');
          }
          final chat = Chat.fromJson(responseData);
          return chat;
        } catch (e) {
          throw Exception('Ошибка парсинга созданного чата: $e');
        }
      } else if (response.statusCode == 404) {
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
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при создании чата: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers(String excludeUserId) async {
    try {
      final url = Uri.parse('$baseUrl/auth/users');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при получении списка пользователей');
        },
      );

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
          throw Exception('Ошибка парсинга списка пользователей: $e');
        }
      } else {
        throw Exception('Не удалось получить список пользователей: ${response.statusCode}');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при получении списка пользователей: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getChatMembers(String chatId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/members');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при получении участников чата');
        },
      );

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(response.body);
          final List<Map<String, dynamic>> members = [];
          for (var user in data) {
            members.add({
              'id': user['id'].toString(),
              'email': user['email'] ?? '',
              'display_name': user['display_name'],
              'displayName': user['displayName'] ?? user['display_name'] ?? user['email'] ?? '',
              'avatar_url': user['avatar_url'],
              'role': user['role'],
              'is_creator': user['is_creator'] == true || user['is_creator'] == 1,
            });
          }
          return members;
        } catch (e) {
          throw Exception('Ошибка парсинга участников чата: $e');
        }
      } else {
        throw Exception('Не удалось получить участников чата: ${response.statusCode}');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при получении участников чата: $e');
    }
  }

  Future<void> addMembersToChat(String chatId, List<String> userIds) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/members');
      
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

      if (response.statusCode == 200 || response.statusCode == 201) {
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
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при добавлении участников: $e');
    }
  }

  Future<void> removeMemberFromChat(String chatId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/members/$userId');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении участника');
        },
      );

      if (response.statusCode == 200) {
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
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при удалении участника: $e');
    }
  }

  Future<void> deleteChat(String chatId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении чата');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
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
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при удалении чата: $e');
    }
  }

  Future<void> leaveChat(String chatId) async {
    try {
      final url = Uri.parse('$baseUrl/chats/$chatId/leave');
      
      final headers = await _getAuthHeaders();
      final response = await http.post(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при выходе из чата');
        },
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 400) {
        String errorMessage = 'Не удалось выйти из чата';
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
        String errorMessage = 'Не удалось выйти из чата';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при выходе из чата: $e');
    }
  }

  // ✅ Создать инвайт в чат (owner/admin)
  Future<Map<String, dynamic>> createInvite(String chatId, {int? ttlMinutes, int? maxUses}) async {
    final headers = await _getAuthHeaders();
    final body = <String, dynamic>{};
    if (ttlMinutes != null) body['ttlMinutes'] = ttlMinutes;
    if (maxUses != null) body['maxUses'] = maxUses;

    final response = await http.post(
      Uri.parse('$baseUrl/chats/$chatId/invites'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String msg = 'Не удалось создать инвайт';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  // ✅ Вступить по коду
  Future<Map<String, dynamic>> joinByInviteCode(String code) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats/join'),
      headers: headers,
      body: jsonEncode({'code': code}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String msg = 'Не удалось вступить по коду';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  // ✅ Переименовать групповой чат (owner/admin)
  Future<Map<String, dynamic>> renameChat(String chatId, String name) async {
    final headers = await _getAuthHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/chats/$chatId/name'),
      headers: headers,
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    String msg = 'Не удалось переименовать чат';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  @Deprecated('Use setChatFolderId(folderId: ...) for custom folders')
  Future<String?> setChatFolder(String chatId, {String? folder}) async {
    await setChatFolderId(chatId, folderId: folder);
    return folder;
  }

  Future<List<ChatFolder>> fetchFolders() async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/chats/folders'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['folders'] as List<dynamic>? ?? []);
      return list.map((e) => ChatFolder.fromJson(e as Map<String, dynamic>)).toList();
    }
    String msg = 'Не удалось загрузить папки';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  Future<ChatFolder> createFolder(String name) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/chats/folders'),
      headers: headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return ChatFolder.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    String msg = 'Не удалось создать папку';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  Future<void> renameFolder(String folderId, String name) async {
    final headers = await _getAuthHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/chats/folders/$folderId'),
      headers: headers,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 200) return;
    String msg = 'Не удалось переименовать папку';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  Future<void> deleteFolder(String folderId) async {
    final headers = await _getAuthHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/chats/folders/$folderId'),
      headers: headers,
    );
    if (response.statusCode == 200) return;
    String msg = 'Не удалось удалить папку';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  Future<void> setChatFolderId(String chatId, {String? folderId}) async {
    final headers = await _getAuthHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/chats/$chatId/folder'),
      headers: headers,
      body: jsonEncode({'folderId': folderId}),
    );
    if (response.statusCode == 200) return;
    String msg = 'Не удалось обновить папку чата';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }
}

