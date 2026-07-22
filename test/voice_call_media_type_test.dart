import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/voice_call_service.dart';

void main() {
  test('callMediaTypeFromRaw defaults to audio', () {
    expect(callMediaTypeFromRaw(null), CallMediaType.audio);
    expect(callMediaTypeFromRaw(''), CallMediaType.audio);
    expect(callMediaTypeFromRaw('audio'), CallMediaType.audio);
    expect(callMediaTypeFromRaw('VIDEO'), CallMediaType.video);
    expect(callMediaTypeFromRaw('video'), CallMediaType.video);
  });

  test('VoiceCallSnapshot.isVideo follows mediaType', () {
    const audio = VoiceCallSnapshot(mediaType: CallMediaType.audio);
    const video = VoiceCallSnapshot(mediaType: CallMediaType.video);
    expect(audio.isVideo, isFalse);
    expect(video.isVideo, isTrue);
    expect(
      audio.copyWith(mediaType: CallMediaType.video).isVideo,
      isTrue,
    );
  });

  test('audio downgrade clears isVideo', () {
    const video = VoiceCallSnapshot(mediaType: CallMediaType.video);
    expect(video.copyWith(mediaType: CallMediaType.audio).isVideo, isFalse);
  });
}
