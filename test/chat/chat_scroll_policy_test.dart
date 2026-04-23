import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

void main() {
  group('ChatScrollPolicy', () {
    test('вход в чат -> всегда автоскролл вниз при первом открытии', () {
      final shouldScroll = ChatScrollPolicy.shouldAutoScrollToBottom(
        didInitialOpenScrollToBottom: false,
        isNearBottom: false,
      );

      expect(shouldScroll, isTrue);
    });

    test('после первого открытия не скроллит, если пользователь далеко от низа', () {
      final shouldScroll = ChatScrollPolicy.shouldAutoScrollToBottom(
        didInitialOpenScrollToBottom: true,
        isNearBottom: false,
      );

      expect(shouldScroll, isFalse);
    });

    test('pagination вверх без скачков: сохраняется видимая позиция', () {
      final newPosition = ChatScrollPolicy.preserveViewportAfterPrepend(
        currentScrollPosition: 420,
        maxScrollExtentBefore: 1000,
        maxScrollExtentAfter: 1320,
      );

      expect(newPosition, 740);
    });

    test('корректно определяет near-bottom для порогового расстояния', () {
      expect(
        ChatScrollPolicy.isNearBottom(
          pixels: 860,
          maxScrollExtent: 1000,
          threshold: 140,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.isNearBottom(
          pixels: 700,
          maxScrollExtent: 1000,
          threshold: 140,
        ),
        isFalse,
      );
    });
  });
}
