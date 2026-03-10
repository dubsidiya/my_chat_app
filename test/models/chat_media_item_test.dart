import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/chat_media_item.dart';

void main() {
  group('ChatMediaItem.fromJson', () {
    test('минимальные поля', () {
      final item = ChatMediaItem.fromJson({
        'id': 'm1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': 'Текст',
        'message_type': 'text',
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(item.id, 'm1');
      expect(item.chatId, 'c1');
      expect(item.content, 'Текст');
      expect(item.messageType, 'text');
      expect(item.isImage, false);
      expect(item.bestImageUrl, isNull);
    });

    test('image_url — isImage и bestImageUrl', () {
      final item = ChatMediaItem.fromJson({
        'id': 'm1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': '',
        'image_url': 'https://example.com/thumb.jpg',
        'message_type': 'image',
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(item.isImage, true);
      expect(item.bestImageUrl, 'https://example.com/thumb.jpg');
    });

    test('original_image_url приоритетнее image_url в bestImageUrl', () {
      final item = ChatMediaItem.fromJson({
        'id': 'm1',
        'chat_id': 'c1',
        'user_id': 'u1',
        'content': '',
        'image_url': 'https://example.com/thumb.jpg',
        'original_image_url': 'https://example.com/full.jpg',
        'message_type': 'image',
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(item.bestImageUrl, 'https://example.com/full.jpg');
    });

    test('isVideo по file_mime и по расширению имени', () {
      expect(
        ChatMediaItem.fromJson({
          'id': '1',
          'chat_id': 'c1',
          'user_id': 'u1',
          'content': '',
          'file_url': 'https://a.ru/v.mp4',
          'file_name': 'v.mp4',
          'message_type': 'file',
          'created_at': '2025-03-01T12:00:00Z',
        }).isVideo,
        true,
      );
      expect(
        ChatMediaItem.fromJson({
          'id': '1',
          'chat_id': 'c1',
          'user_id': 'u1',
          'content': '',
          'file_url': 'https://a.ru/v',
          'file_name': 'video.mov',
          'file_mime': 'video/mp4',
          'message_type': 'file',
          'created_at': '2025-03-01T12:00:00Z',
        }).isVideo,
        true,
      );
    });
  });
}
