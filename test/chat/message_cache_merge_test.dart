import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/message_cache_merge.dart';
import 'package:my_chat_app/models/message.dart';

Message _msg({
  required String id,
  required String createdAt,
  String content = '',
  String userId = 'u1',
}) {
  return Message(
    id: id,
    chatId: 'c1',
    userId: userId,
    content: content,
    senderEmail: 'a@b.ru',
    createdAt: createdAt,
  );
}

void main() {
  group('mergeMessageCache', () {
    test('пустая входящая страница не затирает кэш', () {
      final existing = [
        _msg(id: '1', createdAt: '2026-01-01T10:00:00Z', content: 'old'),
      ];
      final merged = mergeMessageCache(existing: existing, incoming: const []);
      expect(merged, hasLength(1));
      expect(merged.single.content, 'old');
    });

    test('страница из 50 не выкидывает более старые id', () {
      final existing = [
        _msg(
          id: 'old-1',
          createdAt: '2026-01-01T09:00:00Z',
          content: 'history',
        ),
        _msg(id: '2', createdAt: '2026-01-01T10:00:00Z', content: 'stale'),
      ];
      final incoming = [
        _msg(id: '2', createdAt: '2026-01-01T10:00:00Z', content: 'fresh'),
        _msg(id: '3', createdAt: '2026-01-01T10:01:00Z', content: 'new'),
      ];
      final merged = mergeMessageCache(
        existing: existing,
        incoming: incoming,
        evictMissingInWindow: true,
      );
      expect(merged.map((m) => m.id).toList(), ['old-1', '2', '3']);
      expect(merged.firstWhere((m) => m.id == '2').content, 'fresh');
      expect(merged.firstWhere((m) => m.id == 'old-1').content, 'history');
    });

    test('удалённое в окне страницы не воскресает из кэша', () {
      final existing = [
        _msg(id: 'keep-old', createdAt: '2026-01-01T09:00:00Z'),
        _msg(id: 'deleted', createdAt: '2026-01-01T10:01:30Z'),
        _msg(id: '2', createdAt: '2026-01-01T10:01:00Z'),
      ];
      final incoming = [
        _msg(id: '2', createdAt: '2026-01-01T10:01:00Z'),
        _msg(id: '3', createdAt: '2026-01-01T10:02:00Z'),
      ];
      final merged = mergeMessageCache(
        existing: existing,
        incoming: incoming,
        evictMissingInWindow: true,
      );
      expect(merged.map((m) => m.id).toList(), ['keep-old', '2', '3']);
    });

    test('сообщение новее страницы переживает merge (гонка send vs fetch)', () {
      final existing = [
        _msg(id: '1', createdAt: '2026-01-01T10:00:00Z'),
        _msg(
          id: 'sent-now',
          createdAt: '2026-01-01T10:05:00Z',
          content: 'mine',
        ),
      ];
      final incoming = [_msg(id: '1', createdAt: '2026-01-01T10:00:00Z')];
      final merged = mergeMessageCache(
        existing: existing,
        incoming: incoming,
        evictMissingInWindow: true,
      );
      expect(merged.map((m) => m.id), containsAll(['1', 'sent-now']));
    });

    test('temp_ в окне страницы не выкидывается', () {
      final existing = [
        _msg(id: 'temp_abc', createdAt: '2026-01-01T10:00:30Z'),
        _msg(id: '2', createdAt: '2026-01-01T10:01:00Z'),
      ];
      final incoming = [_msg(id: '2', createdAt: '2026-01-01T10:01:00Z')];
      final merged = mergeMessageCache(
        existing: existing,
        incoming: incoming,
        evictMissingInWindow: true,
      );
      expect(merged.map((m) => m.id), contains('temp_abc'));
    });

    test('сортирует по created_at', () {
      final merged = mergeMessageCache(
        existing: [_msg(id: 'b', createdAt: '2026-01-01T11:00:00Z')],
        incoming: [_msg(id: 'a', createdAt: '2026-01-01T10:00:00Z')],
      );
      expect(merged.map((m) => m.id).toList(), ['a', 'b']);
    });
  });
}
