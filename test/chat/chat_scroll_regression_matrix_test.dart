import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

import 'fixtures/chat_scroll_scenarios.dart';

void main() {
  group('Chat scroll regression matrix (reverse:true)', () {
    for (final scenario in chatScrollScenarioCatalog) {
      test('catalog contains ${scenario.id}', () {
        expect(scenario.description, isNotEmpty);
      });
    }

    test('open_at_bottom: открытие у низа = смещение 0', () {
      expect(ChatScrollPolicy.isAtBottom(pixels: 0), isTrue);
    });

    test('open_load_more_blocked: до первичного открытия не грузим', () {
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

    test('load_more_near_top: у верха грузим историю', () {
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 800,
          maxScrollExtent: 1000,
        ),
        isTrue,
      );
    });

    test('incoming_at_bottom: автоскролл только у низа', () {
      expect(ChatScrollPolicy.shouldAutoScrollOnIncoming(atBottom: true), isTrue);
    });

    test('incoming_reading_history: не дёргаем читающего историю', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollOnIncoming(atBottom: false),
        isFalse,
      );
    });

    test('loading_blocks_load_more: во время загрузки не грузим', () {
      expect(
        ChatScrollPolicy.shouldLoadMoreOnScroll(
          isLoading: true,
          initialOpenComplete: true,
          pixels: 1000,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
    });

    test('near-bottom граница порога', () {
      expect(ChatScrollPolicy.isAtBottom(pixels: 120, threshold: 120), isTrue);
      expect(ChatScrollPolicy.isAtBottom(pixels: 121, threshold: 120), isFalse);
    });
  });
}
