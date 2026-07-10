import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/chat_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await ChatImageCache.clearAll();
  });

  test('warm + peek: повторный скролл берёт фото из RAM без сети', () {
    const url = 'https://example.com/photo.jpg';
    final bytes = Uint8List.fromList(List<int>.generate(128, (i) => i % 256));

    expect(ChatImageCache.peek(url), isNull);
    ChatImageCache.warm(url, bytes);

    final hit = ChatImageCache.peek(url);
    expect(hit, isNotNull);
    expect(hit, same(bytes));

    // Второй peek тоже hit (LRU touch).
    expect(ChatImageCache.peek(url), same(bytes));
  });

  test('get после warm возвращает те же байты синхронно из памяти', () async {
    const url = 'https://example.com/cached.jpg';
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    ChatImageCache.warm(url, bytes);

    final got = await ChatImageCache.get(url, chatId: 'c1');
    expect(got, same(bytes));
  });

  test('clearAll сбрасывает peek', () async {
    const url = 'https://example.com/clear-me.jpg';
    ChatImageCache.warm(url, Uint8List.fromList([9, 9, 9]));
    expect(ChatImageCache.peek(url), isNotNull);

    await ChatImageCache.clearAll();
    expect(ChatImageCache.peek(url), isNull);
  });

  test('повторный get того же URL дедуплицирует inflight', () async {
    final url =
        'https://invalid.invalid/inflight-${DateTime.now().microsecondsSinceEpoch}.bin';
    final a = ChatImageCache.get(url);
    final b = ChatImageCache.get(url);
    final ra = await a;
    final rb = await b;
    expect(ra, isNull);
    expect(rb, isNull);
  });
}
