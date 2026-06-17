import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  group('Chat open scroll (reverse:true) regression', () {
    testWidgets('открытие: чат сразу у низа (новые сообщения)', (tester) async {
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

      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      state = _harnessState(tester);
      expect(state.isLoading, isFalse);
      expect(state.initialOpenComplete, isTrue);
      expect(state.isAtBottom, isTrue);
      expect(state.scrollController.position.pixels, closeTo(0, 1));
    });

    testWidgets('до первичного открытия load-more не вызывается', (tester) async {
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

      // Даже у верха (в reverse это maxScrollExtent) до открытия — не грузим.
      if (state.scrollController.hasClients) {
        state.scrollController.jumpTo(
          state.scrollController.position.maxScrollExtent,
        );
      }
      await tester.pump();
      expect(state.loadMoreCalls, 0);
    });

    testWidgets('листание к старым (вверх) у верха вызывает load-more', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: List<double>.filled(12, 120),
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      expect(state.isAtBottom, isTrue);

      // Прокрутка к верху (в reverse — к maxScrollExtent = старые сообщения).
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent,
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(state.loadMoreCalls, 1);
      expect(state.itemHeights.length, 14);
    });

    testWidgets('догрузка истории сохраняет позицию (reverse, без математики)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: List<double>.filled(12, 120),
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent,
      );
      await tester.pump();
      final pixelsBefore = state.scrollController.position.pixels;

      await tester.pump();
      await tester.pumpAndSettle();

      // В reverse старые сообщения добавляются «выше» якоря-низа → смещение
      // (расстояние от низа) сохраняется без ручного пересчёта.
      expect(state.loadMoreCalls, 1);
      expect(state.scrollController.position.pixels, closeTo(pixelsBefore, 1.0));
    });

    testWidgets('новое сообщение у низа: остаёмся у низа, оно видно', (tester) async {
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
      expect(state.isAtBottom, isTrue);

      state.appendNewMessage(80);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(state.isAtBottom, isTrue);
      expect(state.scrollController.position.pixels, closeTo(0, 1));
      // Самое новое сообщение отрисовано.
      expect(find.text('message ${state.itemHeights.length - 1}'), findsOneWidget);
    });

    testWidgets('новое сообщение при чтении истории НЕ дёргает к низу', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: List<double>.filled(14, 120),
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      // Уходим вверх к истории.
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent,
      );
      await tester.pump();
      expect(state.isAtBottom, isFalse);

      state.appendNewMessage(80);
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      expect(state.isAtBottom, isFalse);
    });

    testWidgets('рост картинки у низа: без «пружины», остаёмся у низа', (tester) async {
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
      expect(state.isAtBottom, isTrue);

      // Самое новое сообщение (низ) «выросло» — догрузилось фото.
      state.growItemAt(state.itemHeights.length - 1, 600);
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      // В reverse низ зафиксирован на смещении 0 — никакой обратной связи/прыжков.
      expect(state.isAtBottom, isTrue);
      expect(state.scrollController.position.pixels, closeTo(0, 1));
    });

    testWidgets('рост картинки сверху при чтении истории не дёргает', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: [80, 80, 80, ...List<double>.filled(9, 80)],
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent,
      );
      await tester.pump();
      expect(state.isAtBottom, isFalse);

      // Самое старое сообщение (верх) выросло.
      state.growItemAt(0, 400);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.isAtBottom, isFalse);
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
      expect(find.text('empty'), findsOneWidget);
    });
  });

  group('Manual iPhone scroll scenarios (reverse, automated)', () {
    testWidgets('1. чат с фото открывается у последних сообщений', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            autoStartOpen: false,
            // фото среди старых сверху; новые короткие снизу
            initialItemHeights: [400, 80, 80, ...List<double>.filled(10, 80)],
          ),
        ),
      );

      final state = _harnessState(tester);
      await state.simulateOpenChat();
      await pumpUntilInitialOpenComplete(tester);

      expect(state.isAtBottom, isTrue);
      expect(state.scrollController.position.pixels, closeTo(0, 1));
    });

    testWidgets('2. листание вверх — фото сверху догружается, позиция не сбрасывается', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: [200, 80, 80, ...List<double>.filled(10, 80)],
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent,
      );
      await tester.pump();
      expect(state.isAtBottom, isFalse);

      state.growItemAt(0, 400); // самое старое (верх) выросло
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.isAtBottom, isFalse);
    });

    testWidgets('3. E2EE reload при чтении истории не дёргает к низу', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: List<double>.filled(14, 100),
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent * 0.6,
      );
      await tester.pump();
      final pixelsBeforeReload = state.scrollController.position.pixels;
      expect(state.isAtBottom, isFalse);

      await state.simulateE2eeReload();
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      expect(state.isAtBottom, isFalse);
      expect(
        state.scrollController.position.pixels,
        closeTo(pixelsBeforeReload, 5),
      );
    });

    testWidgets('4. после роста фото скролл остаётся интерактивным', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScrollHarness(
            initialItemHeights: [200, ...List<double>.filled(11, 80)],
          ),
        ),
      );
      await pumpUntilInitialOpenComplete(tester);

      final state = _harnessState(tester);
      state.scrollController.jumpTo(
        state.scrollController.position.maxScrollExtent,
      );
      await tester.pump();
      state.growItemAt(0, 400);
      await tester.pump();
      await tester.pump();

      final before = state.scrollController.position.pixels;
      await tester.drag(find.byType(ListView), const Offset(0, 120));
      await tester.pump();
      await tester.pump();

      // Скролл реагирует на жест (позиция изменилась).
      expect(state.scrollController.position.pixels, isNot(closeTo(before, 0.5)));
    });
  });
}
