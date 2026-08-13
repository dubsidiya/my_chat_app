import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:hive_flutter/hive_flutter.dart';
import '../features/chat/message_cache_merge.dart';
import '../models/message.dart';

/// ✅ Сервис для локального кэширования сообщений
/// Использует Hive для быстрого доступа к данным
class LocalMessagesService {
  static const String _boxName = 'messages_cache';
  static Box? _box;
  static final Map<String, Future<void>> _chatLocks = {};
  static String _pendingUploadsKey(String chatId) =>
      'chat_${chatId}_pending_upload_drafts';

  static Future<T> _withChatLock<T>(
    String chatId,
    Future<T> Function() action,
  ) {
    final previous = _chatLocks[chatId] ?? Future<void>.value();
    final result = previous.catchError((_) {}).then((_) => action());
    _chatLocks[chatId] = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> _putChatMessages(
    String chatId,
    List<Message> messages,
  ) async {
    if (_box == null) await init();
    await _box!.put('chat_$chatId', messages.map((m) => m.toJson()).toList());
    await _box!.put(
      'chat_${chatId}_timestamp',
      DateTime.now().toIso8601String(),
    );
  }

  /// Инициализация Hive и открытие бокса
  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    if (kDebugMode) {
      // ignore: avoid_print
      print('LocalMessagesService: init OK');
    }
  }

