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

    expect(GroupVoiceCallService.instance.snapshot.phase, GroupCallPhase.incoming);
    expect(find.byType(GroupVoiceCallScreen), findsOneWidget);
    expect(find.text('Принять'), findsOneWidget);
  });
}
