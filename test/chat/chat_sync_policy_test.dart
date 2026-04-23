import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_sync_policy.dart';

void main() {
  group('ChatSyncPolicy', () {
    test('offline -> online sync разрешен, если ранее не запускался', () {
      final allowed = ChatSyncPolicy.shouldRunReconnectSync(
        now: DateTime(2026, 1, 1, 10, 0, 0),
        lastRunAt: null,
      );

      expect(allowed, isTrue);
    });

    test('блокирует слишком частые sync после reconnect', () {
      final now = DateTime(2026, 1, 1, 10, 0, 8);
      final last = DateTime(2026, 1, 1, 10, 0, 0);
      final allowed = ChatSyncPolicy.shouldRunReconnectSync(
        now: now,
        lastRunAt: last,
      );

      expect(allowed, isFalse);
    });

    test('разрешает sync после cooldown', () {
      final now = DateTime(2026, 1, 1, 10, 0, 15);
      final last = DateTime(2026, 1, 1, 10, 0, 0);
      final allowed = ChatSyncPolicy.shouldRunReconnectSync(
        now: now,
        lastRunAt: last,
      );

      expect(allowed, isTrue);
    });
  });
}
