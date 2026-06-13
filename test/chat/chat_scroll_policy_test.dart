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

    test('не подгружает историю до завершения первичного скролла', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          didInitialOpenScrollToBottom: false,
          pixels: 0,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: true,
          didInitialOpenScrollToBottom: true,
          pixels: 0,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          didInitialOpenScrollToBottom: true,
          pixels: 100,
        ),
        isTrue,
      );
    });

    test('стабильность maxScrollExtent для остановки первичного скролла', () {
      expect(
        ChatScrollPolicy.isScrollExtentStable(
          previousMaxScrollExtent: null,
          currentMaxScrollExtent: 500,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.isScrollExtentStable(
          previousMaxScrollExtent: 500,
          currentMaxScrollExtent: 500.5,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.isScrollExtentStable(
          previousMaxScrollExtent: 500,
          currentMaxScrollExtent: 520,
        ),
        isFalse,
      );
    });

    test('shouldStopInitialScrollSettling и initial open helpers', () {
      expect(
        ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          shouldAutoScrollToBottom: true,
          messageCount: 3,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldMarkInitialScrollCompleteImmediately(
          shouldAutoScrollToBottom: true,
          messageCount: 0,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(isNearBottom: false),
        isFalse,
      );
    });

    test('shouldAbortInitialScrollSettling если пользователь ушёл от низа', () {
      expect(
        ChatScrollPolicy.shouldAbortInitialScrollSettling(
          attempt: 0,
          isNearBottom: false,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.shouldAbortInitialScrollSettling(
          attempt: 1,
          isNearBottom: false,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldAbortInitialScrollSettling(
          attempt: 1,
          isNearBottom: true,
        ),
        isFalse,
      );
    });
  });
}
