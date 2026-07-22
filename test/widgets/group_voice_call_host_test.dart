import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/main.dart' show navigatorKey;
import 'package:my_chat_app/screens/group_voice_call_screen.dart';
import 'package:my_chat_app/services/group_voice_call_service.dart';
import 'package:my_chat_app/widgets/voice_call_host.dart';

void main() {
  setUp(() {
    GroupVoiceCallService.instance.reset();
  });

  tearDown(() {
    GroupVoiceCallService.instance.reset();
  });

  testWidgets('incoming group call opens GroupVoiceCallScreen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: VoiceCallHost(
            userId: '42',
            child: Center(child: Text('chats')),
          ),
        ),
      ),
    );
    await tester.pump();

    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'g-1',
      chatId: '9',
      chatName: 'Team',
      fromUserId: '7',
      fromLabel: 'Host',
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      GroupVoiceCallService.instance.snapshot.phase,
      GroupCallPhase.incoming,
    );
    expect(find.byType(GroupVoiceCallScreen), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    GroupVoiceCallService.instance.reset();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('minimized incoming group call rejects instead of leaving', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: VoiceCallHost(
            userId: '42',
            child: Center(child: Text('chats')),
          ),
        ),
      ),
    );
    await tester.pump();

    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'g-minimized',
      chatId: '9',
      chatName: 'Team',
      fromUserId: '7',
      fromLabel: 'Host',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Свернуть'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupVoiceCallScreen), findsNothing);
    expect(find.byTooltip('Отклонить'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    GroupVoiceCallService.instance.reset();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('incoming LiveKit video call keeps camera opt-in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: VoiceCallHost(
            userId: '42',
            child: Center(child: Text('chats')),
          ),
        ),
      ),
    );
    await tester.pump();

    GroupVoiceCallService.instance.applyIncomingFromPush(
      callId: 'lk-video',
      chatId: '9',
      chatName: 'Team',
      fromUserId: '7',
      fromLabel: 'Host',
      transport: GroupCallTransport.livekit,
      mediaType: GroupCallMediaType.video,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(GroupVoiceCallService.instance.snapshot.isCameraEnabled, isFalse);
    expect(find.text('С аудио'), findsOneWidget);
    expect(find.text('С видео'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    GroupVoiceCallService.instance.reset();
    await tester.pump(const Duration(seconds: 2));
  });

  test('minimized group action invokes reject only while incoming', () async {
    var rejected = 0;
    var left = 0;

    Future<void> reject() async => rejected++;
    Future<void> leave() async => left++;

    await performMinimizedGroupEndAction(
      phase: GroupCallPhase.incoming,
      rejectIncoming: reject,
      leave: leave,
    );
    await performMinimizedGroupEndAction(
      phase: GroupCallPhase.connecting,
      rejectIncoming: reject,
      leave: leave,
    );

    expect(rejected, 1);
    expect(left, 1);
  });
}
