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

    test('open_first_time: shouldAutoScrollToBottom=true', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollToBottom(
          didInitialOpenScrollToBottom: false,
          isNearBottom: false,
        ),
        isTrue,
      );
    });

    test('open_while_reading_history: reload без автоскролла', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(
          didInitialOpenScrollToBottom: true,
          isNearBottom: false,
        ),
        isFalse,
      );
    });

    test('open_load_more_blocked при pixels=0 до первичного скролла', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          didInitialOpenScrollToBottom: false,
          pixels: 0,
        ),
        isFalse,
      );
    });

    test('open_load_more_allowed у верха после первичного скролла', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          didInitialOpenScrollToBottom: true,
          pixels: 250,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: false,
          didInitialOpenScrollToBottom: true,
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

    test('incoming_near_bottom', () {
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(isNearBottom: true),
        isTrue,
      );
    });

    test('incoming_far_from_bottom', () {
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(isNearBottom: false),
        isFalse,
      );
    });

    test('settle_stop_on_stable_extent', () {
      expect(
        ChatScrollPolicy.shouldStopInitialScrollSettling(
          attempt: 2,
          maxAttempts: 24,
          previousMaxScrollExtent: 1500,
          currentMaxScrollExtent: 1500,
          isNearBottom: true,
        ),
        isTrue,
      );
    });

    test('settle_stop_on_max_attempts', () {
      expect(
        ChatScrollPolicy.shouldStopInitialScrollSettling(
          attempt: 24,
          maxAttempts: 24,
          previousMaxScrollExtent: 1000,
          currentMaxScrollExtent: 2000,
          isNearBottom: false,
        ),
        isTrue,
      );
    });

    test('empty_chat_open', () {
      expect(
        ChatScrollPolicy.shouldMarkInitialScrollCompleteImmediately(
          shouldAutoScrollToBottom: true,
          messageCount: 0,
        ),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          shouldAutoScrollToBottom: true,
          messageCount: 0,
        ),
        isFalse,
      );
    });

    test('loading_blocks_load_more', () {
      expect(
        ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
          isLoading: true,
          didInitialOpenScrollToBottom: true,
          pixels: 0,
        ),
        isFalse,
      );
    });

    test('refresh_near_bottom', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(
          didInitialOpenScrollToBottom: true,
          isNearBottom: true,
        ),
        isTrue,
      );
    });

    test('refresh_reading_history', () {
      expect(
        ChatScrollPolicy.shouldAutoScrollAfterReload(
          didInitialOpenScrollToBottom: true,
          isNearBottom: false,
        ),
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

    test('settle не останавливается слишком рано при растущем layout', () {
      expect(
        ChatScrollPolicy.shouldStopInitialScrollSettling(
          attempt: 2,
          maxAttempts: 24,
          previousMaxScrollExtent: 1000,
          currentMaxScrollExtent: 1300,
          isNearBottom: true,
        ),
        isFalse,
      );
    });

    test('settle не останавливается если не у низа даже при stable extent', () {
      expect(
        ChatScrollPolicy.shouldStopInitialScrollSettling(
          attempt: 5,
          maxAttempts: 24,
          previousMaxScrollExtent: 900,
          currentMaxScrollExtent: 900,
          isNearBottom: false,
        ),
        isFalse,
      );
    });
  });
}
