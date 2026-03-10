import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/widgets/chat_load_more_button.dart';

void main() {
  testWidgets('ChatLoadMoreButton отображает текст и по тапу вызывает onPressed', (WidgetTester tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatLoadMoreButton(
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );
    expect(find.text('Загрузить старые сообщения'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(pressed, true);
  });
}
