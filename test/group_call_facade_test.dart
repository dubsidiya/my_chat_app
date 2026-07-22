import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/group_voice_call_service.dart';
import 'package:my_chat_app/utils/push_payload.dart';
import 'package:my_chat_app/widgets/voice_call_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GroupVoiceCallService.instance.reset();
  });

  tearDown(() {
    GroupVoiceCallService.instance.reset();
  });

  test('facade pins incoming LiveKit transport and requested media', () {
    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'lk-call',
      chatId: '9',
      chatName: 'Team',
      fromUserId: '1',
      fromLabel: 'Host',
      transport: GroupCallTransport.livekit,
      mediaType: GroupCallMediaType.video,
    );
    final first = GroupVoiceCallService.instance.snapshot;
    expect(first.transport, GroupCallTransport.livekit);
    expect(first.mediaType, GroupCallMediaType.video);
    expect(first.phase, GroupCallPhase.incoming);
    expect(first.isCameraEnabled, isFalse);

    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'lk-call',
      chatId: '9',
      chatName: 'Changed duplicate',
      fromUserId: '1',
      fromLabel: 'Changed duplicate',
      transport: GroupCallTransport.livekit,
      mediaType: GroupCallMediaType.video,
    );
    expect(GroupVoiceCallService.instance.snapshot.chatName, 'Team');

    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'lk-call',
      chatId: '9',
      chatName: 'Legacy collision',
      fromUserId: '1',
      fromLabel: 'Legacy',
      transport: GroupCallTransport.mesh,
    );
    expect(
      GroupVoiceCallService.instance.snapshot.transport,
      GroupCallTransport.livekit,
    );
  });

  test('new push protocol is distinct from legacy mesh', () {
    const liveKit = {
      'type': 'incoming_livekit_group_call',
      'provider': 'livekit',
      'protocolVersion': '2',
      'callId': 'same',
    };
    const mesh = {'type': 'incoming_group_call', 'callId': 'same'};
    expect(isIncomingCallPushData(liveKit), isTrue);
    expect(isLiveKitGroupCallPushData(liveKit), isTrue);
    expect(isLiveKitGroupCallPushData(mesh), isFalse);
    expect(
      incomingCallPushDedupeKey(liveKit),
      isNot(incomingCallPushDedupeKey(mesh)),
    );
  });

  test('reconnecting minimized call leaves instead of rejecting', () {
    expect(minimizedGroupShouldReject(GroupCallPhase.incoming), isTrue);
    expect(minimizedGroupShouldReject(GroupCallPhase.reconnecting), isFalse);
  });
}
