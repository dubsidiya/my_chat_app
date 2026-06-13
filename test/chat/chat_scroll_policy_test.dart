import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

void main() {
  group('ChatScrollPolicy', () {
    test('stickToBottom=true -> автоскролл разрешён', () {
      expect(
        ChatScrollPolicy.shouldAutoScroll(stickToBottom: true),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldAutoScroll(stickToBottom: false),
        isFalse,
      );
    });

    test('после отклеивания от низа reload не скроллит', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(stickToBottom: false),
        isFalse,
      );
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

    test('не подгружает историю до завершения первичного открытия', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: false,
          pixels: 0,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: true,
          initialOpenComplete: true,
          pixels: 0,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 100,
        ),
        isTrue,
      );
    });

    test('reanchor при росте контента у низа', () {
      expect(
        ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
          stickToBottom: true,
          pixels: 865,
          maxScrollExtent: 1000,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
          stickToBottom: false,
          pixels: 850,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
    });

    test('initial open helpers', () {
      expect(
        ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          stickToBottom: true,
          messageCount: 3,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldMarkInitialOpenCompleteImmediately(
          messageCount: 0,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(stickToBottom: false),
        isFalse,
      );
    });
  });
}
