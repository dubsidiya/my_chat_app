import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_chat_app/models/message.dart';
import 'package:my_chat_app/widgets/live_voice_bubble.dart';
import 'package:my_chat_app/widgets/premium_chat_message_tile.dart';

Message _textMessage() {
  return Message(
    id: 'm1',
    chatId: 'c1',
    userId: 'u1',
    content: 'hello',
    senderEmail: 'a@b.c',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

Widget _tile() {
  final scheme = const ColorScheme.dark();
  return MaterialApp(
    home: Scaffold(
      body: PremiumChatMessageTile(
        msg: _textMessage(),
        isMine: true,
        isHighlighted: false,
        isFirstInGroup: true,
        isLastInGroup: true,
        scheme: scheme,
        accent1: Colors.purple,
        accent2: Colors.blue,
        accent3: Colors.teal,
        myUserId: 'u1',
        myAvatarUrl: null,
        chatId: 'c1',
        myAvatarPlaceholder: const SizedBox.shrink(),
        otherAvatarPlaceholder: const SizedBox.shrink(),
        memberByHandle: const {},
        onOpenSenderProfile: () {},
        onShowMessageMenu: () {},
        buildVoiceBubble: () => const SizedBox.shrink(),
        isVoiceMessage: () => false,
        formatBytes: (_) => '',
        formatDate: (_) => '12:00',
        buildMessageStatus: const SizedBox.shrink(),
        onShowReactionPicker: () {},
        onOpenUserProfileById: (_, __) {},
      ),
    ),
  );
}

void main() {
  testWidgets('история видна на первом кадре без входной анимации', (tester) async {
    await tester.pumpWidget(_tile());
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
    expect(
      tester.element(find.byType(PremiumChatMessageTile)),
      isA<StatelessElement>(),
    );
  });

  testWidgets('тик голосового обновляет только пузырь', (tester) async {
    final signal = VoicePlaybackSignal();
    var hostBuilds = 0;
    addTearDown(signal.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Builder(
                builder: (context) {
                  hostBuilds++;
                  return const Text('host');
                },
              ),
              LiveVoiceBubble(
                signal: signal,
                messageId: 'voice-1',
                isMine: true,
                seed: 1,
                onPlayPause: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final buildsAfterFirstFrame = hostBuilds;

    signal.sync(
      messageId: 'voice-1',
      position: const Duration(seconds: 3),
      duration: const Duration(seconds: 10),
      playing: true,
      processing: ProcessingState.ready,
    );
    await tester.pump();

    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('host'), findsOneWidget);
    expect(hostBuilds, buildsAfterFirstFrame);
  });

  test('повтор того же тика не уведомляет слушателей', () {
    final signal = VoicePlaybackSignal();
    addTearDown(signal.dispose);
    var notices = 0;
    signal.addListener(() => notices++);
    signal.sync(
      messageId: 'voice-1',
      position: Duration.zero,
      duration: null,
      playing: false,
      processing: ProcessingState.idle,
    );
    expect(notices, 1);
    signal.sync(
      messageId: 'voice-1',
      position: const Duration(milliseconds: 200),
      duration: const Duration(seconds: 2),
      playing: true,
      processing: ProcessingState.ready,
    );
    signal.sync(
      messageId: 'voice-1',
      position: const Duration(milliseconds: 200),
      duration: const Duration(seconds: 2),
      playing: true,
      processing: ProcessingState.ready,
    );
    expect(notices, 2);
  });
}