  /// Сохранение страницы сообщений: merge по id, без затирания более старой истории.
  static Future<void> saveMessages(
    String chatId,
    List<Message> messages,
  ) async {
    if (_box == null) await init();
    if (messages.isEmpty) return;

    try {
      await _withChatLock(chatId, () async {
        final existing = await getMessages(chatId);
        final merged = mergeMessageCache(
          existing: existing,
          incoming: messages,
          evictMissingInWindow: true,
        );
        await _putChatMessages(chatId, merged);
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            'Cache merged: +${messages.length} → ${merged.length} messages for $chatId',
          );
        }
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache save error: $e');
      }
    }
  }

  /// Получение сообщений чата из кэша
  static Future<List<Message>> getMessages(String chatId) async {
    if (_box == null) await init();

    try {
      final messagesJson = _box!.get('chat_$chatId') as List?;
      if (messagesJson == null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('Cache empty for $chatId');
        }
        return [];
      }

      // ✅ Преобразуем Map<dynamic, dynamic> в Map<String, dynamic>
      final messages = messagesJson.map((json) {
        if (json is Map) {
          // Преобразуем все ключи и значения в правильные типы
          final Map<String, dynamic> messageMap = {};
          json.forEach((key, value) {
            messageMap[key.toString()] = value;
          });
          return Message.fromJson(messageMap);
        }
        return Message.fromJson(json as Map<String, dynamic>);
      }).toList();
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache loaded: ${messages.length} for $chatId');
      }
      return messages;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache load error: $e');
      }
      return [];
    }
  }

  /// Добавление одного сообщения в кэш
  static Future<void> addMessage(String chatId, Message message) async {
    if (_box == null) await init();

    try {
      await _withChatLock(chatId, () async {
        var existing = await getMessages(chatId);
        if (!message.id.startsWith('temp_')) {
          existing = existing.where((m) => !m.id.startsWith('temp_')).toList();
        }
        final merged = mergeMessageCache(
          existing: existing,
          incoming: [message],
        );
        await _putChatMessages(chatId, merged);
        if (kDebugMode) {
          // ignore: avoid_print
          print('Cache: message ${message.id} added/updated');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache add error: $e');
      }
    }
  }

  /// Удаление сообщения из кэша
  static Future<void> removeMessage(String chatId, String messageId) async {
    if (_box == null) await init();

    try {
      await _withChatLock(chatId, () async {
        final messages = await getMessages(chatId);
        messages.removeWhere((m) => m.id == messageId);
        await _putChatMessages(chatId, messages);
        if (kDebugMode) {
          // ignore: avoid_print
          print('Cache: message $messageId removed');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache remove error: $e');
      }
    }
  }

  /// Убрать из кэша все сообщения отправителя (после блокировки).
  static Future<void> removeMessagesFromUser(
    String chatId,
    String userId,
  ) async {
    if (_box == null) await init();
    final uid = userId.trim();
    if (uid.isEmpty) return;

    try {
      await _withChatLock(chatId, () async {
        final messages = await getMessages(chatId);
        messages.removeWhere((m) => m.userId == uid);
        await _putChatMessages(chatId, messages);
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache remove-by-user error: $e');
      }
    }
  }

  /// Обновление сообщения в кэше
  static Future<void> updateMessage(String chatId, Message message) async {
    if (_box == null) await init();

    try {
      await _withChatLock(chatId, () async {
        final existing = await getMessages(chatId);
        final merged = mergeMessageCache(
          existing: existing,
          incoming: [message],
        );
        await _putChatMessages(chatId, merged);
        if (kDebugMode) {
          // ignore: avoid_print
          print('Cache: message ${message.id} updated');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache update error: $e');
      }
    }
  }

  /// Очистка кэша чата
  static Future<void> clearChat(String chatId) async {
    if (_box == null) await init();

    try {
      await _withChatLock(chatId, () async {
        await _box!.delete('chat_$chatId');
        await _box!.delete('chat_${chatId}_timestamp');
        await _box!.delete(_pendingUploadsKey(chatId));
        if (kDebugMode) {
          // ignore: avoid_print
          print('Cache cleared for $chatId');
        }
      });
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache clear error: $e');
      }
    }
  }

  /// Получение времени последнего обновления кэша
  static Future<DateTime?> getLastUpdateTime(String chatId) async {
    if (_box == null) await init();

    try {
      final timestamp = _box!.get('chat_${chatId}_timestamp') as String?;
      if (timestamp != null) {
        return DateTime.parse(timestamp);
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache timestamp error: $e');
      }
    }
    return null;
  }

  /// Очистка всего кэша
  static Future<void> clearAll() async {
    if (_box == null) await init();

    try {
      await _box!.clear();
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache: all cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache clearAll error: $e');
      }
    }
  }

  /// Получение размера кэша (приблизительно)
  static Future<int> getCacheSize() async {
    if (_box == null) await init();

    try {
      return _box!.length;
    } catch (e) {
      return 0;
    }
  }

  /// Сохранить/обновить черновик отложенной отправки вложения.
  static Future<void> savePendingUploadDraft(
    String chatId,
    String tempId,
    Map<String, dynamic> draft,
  ) async {
    if (_box == null) await init();
    try {
      final key = _pendingUploadsKey(chatId);
      final raw = _box!.get(key);
      final Map<String, dynamic> drafts = {};
      if (raw is Map) {
        raw.forEach((k, v) => drafts[k.toString()] = v);
      }
      drafts[tempId] = draft;
      await _box!.put(key, drafts);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache pending draft save error: $e');
      }
    }
  }

  /// Получить все черновики отложенной отправки для чата.
  static Future<Map<String, Map<String, dynamic>>> getPendingUploadDrafts(
    String chatId,
  ) async {
    if (_box == null) await init();
    try {
      final key = _pendingUploadsKey(chatId);
      final raw = _box!.get(key);
      if (raw is! Map) return {};
      final result = <String, Map<String, dynamic>>{};
      raw.forEach((k, v) {
        if (v is Map) {
          final draft = <String, dynamic>{};
          v.forEach((dk, dv) => draft[dk.toString()] = dv);
          result[k.toString()] = draft;
        }
      });
      return result;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache pending drafts load error: $e');
      }
      return {};
    }
  }

  /// Удалить один черновик отложенной отправки.
  static Future<void> removePendingUploadDraft(
    String chatId,
    String tempId,
  ) async {
    if (_box == null) await init();
    try {
      final key = _pendingUploadsKey(chatId);
      final raw = _box!.get(key);
      if (raw is! Map) return;
      final drafts = <String, dynamic>{};
      raw.forEach((k, v) => drafts[k.toString()] = v);
      drafts.remove(tempId);
      if (drafts.isEmpty) {
        await _box!.delete(key);
      } else {
        await _box!.put(key, drafts);
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache pending draft remove error: $e');
      }
    }
  }

  /// Удалить все черновики отложенной отправки для чата.
  static Future<void> clearPendingUploadDrafts(String chatId) async {
    if (_box == null) await init();
    try {
      await _box!.delete(_pendingUploadsKey(chatId));
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Cache pending drafts clear error: $e');
      }
    }
  }
}
