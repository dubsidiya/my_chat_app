import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

import 'helpers/chat_scroll_harness.dart';

ChatScrollHarnessState _harnessState(WidgetTester tester) {
  return tester.state<ChatScrollHarnessState>(find.byType(ChatScrollHarness));
}

Future<void> pumpUntilInitialOpenComplete(
  WidgetTester tester, {
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump();
    if (_harnessState(tester).initialOpenComplete) {
      return;
    }
  }
  fail('Initial open did not complete within $maxFrames frames');
}

void main() {
  group('Chat open scroll widget regression', () {
    testWidgets('открытие: скролл только после окончания loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: List<double>.filled(12, 120),
          ),
        ),
      );

      var state = _harnessState(tester);
      expect(state.isLoading, isTrue);
      expect(state.scrollController.hasClients, isFalse);

      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state = _harnessState(tester);
      expect(state.isLoading, isFalse);
      expect(state.initialOpenComplete, isTrue);
      expect(state.stickToBottom, isTrue);
      expect(state.isNearBottom, isTrue);
    });

    testWidgets('до первичного открытия load-more не вызывается при pixels=0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: [80, 80, 80, 80, 80],
          ),
        ),
      );

      final state = _harnessState(tester);
      state.showListWithoutInitialScroll();

      await tester.pumpAndSettle();
      expect(state.scrollController.position.pixels, 0);
      expect(state.loadMoreCalls, 0);
    });

    testWidgets('после первичного открытия load-more срабатывает у верха', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: List<double>.filled(12, 120),
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      expect(state.isNearBottom, isTrue);
      state.scrollController.jumpTo(0);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(state.loadMoreCalls, 1);
      expect(state.itemHeights.length, 14);
    });

    testWidgets('prepend сохраняет позицию при подгрузке с верха', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: List<double>.filled(12, 120),
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      final maxBefore = state.scrollController.position.maxScrollExtent;

      state.scrollController.jumpTo(0);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      final maxAfter = state.scrollController.position.maxScrollExtent;
      final expected = ChatScrollPolicy.preserveViewportAfterPrepend(
        currentScrollPosition: 0,
        maxScrollExtentBefore: maxBefore,
        maxScrollExtentAfter: maxAfter,
      );

      expect(state.scrollController.position.pixels, closeTo(expected, 1.0));
    });

    testWidgets('рост контента у низа: reanchor только при stickToBottom', (tester) async {
      expect(
        ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
          stickToBottom: true,
          pixels: 998,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
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
          pixels: 865,
          maxScrollExtent: 1000,
        ),
        isFalse,
      );
    });

    testWidgets('пустой чат завершает первичное открытие без скролла', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: [],
            hasMoreMessages: false,
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await tester.pumpAndSettle();

      expect(state.initialOpenComplete, isTrue);
      expect(state.scrollController.hasClients, isFalse);
      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('листание вверх отклеивает от низа и не сбрасывает вниз', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: List<double>.filled(12, 120),
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state.scrollController.jumpTo(0);
      state.simulateUserScrollUp();
      await tester.pump();
      await tester.pump();

      expect(state.stickToBottom, isFalse);
      expect(state.isNearBottom, isFalse);
      expect(
        state.scrollController.position.pixels,
        lessThan(state.scrollController.position.maxScrollExtent * 0.2),
      );
      expect(state.initialOpenComplete, isTrue);
    });

    testWidgets('stuck + рост контента у низа → reanchor к самому низу', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: List<double>.filled(12, 80),
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      expect(state.stickToBottom, isTrue);
      expect(state.isNearBottom, isTrue);

      // Последнее сообщение «выросло» (например, догрузилось фото) — без скролла
      // пользователя контент стал выше, и низ ушёл из вида.
      state.growItemAt(state.itemHeights.length - 1, 600);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.stickToBottom, isTrue);
      expect(state.isNearBottom, isTrue);
      expect(
        state.scrollController.position.pixels,
        closeTo(state.scrollController.position.maxScrollExtent, 2),
      );
    });

    testWidgets('reading history + рост контента у низа → НЕ дёргает вниз', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: List<double>.filled(12, 80),
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state.scrollController.jumpTo(0);
      state.simulateUserScrollUp();
      await tester.pump();

      state.growItemAt(state.itemHeights.length - 1, 600);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.stickToBottom, isFalse);
      expect(state.isNearBottom, isFalse);
      expect(state.scrollController.position.pixels, lessThan(200));
    });

    testWidgets('скролл во время loading — no-op (нет clients)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScrollHarness(autoStartOpen: false),
        ),
      );

      final state = _harnessState(tester);
      expect(
        ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          stickToBottom: true,
          initialOpenComplete: false,
          messageCount: state.itemHeights.length,
        ),
        isTrue,
      );
      expect(state.scrollController.hasClients, isFalse);
    });
  });

  group('Manual iPhone scroll scenarios (automated)', () {
    testWidgets('1. чат с фото сверху открывается у последних сообщений', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: [400, 80, 80, ...List<double>.filled(10, 80)],
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      expect(state.stickToBottom, isTrue);
      expect(state.isNearBottom, isTrue);
      expect(
        state.scrollController.position.pixels,
        closeTo(state.scrollController.position.maxScrollExtent, 2),
      );
    });

    testWidgets('2. листание вверх — фото догружается, позиция не сбрасывается вниз', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: [200, 80, 80, ...List<double>.filled(10, 80)],
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state.scrollController.jumpTo(0);
      state.simulateUserScrollUp();
      await tester.pump();

      state.growItemAt(0, 400);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.stickToBottom, isFalse);
      expect(state.isNearBottom, isFalse);
      expect(state.scrollController.position.pixels, lessThan(200));
    });

    testWidgets('3. E2EE reload при чтении истории не yank вниз', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: [400, ...List<double>.filled(11, 80)],
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state.scrollController.jumpTo(0);
      state.simulateUserScrollUp();
      await tester.pump();

      final pixelsBeforeReload = state.scrollController.position.pixels;
      await state.simulateE2eeReload();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.stickToBottom, isFalse);
      expect(state.scrollController.position.pixels, closeTo(pixelsBeforeReload, 5));
      expect(state.isNearBottom, isFalse);
    });

    testWidgets('4. после роста фото скролл остаётся интерактивным', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            initialItemHeights: [200, ...List<double>.filled(11, 80)],
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state.scrollController.jumpTo(0);
      state.simulateUserScrollUp();
      state.growItemAt(0, 400);
      await tester.pump();
      await tester.pump();

      final before = state.scrollController.position.pixels;
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pump();
      await tester.pump();

      expect(state.scrollController.position.pixels, greaterThan(before));
      expect(state.stickToBottom, isFalse);
    });
  });
}
