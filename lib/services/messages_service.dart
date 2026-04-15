import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/message.dart';
import '../models/chat_media_item.dart';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';
import 'local_messages_service.dart';
import 'e2ee_service.dart';

/// Фрагмент текста только для текста уведомления FCM при E2EE (не хранится в БД как шифротекст).
const int _maxPushPreviewChars = 200;

String? _pushPreviewPlainForFcm(String originalPlain, String contentSent) {
  final t = originalPlain.trim();
  if (t.isEmpty) return null;
  if (contentSent == originalPlain) return null;
  if (t.length <= _maxPushPreviewChars) return t;
  return '${t.substring(0, _maxPushPreviewChars)}…';
}

/// Минимальный числовой id в списке (временные `temp_*` и прочие нечисловые id пропускаются).
String? _oldestNumericMessageId(List<Message> messages) {
  if (messages.isEmpty) return null;
  int? best;
  for (final m in messages) {
    final n = int.tryParse(m.id);
    if (n != null && (best == null || n < best)) best = n;
  }
  return best?.toString();
}

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

/// Результат загрузки сжатого и опционально оригинального изображения.
class UploadImageUrls {
  final String imageUrl;
  final String? imageStorageKey;
  final String? originalImageUrl;
  final String? originalImageStorageKey;
  const UploadImageUrls({
    required this.imageUrl,
    this.imageStorageKey,
    this.originalImageUrl,
    this.originalImageStorageKey,
  });
}

class MessagesService {
  final String baseUrl = ApiConfig.baseUrl;
  MessagesPaginationResult _buildPaginatedCacheResult(
    List<Message> decrypted, {
    required int limit,
    String? beforeMessageId,
  }) {
    final sorted = List<Message>.from(decrypted)
      ..sort((a, b) {
        final ai = int.tryParse(a.id);
        final bi = int.tryParse(b.id);
        if (ai != null && bi != null) return bi.compareTo(ai); // newest -> oldest
        return b.createdAt.compareTo(a.createdAt);
      });

    List<Message> source = sorted;
    final beforeNum = beforeMessageId == null ? null : int.tryParse(beforeMessageId);
    if (beforeNum != null) {
      source = sorted.where((m) {
        final n = int.tryParse(m.id);
        return n != null && n < beforeNum;
      }).toList();
    }

    final page = source.take(limit).toList();
    final hasMore = source.length > page.length;
    final chronological = page.reversed.toList();
    return MessagesPaginationResult(
      messages: chronological,
      hasMore: hasMore,
      totalCount: decrypted.length,
      oldestMessageId: _oldestNumericMessageId(chronological),
    );
  }


  static Uri connectivityProbeUri(String baseUrl) => Uri.parse('$baseUrl/healthz');

  static Future<Message> _decryptOne(String chatId, Message m) async {
    String content = m.content;
    if (E2eeService.isEncrypted(content)) {
      content = await E2eeService.decryptMessage(chatId, content, keyVersion: m.keyVersion);
      if (content == '[зашифровано]') {
        // Если ключ чата ещё не успел приехать (часто на web после reconnect),
        // делаем одну активную попытку запросить/дождаться ключ и расшифровать повторно.
        await E2eeService.requestChatKey(chatId, keyVersion: m.keyVersion);
        final ok = await E2eeService.waitForChatKeyFromServer(chatId, keyVersion: m.keyVersion);
        if (ok) {
          content = await E2eeService.decryptMessage(chatId, m.content, keyVersion: m.keyVersion);
        }
      }
    }
    Message? replyTo = m.replyToMessage;
    if (replyTo != null) {
      replyTo = await _decryptOne(chatId, replyTo);
    }
    return Message(
      id: m.id, chatId: m.chatId, userId: m.userId, content: content,
      imageUrl: m.imageUrl, originalImageUrl: m.originalImageUrl,
      fileUrl: m.fileUrl, fileName: m.fileName, fileSize: m.fileSize, fileMime: m.fileMime,
      messageType: m.messageType, senderEmail: m.senderEmail, senderAvatarUrl: m.senderAvatarUrl,
      createdAt: m.createdAt, deliveredAt: m.deliveredAt, editedAt: m.editedAt,
      isRead: m.isRead, readAt: m.readAt, replyToMessageId: m.replyToMessageId,
      replyToMessage: replyTo, isPinned: m.isPinned, reactions: m.reactions,
      isForwarded: m.isForwarded, originalChatName: m.originalChatName,
      keyVersion: m.keyVersion,
    );
  }

