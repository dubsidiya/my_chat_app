import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/message_open_preview.dart';
import 'package:my_chat_app/models/message.dart';

Message _message({
  required String id,
  required String content,
  Message? reply,
}) {
  return Message(
    id: id,
    chatId: 'c1',
    userId: 'u1',
    content: content,
    senderEmail: 'a@b.c',
    createdAt: '2026-01-01T00:00:00.000Z',
    replyToMessage: reply,
  );
}

void main() {
  const cipher = '{"v":"1","ct":"aaaa","n":"bbbb"}';

  test('открытый текст показывается сразу', () {
    final message = _message(id: '1', content: 'привет');
    expect(identical(messageForImmediateDisplay(message), message), isTrue);
    expect(messageAwaitsPreview(message), isFalse);
  });

  test('шифротекст заменяется заглушкой без ожидания ключа', () {
    final shown = messageForImmediateDisplay(
      _message(id: '1', content: cipher),
    );
    expect(shown.content, cipherPreviewPlaceholder);
    expect(shown.content.contains('ct'), isFalse);
    expect(messageAwaitsPreview(shown), isTrue);
  });

  test('расшифровка заполняет заглушку и не затирает уже открытый текст', () {
    final waiting = _message(id: '1', content: cipherPreviewPlaceholder);
    final plain = _message(id: '2', content: 'уже открыто');
    final patched = patchDecryptedPreviews(
      [waiting, plain],
      [
        _message(id: '1', content: 'секрет'),
        _message(id: '2', content: 'чужая версия'),
      ],
    );
    expect(patched, isNotNull);
    expect(patched!.first.content, 'секрет');
    expect(patched.last.content, 'уже открыто');
  });

  test('без заглушек список не меняется', () {
    final current = [_message(id: '1', content: 'привет')];
    expect(
      patchDecryptedPreviews(current, [_message(id: '1', content: 'другое')]),
      isNull,
    );
  });
}
