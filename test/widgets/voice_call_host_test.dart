import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/main.dart' show navigatorKey;
import 'package:my_chat_app/screens/voice_call_screen.dart';
import 'package:my_chat_app/services/voice_call_service.dart';
import 'package:my_chat_app/widgets/voice_call_host.dart';

void main() {
  setUp(() {
    VoiceCallService.instance.reset();
  });

  testWidgets(
    'incoming call opens VoiceCallScreen without user tap (home or chat: same navigator)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: VoiceCallHost(
              userId: '42',
              child: const Center(child: Text('chats')),
            ),
          ),
        ),
      );
      await tester.pump();

      VoiceCallService.instance.applyIncomingFromPush(
        callId: 'call-1',
        chatId: '7',
        peerUserId: '99',
        peerLabel: 'Caller',
      );

      // Без tap — только pump кадров и таймер retry (250 ms).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final snap = VoiceCallService.instance.snapshot;
      expect(snap.phase, VoiceCallPhase.incoming,
          reason: 'phase=${snap.phase} status=${snap.statusMessage}');
      expect(navigatorKey.currentState?.canPop() ?? false, isTrue,
          reason: 'call route must be on root navigator');
      expect(find.byType(VoiceCallScreen), findsOneWidget);
      expect(find.text('Принять'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);
    },
  );

  testWidgets(
    'call_invite over same path as WebSocket (_applyIncomingInvite)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: VoiceCallHost(
            userId: '42',
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('inside chat')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Эмуляция call_invite: тот же _emit, что и из WebSocket.
      VoiceCallService.instance.applyIncomingFromPush(
        callId: 'call-2',
        chatId: '7',
        peerUserId: '99',
        peerLabel: 'Peer',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(VoiceCallScreen), findsOneWidget);
    },
  );
}
