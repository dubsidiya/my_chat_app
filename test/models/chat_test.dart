import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/chat.dart';

void main() {
  group('Chat.fromJson', () {
    test('минимальный чат без last_message', () {
      final c = Chat.fromJson({
        'id': 'chat1',
        'name': 'Чат 1',
        'is_group': false,
      });
      expect(c.id, 'chat1');
      expect(c.name, 'Чат 1');
      expect(c.isGroup, false);
      expect(c.unreadCount, 0);
      expect(c.lastMessageId, isNull);
      expect(c.lastMessageText, isNull);
    });

    test('is_group из bool и из строки', () {
      expect(Chat.fromJson({'id': '1', 'name': 'x', 'is_group': true}).isGroup, true);
      expect(Chat.fromJson({'id': '1', 'name': 'x', 'is_group': 'true'}).isGroup, true);
      expect(Chat.fromJson({'id': '1', 'name': 'x', 'is_group': false}).isGroup, false);
    });

    test('unread_count парсится', () {
      final c = Chat.fromJson({
        'id': '1',
        'name': 'x',
        'is_group': false,
        'unread_count': 3,
      });
      expect(c.unreadCount, 3);
    });

    test('unread_count из строки парсится как число', () {
      final c = Chat.fromJson({
        'id': '1',
        'name': 'x',
        'is_group': false,
        'unread_count': '5',
      });
      expect(c.unreadCount, 5);
    });

    test('last_message вложенный объект', () {
      final c = Chat.fromJson({
        'id': '1',
        'name': 'x',
        'is_group': false,
        'last_message': {
          'id': 'msg1',
          'content': 'Последнее сообщение',
          'message_type': 'text',
          'created_at': '2025-03-01T14:00:00Z',
          'sender_email': 'b@b.ru',
        },
      });
      expect(c.lastMessageId, 'msg1');
      expect(c.lastMessageText, 'Последнее сообщение');
      expect(c.lastMessageAt, '2025-03-01T14:00:00Z');
    });

    test('folder_id и other_user_id', () {
      final c = Chat.fromJson({
        'id': '1',
        'name': 'x',
        'is_group': false,
        'folder_id': 'f1',
        'folder_name': 'Работа',
        'other_user_id': 'u2',
      });
      expect(c.folderId, 'f1');
      expect(c.folderName, 'Работа');
      expect(c.otherUserId, 'u2');
    });
  });
}
