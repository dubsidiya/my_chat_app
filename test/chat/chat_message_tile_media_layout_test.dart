import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';
import 'package:my_chat_app/models/message.dart';
import 'package:my_chat_app/widgets/chat_message_tile.dart';
import 'package:my_chat_app/widgets/skeleton_placeholder.dart';

Message _imageMessage() {
  return Message(
    id: '1',
    chatId: 'c1',
    userId: 'u2',
    content: '',
    imageUrl: 'https://example.com/image.jpg',
    messageType: 'image',
    senderEmail: 'user@example.com',
    createdAt: '2026-01-01T10:00:00.000Z',
  );
}

void main() {
  group('ChatMessageTile media layout regression', () {
    testWidgets('placeholder фото совпадает с maxHeight bubble (400px)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageTile(
              msg: _imageMessage(),
              isMine: false,
              isHighlighted: false,
              scheme: ThemeData.dark().colorScheme,
              accent1: Colors.cyan,
              accent2: Colors.blue,
              accent3: Colors.purple,
              myUserId: 'u1',
              myAvatarUrl: null,
              myAvatarPlaceholder: const Icon(Icons.person),
              otherAvatarPlaceholder: const Icon(Icons.person_outline),
              memberByHandle: const {},
              onOpenSenderProfile: () {},
              onShowMessageMenu: () {},
              onOpenImage: () {},
              onOpenVideo: () {},
              buildVoiceBubble: () => const SizedBox.shrink(),
              isVoiceMessage: () => false,
              formatBytes: (b) => '$b B',
              formatDate: (iso) => iso,
              buildMessageStatus: const SizedBox.shrink(),
              onShowReactionPicker: () {},
              onOpenUserProfileById: (_, __) {},
            ),
          ),
        ),
      );

      final skeleton = tester.widget<SkeletonPlaceholder>(
        find.byType(SkeletonPlaceholder),
      );
      expect(skeleton.height, 400);
      expect(skeleton.width, 250);
    });

    test('incoming message policy: near-bottom only', () {
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(isNearBottom: true),
        isTrue,
      );
      expect(
        ChatScrollPolicy.shouldScrollOnIncomingMessages(isNearBottom: false),
        isFalse,
      );
    });
  });
}
