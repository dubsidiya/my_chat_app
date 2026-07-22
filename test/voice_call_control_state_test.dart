import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/group_voice_call_service.dart';
import 'package:my_chat_app/services/voice_call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceCallService.instance.reset();
    GroupVoiceCallService.instance.reset();
  });

  tearDown(() {
    VoiceCallService.instance.reset();
    GroupVoiceCallService.instance.reset();
  });

  test('DM desired mute and camera state works before tracks exist', () async {
    VoiceCallService.instance.applyIncomingFromPush(
      callId: 'call-controls',
      chatId: '7',
      peerUserId: '9',
      peerLabel: 'Peer',
      mediaType: CallMediaType.video,
    );

    await VoiceCallService.instance.toggleMute();
    await VoiceCallService.instance.toggleCamera();

    final snapshot = VoiceCallService.instance.snapshot;
    expect(snapshot.isMuted, isTrue);
    expect(snapshot.isCameraOff, isTrue);
    expect(snapshot.mediaType, CallMediaType.video);
  });

  test('group desired mute state works before tracks exist', () async {
    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'group-controls',
      chatId: '8',
      chatName: 'Team',
      fromUserId: '9',
      fromLabel: 'Peer',
    );

    await GroupVoiceCallService.instance.toggleMute();

    expect(GroupVoiceCallService.instance.snapshot.isMuted, isTrue);
  });

  test('camera-only media update does not imply audio downgrade', () {
    final update = parseCallMediaUpdate({'camera_off': true});
    final explicitVideoUpdate = parseCallMediaUpdate({
      'media_type': 'video',
      'camera_off': true,
    });

    expect(update.cameraOff, isTrue);
    expect(update.mediaType, isNull);
    expect(explicitVideoUpdate.mediaType, CallMediaType.video);
    expect(explicitVideoUpdate.cameraOff, isTrue);
    expect(callCameraOffFromRaw('true'), isNull);
  });

  test('front camera state is exposed by call snapshots', () {
    const video = VoiceCallSnapshot(
      mediaType: CallMediaType.video,
      isUsingFrontCamera: true,
    );

    expect(video.isUsingFrontCamera, isTrue);
    expect(
      video.copyWith(isUsingFrontCamera: false).isUsingFrontCamera,
      isFalse,
    );
  });
}
