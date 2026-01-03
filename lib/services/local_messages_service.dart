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
      // ✅ Получаем сообщения напрямую из бокса, без преобразования в Message
      final messagesJson = _box!.get('chat_$chatId') as List?;
      List<Map<String, dynamic>> messages = [];
      
      if (messagesJson != null) {
        // Преобразуем в список Map, исключая временные сообщения
        messages = messagesJson.map((json) {
          if (json is Map) {
            final Map<String, dynamic> messageMap = {};
            json.forEach((key, value) {
              messageMap[key.toString()] = value;
            });
            return messageMap;
          }
          return json as Map<String, dynamic>;
        }).where((m) {
          final id = m['id']?.toString() ?? '';
          return !id.startsWith('temp_');
        }).toList();
      }
      
      // Проверяем, нет ли уже такого сообщения
      final existingIndex = messages.indexWhere((m) => m['id']?.toString() == message.id);
      if (existingIndex != -1) {
        // Обновляем существующее сообщение
        messages[existingIndex] = {
          'id': message.id,
          'chat_id': message.chatId,
          'user_id': message.userId,
          'content': message.content,
          'image_url': message.imageUrl,
          'original_image_url': message.originalImageUrl,
          'message_type': message.messageType,
          'sender_email': message.senderEmail,
          'created_at': message.createdAt,
          'delivered_at': message.deliveredAt,
          'edited_at': message.editedAt,
          'is_read': message.isRead,
          'read_at': message.readAt,
        };
      } else {
        // Добавляем новое сообщение
        messages.add({
          'id': message.id,
          'chat_id': message.chatId,
          'user_id': message.userId,
          'content': message.content,
          'image_url': message.imageUrl,
          'original_image_url': message.originalImageUrl,
          'message_type': message.messageType,
          'sender_email': message.senderEmail,
          'created_at': message.createdAt,
          'delivered_at': message.deliveredAt,
          'edited_at': message.editedAt,
          'is_read': message.isRead,
          'read_at': message.readAt,
        });
      }
      
      // Сортируем по времени
      messages.sort((a, b) {
        try {
          final aTime = DateTime.parse(a['created_at']?.toString() ?? '');
          final bTime = DateTime.parse(b['created_at']?.toString() ?? '');
          return aTime.compareTo(bTime);
        } catch (e) {
          return 0;
        }
      });
      
      await _box!.put('chat_$chatId', messages);
      await _box!.put('chat_${chatId}_timestamp', DateTime.now().toIso8601String());
      print('✅ Сообщение ${message.id} добавлено/обновлено в кэше');
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
      final messagesJson = _box!.get('chat_$chatId') as List?;
      if (messagesJson == null) {
        // Если кэша нет, просто добавляем сообщение
        await addMessage(chatId, message);
        return;
      }
      
      // Преобразуем в список Map
      final List<Map<String, dynamic>> messages = messagesJson.map((json) {
        if (json is Map) {
          final Map<String, dynamic> messageMap = {};
          json.forEach((key, value) {
            messageMap[key.toString()] = value;
          });
          return messageMap;
        }
        return json as Map<String, dynamic>;
      }).toList();
      
      // Находим и обновляем сообщение
      final index = messages.indexWhere((m) => m['id']?.toString() == message.id);
      if (index != -1) {
        // Обновляем сообщение напрямую в JSON
        messages[index] = {
          'id': message.id,
          'chat_id': message.chatId,
          'user_id': message.userId,
          'content': message.content,
          'image_url': message.imageUrl,
          'original_image_url': message.originalImageUrl,
          'message_type': message.messageType,
          'sender_email': message.senderEmail,
          'created_at': message.createdAt,
          'delivered_at': message.deliveredAt,
          'edited_at': message.editedAt,
          'is_read': message.isRead,
          'read_at': message.readAt,
        };
        
        await _box!.put('chat_$chatId', messages);
        await _box!.put('chat_${chatId}_timestamp', DateTime.now().toIso8601String());
        print('✅ Сообщение ${message.id} обновлено в кэше');
      } else {
        // Если сообщение не найдено, добавляем его
        await addMessage(chatId, message);
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

