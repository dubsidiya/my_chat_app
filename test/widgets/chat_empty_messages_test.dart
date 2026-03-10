import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/widgets/chat_empty_messages.dart';

void main() {
  testWidgets('ChatEmptyMessages показывает заглушку без сообщений', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatEmptyMessages()),
      ),
    );
    expect(find.text('Нет сообщений'), findsOneWidget);
    expect(find.text('Напишите первое сообщение'), findsOneWidget);
  });
}
