import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/widgets/chat_date_header.dart';

void main() {
  testWidgets('ChatDateHeader отображает переданный label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatDateHeader(label: 'Сегодня'),
        ),
      ),
    );
    expect(find.text('Сегодня'), findsOneWidget);
  });

  testWidgets('ChatDateHeader отображает произвольную дату', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatDateHeader(label: '15 февраля'),
        ),
      ),
    );
    expect(find.text('15 февраля'), findsOneWidget);
  });
}
