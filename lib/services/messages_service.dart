import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/message.dart';
import '../config/api_config.dart';
import 'storage_service.dart';
import 'local_messages_service.dart'; // ✅ Импорт сервиса кэширования

// Результат пагинации сообщений
class MessagesPaginationResult {
  final List<Message> messages;
  final bool hasMore;
  final int totalCount;
  final String? oldestMessageId;

  MessagesPaginationResult({
    required this.messages,
    required this.hasMore,
    required this.totalCount,
    this.oldestMessageId,
  });
}

class MessagesService {
  final String baseUrl = ApiConfig.baseUrl;

  /// Проверка доступа в интернет без сторонних SDK (для соответствия требованиям Apple privacy manifest).
  Future<bool> _isOnline() async {
    try {
      final uri = Uri.parse(baseUrl);
      await http.get(uri).timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    } else {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MessagesService: request without token');
      }
    }
    return headers;
  }

  Future<List<Message>> fetchMessages(String chatId) async {
    return fetchMessagesPaginated(chatId, limit: 50, offset: 0).then((result) => result.messages);
  }

  Future<MessagesPaginationResult> fetchMessagesPaginated(
    String chatId, {
    int limit = 50,
    int offset = 0,
    String? beforeMessageId,
    bool useCache = true, // ✅ Использовать кэш по умолчанию
  }) async {
    // ✅ Проверяем подключение к интернету (без сторонних плагинов — для соответствия Apple privacy manifest)
    final isOnline = await _isOnline();
    
    // ✅ Если есть кэш и мы офлайн, возвращаем из кэша
    if (!isOnline && useCache) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MessagesService: offline, using cache');
      }
      final cachedMessages = await LocalMessagesService.getMessages(chatId);
      return MessagesPaginationResult(
        messages: cachedMessages,
        hasMore: false,
        totalCount: cachedMessages.length,
        oldestMessageId: cachedMessages.isNotEmpty 
            ? cachedMessages.map((m) => int.parse(m.id)).reduce((a, b) => a < b ? a : b).toString()
            : null,
      );
    }
    
    try {
      final uri = Uri.parse('$baseUrl/messages/$chatId').replace(
        queryParameters: {
          'limit': limit.toString(),
          'offset': offset.toString(),
          if (beforeMessageId != null) 'before': beforeMessageId,
        },
      );

      final headers = await _getAuthHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        try {
          final dynamic decodedData = jsonDecode(response.body);
          
          // Поддержка старого формата (без пагинации) для обратной совместимости
          if (decodedData is Map<String, dynamic> && decodedData.containsKey('messages')) {
            // Новый формат с пагинацией
            final messagesData = decodedData['messages'] as List<dynamic>;
            final paginationData = decodedData['pagination'] as Map<String, dynamic>;
            
            final List<Message> messages = [];
            for (var msgJson in messagesData) {
              try {
                messages.add(Message.fromJson(msgJson as Map<String, dynamic>));
              } catch (e) {
                if (kDebugMode) {
                  // ignore: avoid_print
                  print('MessagesService: error parsing message: $e');
                }
              }
            }
            
            // ✅ Сохраняем сообщения в кэш только если useCache = true
            if (useCache && isOnline) {
              // Используем задержку, чтобы не триггерить перезагрузку UI
              Future.delayed(Duration(milliseconds: 100), () {
                LocalMessagesService.saveMessages(chatId, messages);
              });
            }
            
            return MessagesPaginationResult(
              messages: messages,
              hasMore: paginationData['hasMore'] ?? false,
              totalCount: paginationData['totalCount'] ?? messages.length,
              oldestMessageId: paginationData['oldestMessageId']?.toString(),
            );
          } else if (decodedData is List<dynamic>) {
            // Старый формат (массив сообщений)
            final List<dynamic> messagesData = decodedData;
            final List<Message> messages = [];
            for (var msgJson in messagesData) {
              try {
                messages.add(Message.fromJson(msgJson as Map<String, dynamic>));
              } catch (e) {
                if (kDebugMode) {
                  // ignore: avoid_print
                  print('MessagesService: error parsing message: $e');
                }
              }
            }
            
                   // ✅ Сохраняем сообщения в кэш
                   if (useCache && isOnline) {
                     await LocalMessagesService.saveMessages(chatId, messages);
                   }
                   
                   return MessagesPaginationResult(
                     messages: messages,
                     hasMore: false,
                     totalCount: messages.length,
                     oldestMessageId: null,
                   );
                 } else {
            // Неожиданный формат
            return MessagesPaginationResult(
              messages: [],
              hasMore: false,
              totalCount: 0,
              oldestMessageId: null,
            );
          }
        } catch (e) {
          throw Exception('Ошибка парсинга сообщений: $e');
        }
             } else {
               // ✅ Если ошибка сервера, пытаемся загрузить из кэша
               if (useCache) {
                 if (kDebugMode) {
                   // ignore: avoid_print
                   print('MessagesService: server error, trying cache');
                 }
                 final cachedMessages = await LocalMessagesService.getMessages(chatId);
                 if (cachedMessages.isNotEmpty) {
                   return MessagesPaginationResult(
                     messages: cachedMessages,
                     hasMore: false,
                     totalCount: cachedMessages.length,
                     oldestMessageId: cachedMessages.isNotEmpty 
                         ? cachedMessages.map((m) => int.parse(m.id)).reduce((a, b) => a < b ? a : b).toString()
                         : null,
                   );
                 }
               }
               throw Exception('Ошибка при получении сообщений: ${response.statusCode}');
             }
           } catch (e) {
             // ✅ Если ошибка сети, пытаемся загрузить из кэша
             if (useCache && e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
               if (kDebugMode) {
                 // ignore: avoid_print
                 print('MessagesService: network error, using cache');
               }
               final cachedMessages = await LocalMessagesService.getMessages(chatId);
               if (cachedMessages.isNotEmpty) {
                 return MessagesPaginationResult(
                   messages: cachedMessages,
                   hasMore: false,
                   totalCount: cachedMessages.length,
                   oldestMessageId: null,
                 );
               }
             }
             rethrow;
           }
         }

  Future<Message?> sendMessage(
    String chatId, 
    String content, {
    String? imageUrl, 
    String? originalImageUrl,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileMime,
    String? replyToMessageId, // ✅ ID сообщения, на которое отвечают
  }) async {
    // ✅ Проверяем подключение
    final isOnline = await _isOnline();
    
    if (!isOnline) {
      // ✅ В офлайн режиме создаем временное сообщение и сохраняем в кэш
      final tempMessage = Message(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        chatId: chatId,
        userId: '', // Будет заполнено после синхронизации
        content: content,
        imageUrl: imageUrl,
        originalImageUrl: originalImageUrl,
        messageType: imageUrl != null ? 'image' : 'text',
        senderEmail: '',
        createdAt: DateTime.now().toIso8601String(),
        isRead: false,
      );
      await LocalMessagesService.addMessage(chatId, tempMessage);
      throw Exception('Нет подключения к интернету. Сообщение сохранено локально и будет отправлено при восстановлении связи.');
    }
    
    final headers = await _getAuthHeaders();
    final body = jsonEncode({
      'chat_id': chatId,
      'content': content,
      'image_url': imageUrl,
      'original_image_url': originalImageUrl,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'file_mime': fileMime,
      'reply_to_message_id': replyToMessageId,
    });

    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: headers,
      body: body,
    );

    if (response.statusCode != 201) {
      String errorMessage = 'Ошибка при отправке сообщения';
      try {
        if (response.body.trim().startsWith('{')) {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? error['error'] ?? errorMessage;
        } else {
          errorMessage = response.body;
        }
      } catch (e) {
        errorMessage = 'Ошибка сервера (${response.statusCode}): ${response.body}';
      }
      throw Exception(errorMessage);
    }
    
    // ✅ После успешной отправки обновляем кэш
    try {
      final responseData = jsonDecode(response.body);
      
      final sentMessage = Message.fromJson(responseData);
      
      await LocalMessagesService.addMessage(chatId, sentMessage);
      
      // ✅ Возвращаем отправленное сообщение для возможного обновления UI
      return sentMessage;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MessagesService: error parsing sendMessage response: $e');
        // ignore: avoid_print
        print(stackTrace);
      }
      return null;
    }
  }

  // Загрузка изображения
  // [imageBytes] - сжатое изображение для отображения
  // [originalBytes] - оригинальное изображение (опционально, для сохранения оригинала)
  Future<String> uploadImage(List<int> imageBytes, String fileName, {List<int>? originalBytes}) async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Токен не найден');
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/messages/upload-image'),
      );

      // НЕ устанавливаем Content-Type вручную - multer сам установит правильный заголовок
      request.headers['Authorization'] = 'Bearer $token';
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: fileName,
        ),
      );
      
      // ✅ Если есть оригинал, отправляем его отдельно
      if (originalBytes != null) {
        // Генерируем имя для оригинала
        final originalFileName = 'original-${fileName}';
        request.files.add(
          http.MultipartFile.fromBytes(
            'original',
            originalBytes,
            filename: originalFileName,
          ),
        );
        if (kDebugMode) {
          // ignore: avoid_print
          print('Uploading original image: $originalFileName, size: ${originalBytes.length} bytes');
        }
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('Uploading image: $fileName, size: ${imageBytes.length} bytes');
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (kDebugMode) {
        // ignore: avoid_print
        print('Upload image status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        // Проверяем, что ответ действительно JSON
        if (response.body.trim().startsWith('<')) {
          throw Exception('Сервер вернул HTML вместо JSON. Возможно, эндпоинт не найден или произошла ошибка на сервере.');
        }
        
        try {
          final data = jsonDecode(response.body);
          if (data['image_url'] != null) {
            // Сохраняем original_image_url, если есть (для будущего использования)
            if (data['original_image_url'] != null) {
              if (kDebugMode) {
                // ignore: avoid_print
                print('Original image URL returned');
              }
            }
            return data['image_url'] as String;
          } else {
            throw Exception('Сервер не вернул image_url');
          }
        } catch (e) {
          throw Exception('Ошибка парсинга ответа сервера: $e');
        }
      } else {
        // Пытаемся распарсить ошибку
        String errorMessage = 'Не удалось загрузить изображение (${response.statusCode})';
        try {
          if (response.body.trim().startsWith('{')) {
            final error = jsonDecode(response.body);
            errorMessage = error['message'] ?? errorMessage;
          } else {
            // Если это HTML, берем первые 200 символов
            errorMessage = 'Сервер вернул ошибку: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}';
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера: ${response.statusCode}';
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при загрузке изображения: $e');
    }
  }

  // Загрузка файла (attachment)
  Future<Map<String, dynamic>> uploadFile(List<int> fileBytes, String fileName) async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Токен не найден');
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/messages/upload-file'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        if (response.body.trim().startsWith('<')) {
          throw Exception('Сервер вернул HTML вместо JSON');
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      }

      String errorMessage = 'Не удалось загрузить файл (${response.statusCode})';
      try {
        if (response.body.trim().startsWith('{')) {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? errorMessage;
        }
      } catch (_) {}
      throw Exception(errorMessage);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Неожиданная ошибка при загрузке файла: $e');
    }
  }

  Future<void> deleteMessage(String messageId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/messages/message/$messageId?userId=$userId');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении сообщения');
        },
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 403) {
        String errorMessage = 'Недостаточно прав для удаления сообщения';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      } else if (response.statusCode == 404) {
        throw Exception('Сообщение не найдено');
      } else {
        String errorMessage = 'Не удалось удалить сообщение';
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
      throw Exception('Неожиданная ошибка при удалении сообщения: $e');
    }
  }

  // ✅ Отметить сообщение как прочитанное
  Future<void> markMessageAsRead(String messageId) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/messages/message/$messageId/read'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при отметке сообщения как прочитанного');
    }
  }

  // ✅ Отметить все сообщения в чате как прочитанные
  Future<void> markChatAsRead(String chatId) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/messages/chat/$chatId/read-all'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при отметке сообщений как прочитанных');
    }
  }

  // ✅ Редактирование сообщения
  Future<void> editMessage(String messageId, {String? content, String? imageUrl}) async {
    final headers = await _getAuthHeaders();
    final body = <String, dynamic>{};
    if (content != null) body['content'] = content;
    if (imageUrl != null) body['image_url'] = imageUrl;
    
    final response = await http.put(
      Uri.parse('$baseUrl/messages/message/$messageId'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при редактировании сообщения');
    }
  }

  // ✅ Переслать сообщение
  Future<void> forwardMessage(String messageId, List<String> toChatIds) async {
    final headers = await _getAuthHeaders();
    // ✅ Сервер требует content или image_url даже для пересылки
    // Отправляем пробел, так как пустая строка не проходит валидацию (!content = true для '')
    final body = jsonEncode({
      'forward_from_message_id': messageId,
      'forward_to_chat_ids': toChatIds,
      'chat_id': toChatIds.first, // Для совместимости
      'content': ' ', // Пробел для прохождения валидации сервера (не пустая строка)
    });
    
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: headers,
      body: body,
    );

    if (response.statusCode != 201) {
      String errorMessage = 'Ошибка при пересылке сообщения';
      try {
        if (response.body.trim().startsWith('{')) {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? error['error'] ?? errorMessage;
        } else {
          errorMessage = response.body;
        }
      } catch (e) {
        errorMessage = 'Ошибка сервера (${response.statusCode}): ${response.body}';
      }
      throw Exception(errorMessage);
    }
  }

  // ✅ Закрепить сообщение
  Future<void> pinMessage(String messageId) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/messages/message/$messageId/pin'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при закреплении сообщения');
    }
  }

  // ✅ Открепить сообщение
  Future<void> unpinMessage(String messageId) async {
    final headers = await _getAuthHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/message/$messageId/pin'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при откреплении сообщения');
    }
  }

  // ✅ Получить закрепленные сообщения
  Future<List<Message>> getPinnedMessages(String chatId) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/messages/chat/$chatId/pinned'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final messagesData = data['messages'] as List<dynamic>;
      return messagesData.map((json) => Message.fromJson(json as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Ошибка при получении закрепленных сообщений');
    }
  }

  // 🔎 Поиск сообщений в чате
  Future<List<Map<String, dynamic>>> searchMessages(String chatId, String query, {int limit = 20, String? before}) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/messages/chat/$chatId/search').replace(
      queryParameters: {
        'q': query,
        'limit': limit.toString(),
        if (before != null) 'before': before,
      },
    );
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = (data['results'] as List<dynamic>? ?? []);
      return list.map((e) => e as Map<String, dynamic>).toList();
    }
    throw Exception('Ошибка поиска: ${response.statusCode}');
  }

  // 🎯 Получить окно сообщений вокруг messageId
  Future<List<Message>> fetchMessagesAround(String chatId, String messageId, {int limit = 50}) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/messages/chat/$chatId/around/$messageId').replace(
      queryParameters: {
        'limit': limit.toString(),
      },
    );
    final response = await http.get(uri, headers: headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final messagesData = (data['messages'] as List<dynamic>? ?? []);
      return messagesData.map((json) => Message.fromJson(json as Map<String, dynamic>)).toList();
    }
    throw Exception('Ошибка загрузки контекста: ${response.statusCode}');
  }

  // ✅ Добавить реакцию
  Future<void> addReaction(String messageId, String reaction) async {
    final headers = await _getAuthHeaders();
    // ✅ Убеждаемся, что Content-Type установлен
    headers['Content-Type'] = 'application/json';
    
    final body = jsonEncode({
      'reaction': reaction,
    });
    
    final response = await http.post(
      Uri.parse('$baseUrl/messages/message/$messageId/reaction'),
      headers: headers,
      body: body,
    );

    if (response.statusCode != 200) {
      String errorMessage = 'Ошибка при добавлении реакции';
      try {
        if (response.body.trim().startsWith('{')) {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? error['error'] ?? errorMessage;
        } else {
          errorMessage = response.body;
        }
      } catch (e) {
        errorMessage = 'Ошибка сервера (${response.statusCode}): ${response.body}';
      }
      throw Exception(errorMessage);
    }
  }

  // ✅ Удалить реакцию
  Future<void> removeReaction(String messageId, String reaction) async {
    final headers = await _getAuthHeaders();
    // ✅ Убеждаемся, что Content-Type установлен
    headers['Content-Type'] = 'application/json';
    
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/message/$messageId/reaction'),
      headers: headers,
      body: jsonEncode({
        'reaction': reaction,
      }),
    );

    if (response.statusCode != 200) {
      String errorMessage = 'Ошибка при удалении реакции';
      try {
        if (response.body.trim().startsWith('{')) {
          final error = jsonDecode(response.body);
          errorMessage = error['message'] ?? errorMessage;
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  Future<void> clearChat(String chatId, String userId) async {
    try {
      final url = Uri.parse('$baseUrl/messages/$chatId?userId=$userId');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(url, headers: headers).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при очистке чата');
        },
      );

      if (response.statusCode == 200) {
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
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Неожиданная ошибка при очистке чата: $e');
    }
  }
}
