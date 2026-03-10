import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/widgets/mention_text.dart';

void main() {
  testWidgets('MentionText отображает текст с упоминанием', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionText(
            text: 'Привет @user, как дела?',
            style: const TextStyle(fontSize: 14),
            mentionStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    expect(find.textContaining('@user', findRichText: true), findsOneWidget);
  });

  testWidgets('MentionText по тапу на упоминание вызывает onMentionTap', (WidgetTester tester) async {
    String? tappedHandle;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionText(
            text: '@admin',
            style: const TextStyle(fontSize: 14),
            mentionStyle: const TextStyle(fontSize: 14),
            onMentionTap: (handle) => tappedHandle = handle,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(RichText));
    await tester.pumpAndSettle();
    expect(tappedHandle, 'admin');
  });

  testWidgets('MentionText без упоминаний отображает текст', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionText(
            text: 'Обычный текст без @mention',
            style: const TextStyle(fontSize: 14),
            mentionStyle: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
    expect(find.textContaining('Обычный текст', findRichText: true), findsOneWidget);
  });
}