  static Future<List<Message>> _decryptMessages(String chatId, List<Message> messages) async {
    final result = <Message>[];
    for (final m in messages) {
      result.add(await _decryptOne(chatId, m));
    }
    return result;
  }

  /// Расшифровывает одно сообщение (включая replyToMessage) для отображения в UI.
  static Future<Message> decryptMessageForChat(String chatId, Message raw) async =>
      _decryptOne(chatId, raw);

  /// Проверка доступа в интернет без сторонних SDK (для соответствия требованиям Apple privacy manifest).
  Future<bool> _isOnline() async {
    try {
      final uri = connectivityProbeUri(baseUrl);
      await timedGet(uri, timeout: const Duration(seconds: 3));
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
    
    // ✅ Если есть кэш и мы офлайн, возвращаем из кэша (расшифровываем — в кэше хранится ciphertext)
    if (!isOnline && useCache) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MessagesService: offline, using cache');
      }
      final cachedMessages = await LocalMessagesService.getMessages(chatId);
      final decrypted = await _decryptMessages(chatId, cachedMessages);
      return _buildPaginatedCacheResult(
        decrypted,
        limit: limit,
        beforeMessageId: beforeMessageId,
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
      final response = await timedGet(uri, headers: headers);

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
            if (useCache && isOnline) {
              Future.delayed(const Duration(milliseconds: 100), () {
                LocalMessagesService.saveMessages(chatId, messages);
              });
            }
            final decrypted = await _decryptMessages(chatId, messages);
            return MessagesPaginationResult(
              messages: decrypted,
              hasMore: paginationData['hasMore'] ?? false,
              totalCount: paginationData['totalCount'] ?? decrypted.length,
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
            if (useCache && isOnline) {
              await LocalMessagesService.saveMessages(chatId, messages);
            }
            final decrypted = await _decryptMessages(chatId, messages);
            return MessagesPaginationResult(
              messages: decrypted,
              hasMore: false,
              totalCount: decrypted.length,
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
        // ✅ Если ошибка сервера, пытаемся загрузить из кэша (с расшифровкой E2EE, как при офлайне)
        if (useCache) {
          if (kDebugMode) {
            // ignore: avoid_print
            print('MessagesService: server error, trying cache');
          }
          final cachedMessages = await LocalMessagesService.getMessages(chatId);
          if (cachedMessages.isNotEmpty) {
            final decrypted = await _decryptMessages(chatId, cachedMessages);
            return _buildPaginatedCacheResult(
              decrypted,
              limit: limit,
              beforeMessageId: beforeMessageId,
            );
          }
        }
        throw Exception('Ошибка при получении сообщений: ${response.statusCode}');
      }
    } catch (e) {
      // ✅ Если ошибка сети, пытаемся загрузить из кэша
      final es = e.toString();
      final looksNet = es.contains('SocketException') ||
          es.contains('Failed host lookup') ||
          es.contains('TimeoutException');
      if (useCache && looksNet) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('MessagesService: network error, using cache');
        }
        final cachedMessages = await LocalMessagesService.getMessages(chatId);
        if (cachedMessages.isNotEmpty) {
          final decrypted = await _decryptMessages(chatId, cachedMessages);
          return _buildPaginatedCacheResult(
            decrypted,
            limit: limit,
            beforeMessageId: beforeMessageId,
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
    String? imageStorageKey,
    String? originalImageUrl,
    String? originalImageStorageKey,
    String? fileUrl,
    String? fileStorageKey,
    String? fileName,
    int? fileSize,
    String? fileMime,
    String? replyToMessageId, // ✅ ID сообщения, на которое отвечают
    String? forwardOriginalMessageId,
    String? forwardOriginalChatId,
    String? idempotencyKey,
  }) async {
    // Не блокируем отправку предварительной проверкой сети:
    // на iOS короткий probe может давать ложные офлайн-результаты.
    // Реальную доступность сети определяем по фактическому ответу POST ниже.
    final headers = await _getAuthHeaders();

    String contentToSend = content;
    try {
      if (content.isNotEmpty) {
        try {
          await E2eeService.ensureKeyPair();
        } catch (_) {}
        var encrypted = await E2eeService.encryptMessage(chatId, content);
        if (encrypted == null) {
          await E2eeService.requestChatKey(chatId);
          final obtained = await E2eeService.waitForChatKeyFromServer(chatId);
          if (obtained) {
            encrypted = await E2eeService.encryptMessage(chatId, content);
          }
        }
        if (encrypted == null) {
          throw Exception('E2EE ключ для чата пока недоступен (возможен лимит запросов 429). Подождите 10-20 секунд и повторите отправку.');
        }
        contentToSend = jsonEncode(encrypted);
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Ошибка E2EE при отправке: $e');
    }

    final bodyMap = <String, dynamic>{
      'chat_id': chatId,
      'content': contentToSend,
      'image_url': imageUrl,
      'image_storage_key': imageStorageKey,
      'original_image_url': originalImageUrl,
      'original_image_storage_key': originalImageStorageKey,
      'file_url': fileUrl,
      'file_storage_key': fileStorageKey,
      'file_name': fileName,
      'file_size': fileSize,
      'file_mime': fileMime,
      'reply_to_message_id': replyToMessageId,
    };
    if (forwardOriginalMessageId != null &&
        forwardOriginalMessageId.isNotEmpty &&
        forwardOriginalChatId != null &&
        forwardOriginalChatId.isNotEmpty) {
      bodyMap['forward_original_message_id'] = forwardOriginalMessageId;
      bodyMap['forward_original_chat_id'] = forwardOriginalChatId;
    }
    final previewForPush = _pushPreviewPlainForFcm(content, contentToSend);
    if (previewForPush != null) {
      bodyMap['push_preview'] = previewForPush;
    }
    final body = jsonEncode(bodyMap);

    final response = await timedPost(
      Uri.parse('$baseUrl/messages'),
      headers: {
        ...headers,
        if (idempotencyKey != null && idempotencyKey.isNotEmpty)
          'Idempotency-Key': idempotencyKey,
      },
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
      
      final rawMessage = Message.fromJson(responseData);
      await LocalMessagesService.addMessage(chatId, rawMessage);
      final sentMessage = await _decryptOne(chatId, rawMessage);
      return sentMessage;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('MessagesService: error parsing sendMessage response: $e');
        // ignore: avoid_print
        print(stackTrace);
      }
      // Не возвращаем null: иначе UI ставит сообщение в «очередь» и бесконечно ретраит.
      throw Exception(
        'Сообщение, скорее всего, уже на сервере, но ответ не удалось разобрать. '
        'Потяните чат для обновления. Технически: $e',
      );
    }
  }

  // Загрузка изображения. При [chatId] и наличии ключа — E2EE шифрование перед отправкой.
  Future<UploadImageUrls> uploadImageWithUrls(
    List<int> imageBytes,
    String fileName, {
    List<int>? originalBytes,
    String? chatId,
  }) async {
    final token = await StorageService.getToken();
    if (token == null) throw Exception('Токен не найден');

    List<int> bytesToSend = imageBytes;
    List<int>? originalToSend = originalBytes;
    String sendFileName = fileName;
    if (chatId != null) {
      final encrypted = await E2eeService.encryptBytes(chatId, Uint8List.fromList(imageBytes));
      if (encrypted != null) {
        bytesToSend = encrypted;
        // Имя в multipart оставляем как у исходного изображения (.jpg и т.д.): иначе multer
        // на сервере видит только расширение .e2ee и отвечает 400 «не изображение».
        // Шифрование — только в теле файла, не в суффиксе имени.
        sendFileName = fileName;
        if (originalBytes != null) {
          final encOrig = await E2eeService.encryptBytes(chatId, Uint8List.fromList(originalBytes));
          if (encOrig != null) originalToSend = encOrig;
        }
      }
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/messages/upload-image'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes('image', bytesToSend, filename: sendFileName),
      );
      if (originalToSend != null) {
        request.files.add(
          http.MultipartFile.fromBytes('original', originalToSend, filename: 'original-$sendFileName'),
        );
        if (kDebugMode) {
          // ignore: avoid_print
          print('Uploading original image: size: ${originalToSend.length} bytes');
        }
      }

      if (kDebugMode) {
        // ignore: avoid_print
        print('Uploading image: $fileName, size: ${imageBytes.length} bytes');
      }

      final response = await timedMultipart(request);

      if (kDebugMode) {
        // ignore: avoid_print
        print('Upload image status: ${response.statusCode}');
        if (response.statusCode != 200) {
          // ignore: avoid_print
          print('Upload image body: ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        if (response.body.trim().startsWith('<')) {
          throw Exception('Сервер вернул HTML вместо JSON. Возможно, эндпоинт не найден или произошла ошибка на сервере.');
        }

        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['image_url'] != null) {
            if (data['original_image_url'] != null && kDebugMode) {
              // ignore: avoid_print
              print('Original image URL returned');
            }
            return UploadImageUrls(
              imageUrl: data['image_url'] as String,
              imageStorageKey: data['image_storage_key']?.toString(),
              originalImageUrl: data['original_image_url'] as String?,
              originalImageStorageKey: data['original_image_storage_key']?.toString(),
            );
          }
          throw Exception('Сервер не вернул image_url');
        } catch (e) {
          throw Exception('Ошибка парсинга ответа сервера: $e');
        }
      } else {
        String errorMessage = 'Не удалось загрузить изображение (${response.statusCode})';
        try {
          if (response.body.trim().startsWith('{')) {
            final error = jsonDecode(response.body);
            errorMessage = error['message'] ?? errorMessage;
          } else {
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

  Future<String> uploadImage(List<int> imageBytes, String fileName, {List<int>? originalBytes, String? chatId}) async {
    final u = await uploadImageWithUrls(imageBytes, fileName, originalBytes: originalBytes, chatId: chatId);
    return u.imageUrl;
  }

  static const int _forwardDownloadMaxBytes = 40 * 1024 * 1024;

  static Future<Uint8List> _downloadUrlBytes(String url) async {
    final r = await timedGet(Uri.parse(url), timeout: const Duration(seconds: 120));
    if (r.statusCode != 200) {
      throw Exception('Не удалось скачать файл для пересылки: HTTP ${r.statusCode}');
    }
    if (r.bodyBytes.length > _forwardDownloadMaxBytes) {
      throw Exception('Вложение слишком большое для пересылки');
    }
    return Uint8List.fromList(r.bodyBytes);
  }

  static Future<Uint8List> _unwrapForwardImageBytes(
    String sourceChatId,
    Uint8List bytes,
    int keyVersion,
  ) async {
    if (!E2eeService.looksLikeEncryptedBytes(bytes)) {
      return bytes;
    }
    final d = await E2eeService.decryptBytes(sourceChatId, bytes, keyVersion: keyVersion);
    if (d == null) {
      throw Exception(
        'Не удалось расшифровать изображение для пересылки. Откройте исходный чат и дождитесь ключа.',
      );
    }
    return d;
  }

  static String _forwardImageStubName(String imageUrl) {
    try {
      final segs = Uri.parse(imageUrl).pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        var seg = segs.last.replaceAll(RegExp(r'\.e2ee$', caseSensitive: false), '');
        if (seg.contains('.') && seg.length <= 200) return seg;
      }
    } catch (_) {}
    return 'forward.jpg';
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

      final response = await timedMultipart(request);

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
      final response = await timedDelete(
        url,
        headers: headers,
        timeout: const Duration(seconds: 10),
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
    final response = await timedPost(
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
    final response = await timedPost(
      Uri.parse('$baseUrl/messages/chat/$chatId/read-all'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при отметке сообщений как прочитанных');
    }
  }

  // ✅ Редактирование сообщения. [chatId] нужен для E2EE — шифруем content перед отправкой.
  Future<void> editMessage(String messageId, {String? content, String? imageUrl, String? chatId}) async {
    final headers = await _getAuthHeaders();
    final body = <String, dynamic>{};
    if (content != null) {
      String contentToSend = content;
      if (chatId != null) {
        try {
          final encrypted = await E2eeService.encryptMessage(chatId, content);
          if (encrypted != null) contentToSend = jsonEncode(encrypted);
        } catch (_) {}
      }
      body['content'] = contentToSend;
    }
    if (imageUrl != null) body['image_url'] = imageUrl;

    final response = await timedPut(
      Uri.parse('$baseUrl/messages/message/$messageId'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при редактировании сообщения');
    }
  }

  // ✅ Переслать сообщение
  /// E2EE: расшифровка в [sourceChatId], затем для каждого целевого чата — обычная отправка
  /// (шифрование под ключ целевого чата). Сервер только сохраняет метаданные [message_forwards].
  static const int _maxForwardChats = 20;

  Future<void> forwardMessage(
    Message sourceMessage,
    String sourceChatId,
    List<String> toChatIds,
  ) async {
    if (toChatIds.isEmpty) return;
    final targets = toChatIds.length > _maxForwardChats
        ? toChatIds.sublist(0, _maxForwardChats)
        : List<String>.from(toChatIds);

    await E2eeService.ensureKeyPair();

    var plain = sourceMessage.content;
    final hadEncryptedText =
        plain.trim().isNotEmpty && E2eeService.isEncrypted(plain);
    if (hadEncryptedText) {
      plain = await E2eeService.decryptMessage(
        sourceChatId,
        plain,
        keyVersion: sourceMessage.keyVersion,
      );
      if (plain == '[зашифровано]') {
        throw Exception(
          'Не удалось переслать: сообщение не расшифровано в исходном чате. Откройте чат и дождитесь ключа, затем повторите.',
        );
      }
    }

    final hasImage =
        sourceMessage.imageUrl != null && sourceMessage.imageUrl!.trim().isNotEmpty;
    final hasMedia = hasImage ||
        (sourceMessage.fileUrl != null && sourceMessage.fileUrl!.trim().isNotEmpty);

    if (!hasMedia && plain.trim().isEmpty) {
      throw Exception('Не удалось переслать: пустой текст (и нет вложения)');
    }

    Uint8List? mainPlainBytes;
    Uint8List? origPlainBytes;
    var imagePayloadE2ee = false;

    if (hasImage) {
      final rawMain = await _downloadUrlBytes(sourceMessage.imageUrl!);
      imagePayloadE2ee = E2eeService.looksLikeEncryptedBytes(rawMain);
      mainPlainBytes = await _unwrapForwardImageBytes(
        sourceChatId,
        rawMain,
        sourceMessage.keyVersion,
      );

      final origUrl = sourceMessage.originalImageUrl?.trim();
      if (origUrl != null &&
          origUrl.isNotEmpty &&
          origUrl != sourceMessage.imageUrl!.trim()) {
        final rawOrig = await _downloadUrlBytes(origUrl);
        origPlainBytes = await _unwrapForwardImageBytes(
          sourceChatId,
          rawOrig,
          sourceMessage.keyVersion,
        );
      } else {
        origPlainBytes = null;
      }
    }

    for (final toId in targets) {
      String? outImage = sourceMessage.imageUrl;
      String? outOriginal = sourceMessage.originalImageUrl;

      if (hasImage && imagePayloadE2ee) {
        final stub = _forwardImageStubName(sourceMessage.imageUrl!);
        final existingTargetKey = await E2eeService.getChatKey(toId);
        if (existingTargetKey == null) {
          await E2eeService.requestChatKey(toId);
          final ok = await E2eeService.waitForChatKeyFromServer(toId);
          if (!ok) {
            throw Exception(
              'Нет ключа шифрования для чата $toId — не удалось переслать фото. Откройте этот чат или попробуйте позже.',
            );
          }
        }
        final urls = await uploadImageWithUrls(
          mainPlainBytes!.toList(),
          stub,
          originalBytes: origPlainBytes?.toList(),
          chatId: toId,
        );
        outImage = urls.imageUrl;
        outOriginal = urls.originalImageUrl;
      }

      final sent = await sendMessage(
        toId,
        plain,
        imageUrl: outImage,
        originalImageUrl: outOriginal,
        fileUrl: sourceMessage.fileUrl,
        fileName: sourceMessage.fileName,
        fileSize: sourceMessage.fileSize,
        fileMime: sourceMessage.fileMime,
        forwardOriginalMessageId: sourceMessage.id,
        forwardOriginalChatId: sourceChatId,
      );
      if (sent == null) {
        throw Exception(
          'Пересылка в чат $toId: сервер ответил успешно, но не удалось разобрать ответ. Проверьте чат вручную.',
        );
      }
    }
  }

  // ✅ Закрепить сообщение
  Future<void> pinMessage(String messageId) async {
    final headers = await _getAuthHeaders();
    final response = await timedPost(
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
    final response = await timedDelete(
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
    final response = await timedGet(
      Uri.parse('$baseUrl/messages/chat/$chatId/pinned'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final messagesData = data['messages'] as List<dynamic>;
      final list = messagesData.map((json) => Message.fromJson(json as Map<String, dynamic>)).toList();
      return _decryptMessages(chatId, list);
    } else {
      throw Exception('Ошибка при получении закрепленных сообщений');
    }
  }

  // 🔎 Поиск сообщений в чате. Сервер отдаёт последние сообщения с content; расшифровываем и фильтруем по query на клиенте (E2EE).
  Future<List<Map<String, dynamic>>> searchMessages(String chatId, String query, {int limit = 20, String? before}) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/messages/chat/$chatId/search').replace(
      queryParameters: {
        'q': query,
        'limit': '300',
        if (before != null) 'before': before,
      },
    );
    final response = await timedGet(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Ошибка поиска: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['results'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final queryTrimmed = query.trim();
    final queryLower = queryTrimmed.toLowerCase();
    final int takeLimit = limit > 0 ? limit : 30;
    final List<Map<String, dynamic>> out = [];
    for (final item in list) {
      final rawContent = (item['content'] ?? '').toString();
      final keyVersion = item['key_version'] is int
          ? item['key_version'] as int
          : int.tryParse((item['key_version'] ?? '').toString());
      String plain = rawContent;
      if (E2eeService.isEncrypted(rawContent)) {
        plain = await E2eeService.decryptMessage(chatId, rawContent, keyVersion: keyVersion);
      }
      if (queryTrimmed.isNotEmpty && !plain.toLowerCase().contains(queryLower)) continue;
      out.add(_searchResultToSnippet(item, plain, queryLower));
      if (out.length >= takeLimit) break;
    }
    return out;
  }

  static Map<String, dynamic> _searchResultToSnippet(Map<String, dynamic> item, String plainContent, String queryLower) {
    String snippet = plainContent;
    if (queryLower.isNotEmpty && plainContent.toLowerCase().contains(queryLower)) {
      final idx = plainContent.toLowerCase().indexOf(queryLower);
      final start = idx > 40 ? idx - 40 : 0;
      final end = (idx + queryLower.length + 40).clamp(0, plainContent.length);
      snippet =
          '${start > 0 ? '…' : ''}${plainContent.substring(start, end)}${end < plainContent.length ? '…' : ''}';
    } else if (plainContent.length > 120) {
      snippet = '${plainContent.substring(0, 120)}…';
    }
    return {
      'message_id': item['message_id'],
      'key_version': item['key_version'] ?? 1,
      'content_snippet': snippet,
      'message_type': item['message_type'],
      'image_url': item['image_url'],
      'created_at': item['created_at'],
      'sender_email': item['sender_email'],
      'is_read': item['is_read'] == true,
    };
  }

  // 🎯 Получить окно сообщений вокруг messageId
  Future<List<Message>> fetchMessagesAround(String chatId, String messageId, {int limit = 50}) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/messages/chat/$chatId/around/$messageId').replace(
      queryParameters: {
        'limit': limit.toString(),
      },
    );
    final response = await timedGet(uri, headers: headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final messagesData = (data['messages'] as List<dynamic>? ?? []);
      final list = messagesData.map((json) => Message.fromJson(json as Map<String, dynamic>)).toList();
      return _decryptMessages(chatId, list);
    }
    throw Exception('Ошибка загрузки контекста: ${response.statusCode}');
  }

  Future<List<ChatMediaItem>> fetchChatMedia(String chatId, {String? beforeMessageId, int limit = 60}) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/messages/chat/$chatId/media').replace(
      queryParameters: {
        'limit': limit.toString(),
        if (beforeMessageId != null && beforeMessageId.trim().isNotEmpty) 'before': beforeMessageId.trim(),
      },
    );
    final response = await timedGet(uri, headers: headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>? ?? []);
      return items.map((e) => ChatMediaItem.fromJson(e as Map<String, dynamic>)).toList();
    }
    String msg = 'Ошибка загрузки медиа';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) msg = data['message'];
    } catch (_) {}
    throw Exception('$msg (${response.statusCode})');
  }

  // ✅ Добавить реакцию
  Future<void> addReaction(String messageId, String reaction) async {
    final headers = await _getAuthHeaders();
    // ✅ Убеждаемся, что Content-Type установлен
    headers['Content-Type'] = 'application/json';
    
    final body = jsonEncode({
      'reaction': reaction,
    });
    
    final response = await timedPost(
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
    
    final response = await timedDelete(
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
      final response = await timedDelete(
        url,
        headers: headers,
        timeout: const Duration(seconds: 10),
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
