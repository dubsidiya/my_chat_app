import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:my_chat_app/screens/register_screen.dart';

void main() {
  testWidgets('Register screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Зарегистрироваться'), findsOneWidget);
  });
}
