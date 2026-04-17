import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/message.dart';
import 'package:my_chat_app/utils/voice_message_utils.dart';

void main() {
  test('looksLikeAudio по mime и расширению', () {
    expect(looksLikeAudio(mime: 'audio/m4a'), isTrue);
    expect(looksLikeAudio(fileName: 'x.MP3'), isTrue);
    expect(looksLikeAudio(mime: 'image/jpeg', fileName: 'a.jpg'), isFalse);
  });

  test('formatVoiceDuration MM:SS', () {
    expect(formatVoiceDuration(const Duration(minutes: 2, seconds: 5)), '02:05');
    expect(formatVoiceDuration(const Duration(seconds: 9)), '00:09');
  });

  test('isVoiceMessage по типу и файлу', () {
    final v = Message(
      id: '1',
      chatId: '1',
      userId: '1',
      content: '',
      messageType: 'voice',
      senderEmail: 'a@a.com',
      createdAt: '',
      fileUrl: 'x',
      fileName: 'a.m4a',
    );
    expect(isVoiceMessage(v), isTrue);

    final t = Message(
      id: '2',
      chatId: '1',
      userId: '1',
      content: 'hi',
      messageType: 'text',
      senderEmail: 'a@a.com',
      createdAt: '',
    );
    expect(isVoiceMessage(t), isFalse);
  });
}
