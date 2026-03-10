import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/message.dart';

void main() {
  group('Message.fromJson', () {
    test('парсит минимальный текст сообщения', () {
      final json = {
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'Привет',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
      };
      final m = Message.fromJson(json);
      expect(m.id, '1');
      expect(m.chatId, 'c1');
      expect(m.userId, 'u1');
      expect(m.content, 'Привет');
      expect(m.senderEmail, 'a@b.ru');
      expect(m.createdAt, '2025-03-01T12:00:00Z');
      expect(m.messageType, 'text');
      expect(m.isRead, false);
      expect(m.isPinned, false);
      expect(m.isForwarded, false);
      expect(m.hasImage, false);
      expect(m.hasFile, false);
      expect(m.hasText, true);
      expect(m.status, MessageStatus.sent);
    });

    test('парсит is_read и delivered_at', () {
      final m = Message.fromJson({
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'x',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
        'is_read': true,
        'delivered_at': '2025-03-01T12:01:00Z',
      });
      expect(m.isRead, true);
      expect(m.status, MessageStatus.read);
    });

    test('status delivered когда delivered_at есть и is_read false', () {
      final m = Message.fromJson({
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'x',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
        'delivered_at': '2025-03-01T12:01:00Z',
      });
      expect(m.isRead, false);
      expect(m.status, MessageStatus.delivered);
    });

    test('is_read и is_pinned из числа 1', () {
      final m = Message.fromJson({
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'x',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
        'is_read': 1,
        'is_pinned': 1,
      });
      expect(m.isRead, true);
      expect(m.isPinned, true);
    });

    test('парсит edited_at и is_edited', () {
      final m = Message.fromJson({
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'x',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
        'edited_at': '2025-03-01T12:05:00Z',
      });
      expect(m.isEdited, true);
    });

    test('парсит вложение файла', () {
      final m = Message.fromJson({
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': '',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
        'file_url': 'https://example.com/file.pdf',
        'file_name': 'doc.pdf',
        'file_size': 1024,
        'file_mime': 'application/pdf',
      });
      expect(m.hasFile, true);
      expect(m.fileUrl, 'https://example.com/file.pdf');
      expect(m.fileName, 'doc.pdf');
      expect(m.fileSize, 1024);
    });

    test('toJson roundtrip', () {
      final json = {
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'Test',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
      };
      final m = Message.fromJson(json);
      final out = m.toJson();
      expect(out['id'], '1');
      expect(out['content'], 'Test');
      expect(out['chat_id'], 'c1');
    });

    test('reply_to_message вложенное сообщение', () {
      final m = Message.fromJson({
        'id': '2',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'Ответ',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T13:00:00Z',
        'reply_to_message_id': '1',
        'reply_to_message': {
          'id': '1',
          'chat_id': 'c1',
          'user_id': 'u2',
          'content': 'Вопрос',
          'sender_email': 'b@b.ru',
          'created_at': '2025-03-01T12:00:00Z',
        },
      });
      expect(m.replyToMessageId, '1');
      expect(m.replyToMessage, isNotNull);
      expect(m.replyToMessage!.content, 'Вопрос');
    });

    test('hasImage и isImageOnly', () {
      final m = Message.fromJson({
        'id': '1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': '',
        'sender_email': 'a@b.ru',
        'created_at': '2025-03-01T12:00:00Z',
        'image_url': 'https://example.com/img.jpg',
        'message_type': 'image',
      });
      expect(m.hasImage, true);
      expect(m.isImageOnly, true);
    });
  });

  group('MessageReaction.fromJson', () {
    test('парсит реакцию', () {
      final r = MessageReaction.fromJson({
        'id': 'r1',
        'message_id': 'm1',
        'user_id': 'u1',
        'reaction': '👍',
        'created_at': '2025-03-01T12:00:00Z',
        'user_email': 'u@mail.ru',
      });
      expect(r.id, 'r1');
      expect(r.reaction, '👍');
      expect(r.userEmail, 'u@mail.ru');
    });

    test('toJson roundtrip', () {
      final json = {
        'id': 'r1',
        'message_id': 'm1',
        'user_id': 'u1',
        'reaction': '❤️',
        'created_at': '2025-03-01T12:00:00Z',
        'user_email': 'u@mail.ru',
      };
      final r = MessageReaction.fromJson(json);
      final out = r.toJson();
      expect(out['id'], 'r1');
      expect(out['reaction'], '❤️');
      expect(out['user_email'], 'u@mail.ru');
    });
  });
}
