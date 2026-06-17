import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

import 'fixtures/chat_scroll_scenarios.dart';

void main() {
  group('Chat scroll regression matrix', () {
    for (final scenario in chatScrollScenarioCatalog) {
      test('catalog contains ${scenario.id}', () {
        expect(scenario.description, isNotEmpty);
      });
    }

    test('open_first_time: stickToBottom=true -> scroll', () {
      expect(
        ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          stickToBottom: true,
          initialOpenComplete: false,
          messageCount: 5,
        ),
        isTrue,
      );
    });

    test('open_while_reading_history: reload без автоскролла', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(stickToBottom: false),
        isFalse,
      );
    });

    test('open_load_more_blocked при pixels=0 до первичного открытия', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: false,
          pixels: 0,
        ),
        isFalse,
      );
    });

    test('open_load_more_allowed у верха после первичного открытия', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 250,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          initialOpenComplete: true,
          pixels: 301,
        ),
        isFalse,
      );
    });

    test('prepend_preserve_viewport', () {
      expect(
        ChatScrollPolicy.preserveViewportAfterPrepend(
          currentScrollPosition: 120,
          maxScrollExtentBefore: 800,
          maxScrollExtentAfter: 1100,
        ),
        420,
      );
    });

    test('incoming_stuck_to_bottom', () {
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(stickToBottom: true),
        isTrue,
      );
    });

    test('incoming_reading_history', () {
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(stickToBottom: false),
        isFalse,
      );
    });

    test('empty_chat_open', () {
      expect(
        ChatScrollPolicy.shouldMarkInitialOpenCompleteImmediately(
          messageCount: 0,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          stickToBottom: true,
          initialOpenComplete: true,
          messageCount: 0,
        ),
        isFalse,
      );
    });

    test('loading_blocks_load_more', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: true,
          initialOpenComplete: true,
          pixels: 0,
        ),
        isFalse,
      );
    });

    test('refresh_near_bottom', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(stickToBottom: true),
        isTrue,
      );
    });

    test('refresh_reading_history', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(stickToBottom: false),
        isFalse,
      );
    });

    test('near-bottom границы порога 140px', () {
      const max = 2000.0;
      expect(
        ChatScrollPolicy.isNearBottom(
          pixels: max - 140,
          maxScrollExtent: max,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.isNearBottom(
          pixels: max - 141,
          maxScrollExtent: max,
        ),
        isFalse,
      );
    });

    test('reanchor only when stuck and near bottom', () {
      expect(
        ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
          stickToBottom: true,
          pixels: 1160,
          maxScrollExtent: 1300,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
          stickToBottom: false,
          pixels: 1000,
          maxScrollExtent: 1300,
        ),
        isFalse,
      );
    });
  });
}
