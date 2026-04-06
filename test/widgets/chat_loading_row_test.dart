import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/widgets/chat_loading_row.dart';

void main() {
  testWidgets('ChatLoadingRow показывает текст загрузки', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatLoadingRow()),
      ),
    );
    expect(find.text('Загрузка сообщений...'), findsOneWidget);
  });

  testWidgets('ChatLoadingRow с кастомным accentColor', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatLoadingRow(accentColor: Colors.red),
        ),
      ),
    );
    expect(find.text('Загрузка сообщений...'), findsOneWidget);
  });
}
