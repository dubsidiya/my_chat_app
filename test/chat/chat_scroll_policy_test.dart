import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

void main() {
  group('ChatScrollPolicy (reverse:true)', () {
    test('isAtBottom: низ — это малое смещение (reverse)', () {
      expect(ChatScrollPolicy.isAtBottom(pixels: 0), isTrue);
      expect(ChatScrollPolicy.isAtBottom(pixels: 100, threshold: 120), isTrue);
      expect(ChatScrollPolicy.isAtBottom(pixels: 200, threshold: 120), isFalse);
    });

    test('shouldLoadMoreOnScroll: только у верха и после первичного открытия', () {
      // У верха (в reverse это близко к maxScrollExtent) после открытия — грузим.
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 950,
          maxScrollExtent: 1000,
        ),
        isTrue,
      );
      // У низа (смещение 0) — не грузим.
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 0,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
    });

    test('shouldLoadMoreOnScroll: заблокировано при загрузке и до открытия', () {
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: true,
          initialOpenComplete: true,
          pixels: 1000,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: false,
          pixels: 1000,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
    });

    test('shouldLoadMoreOnScroll: порог 300px от верха', () {
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 700, // 300 до верха
          maxScrollExtent: 1000,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 699, // 301 до верха
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
    });

    test('shouldAutoScrollOnIncoming: только если пользователь у низа', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollOnIncoming(atBottom: true),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldAutoScrollOnIncoming(atBottom: false),
        isFalse,
      );
    });
  });
}
