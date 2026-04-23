import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('длинный чат (5k) рендерится без ошибок и заметных лагов', (tester) async {
    final items = List<int>.generate(5000, (i) => i);
    final sw = Stopwatch()..start();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final mod = index % 10;
              if (mod == 0) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blueGrey,
                    child: Text('${index % 9}'),
                  ),
                  title: const Text('Voice bubble mock'),
                  subtitle: const LinearProgressIndicator(value: 0.35),
                );
              }
              if (mod == 1) {
                return ListTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                  ),
                  title: Text('Image message #$index'),
                );
              }
              return ListTile(title: Text('Text message #$index'));
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    sw.stop();

    expect(find.byType(ListView), findsOneWidget);
    expect(sw.elapsedMilliseconds, lessThan(2500));
  });
}
