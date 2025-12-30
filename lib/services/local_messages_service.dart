import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';

/// ✅ Сервис для локального кэширования сообщений
/// Использует Hive для быстрого доступа к данным
class LocalMessagesService {
  static const String _boxName = 'messages_cache';
  static Box? _box;

  /// Инициализация Hive и открытие бокса
  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    print('✅ Локальное хранилище сообщений инициализировано');
  }

  /// Сохранение сообщений чата в кэш
  static Future<void> saveMessages(String chatId, List<Message> messages) async {
    if (_box == null) await init();
    
    try {
      // Сохраняем сообщения по ключу chatId
      final messagesJson = messages.map((m) => {
        'id': m.id,
        'chat_id': m.chatId,
        'user_id': m.userId,
        'content': m.content,
        'image_url': m.imageUrl,
        'original_image_url': m.originalImageUrl,
        'message_type': m.messageType,
        'sender_email': m.senderEmail,
        'created_at': m.createdAt,
        'delivered_at': m.deliveredAt,
        'edited_at': m.editedAt,
        'is_read': m.isRead,
        'read_at': m.readAt,
      }).toList();
      
      await _box!.put('chat_$chatId', messagesJson);
      await _box!.put('chat_${chatId}_timestamp', DateTime.now().toIso8601String());
      print('✅ Сохранено ${messages.length} сообщений для чата $chatId');
    } catch (e) {
      print('❌ Ошибка сохранения сообщений в кэш: $e');
    }
  }

  /// Получение сообщений чата из кэша
  static Future<List<Message>> getMessages(String chatId) async {
    if (_box == null) await init();
    
    try {
      final messagesJson = _box!.get('chat_$chatId') as List?;
      if (messagesJson == null) {
        print('⚠️ Кэш для чата $chatId пуст');
        return [];
      }
      
      final messages = messagesJson.map((json) => Message.fromJson(json as Map<String, dynamic>)).toList();
      print('✅ Загружено ${messages.length} сообщений из кэша для чата $chatId');
      return messages;
    } catch (e) {
      print('❌ Ошибка загрузки сообщений из кэша: $e');
      return [];
    }
  }

  /// Добавление одного сообщения в кэш
  static Future<void> addMessage(String chatId, Message message) async {
    if (_box == null) await init();
    
    try {
      final messages = await getMessages(chatId);
      
      // Проверяем, нет ли уже такого сообщения
      if (messages.any((m) => m.id == message.id)) {
        // Обновляем существующее сообщение
        final index = messages.indexWhere((m) => m.id == message.id);
        messages[index] = message;
      } else {
        // Добавляем новое сообщение
        messages.add(message);
      }
      
      // Сортируем по времени
      messages.sort((a, b) {
        try {
          final aTime = DateTime.parse(a.createdAt);
          final bTime = DateTime.parse(b.createdAt);
          return aTime.compareTo(bTime);
        } catch (e) {
          return 0;
        }
      });
      
      await saveMessages(chatId, messages);
    } catch (e) {
      print('❌ Ошибка добавления сообщения в кэш: $e');
    }
  }

  /// Удаление сообщения из кэша
  static Future<void> removeMessage(String chatId, String messageId) async {
    if (_box == null) await init();
    
    try {
      final messages = await getMessages(chatId);
      messages.removeWhere((m) => m.id == messageId);
      await saveMessages(chatId, messages);
      print('✅ Сообщение $messageId удалено из кэша');
    } catch (e) {
      print('❌ Ошибка удаления сообщения из кэша: $e');
    }
  }

  /// Обновление сообщения в кэше
  static Future<void> updateMessage(String chatId, Message message) async {
    if (_box == null) await init();
    
    try {
      final messages = await getMessages(chatId);
      final index = messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        messages[index] = message;
        await saveMessages(chatId, messages);
        print('✅ Сообщение ${message.id} обновлено в кэше');
      }
    } catch (e) {
      print('❌ Ошибка обновления сообщения в кэше: $e');
    }
  }

  /// Очистка кэша чата
  static Future<void> clearChat(String chatId) async {
    if (_box == null) await init();
    
    try {
      await _box!.delete('chat_$chatId');
      await _box!.delete('chat_${chatId}_timestamp');
      print('✅ Кэш чата $chatId очищен');
    } catch (e) {
      print('❌ Ошибка очистки кэша чата: $e');
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
      print('❌ Ошибка получения времени обновления: $e');
    }
    return null;
  }

  /// Очистка всего кэша
  static Future<void> clearAll() async {
    if (_box == null) await init();
    
    try {
      await _box!.clear();
      print('✅ Весь кэш сообщений очищен');
    } catch (e) {
      print('❌ Ошибка очистки кэша: $e');
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
}

