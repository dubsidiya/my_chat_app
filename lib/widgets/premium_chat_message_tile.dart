import 'package:flutter/material.dart';
import '../models/message.dart';
import 'chat_message_tile.dart';

/// Обёртка над [ChatMessageTile].
///
/// История не анимируется: при прокрутке строка создаётся заново
/// (`addAutomaticKeepAlives: false`), и входная анимация прятала уже
/// прочитанные сообщения. Новое сообщение анимирует вызывающий код.
class PremiumChatMessageTile extends StatelessWidget {
  final Message msg;
  final bool isMine;
  final bool isHighlighted;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final ColorScheme scheme;
  final Color accent1;
  final Color accent2;
  final Color accent3;
  final String myUserId;
  final String? myAvatarUrl;
  final String chatId;
  final Widget myAvatarPlaceholder;
  final Widget otherAvatarPlaceholder;
  final Map<String, Map<String, String>> memberByHandle;
  final VoidCallback onOpenSenderProfile;
  final VoidCallback onShowMessageMenu;
  final VoidCallback? onOpenImage;
  final VoidCallback? onOpenVideo;
  final Widget Function() buildVoiceBubble;
  final bool Function() isVoiceMessage;
  final String Function(int) formatBytes;
  final String Function(String) formatDate;
  final Widget buildMessageStatus;
  final VoidCallback onShowReactionPicker;
  final void Function(String, String) onOpenUserProfileById;

  const PremiumChatMessageTile({
    super.key,
    required this.msg,
    required this.isMine,
    required this.isHighlighted,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.scheme,
    required this.accent1,
    required this.accent2,
    required this.accent3,
    required this.myUserId,
    required this.myAvatarUrl,
    required this.chatId,
    required this.myAvatarPlaceholder,
    required this.otherAvatarPlaceholder,
    required this.memberByHandle,
    required this.onOpenSenderProfile,
    required this.onShowMessageMenu,
    this.onOpenImage,
    this.onOpenVideo,
    required this.buildVoiceBubble,
    required this.isVoiceMessage,
    required this.formatBytes,
    required this.formatDate,
    required this.buildMessageStatus,
    required this.onShowReactionPicker,
    required this.onOpenUserProfileById,
  });

  @override
  Widget build(BuildContext context) {
    return ChatMessageTile(
      msg: msg,
      isMine: isMine,
      isHighlighted: isHighlighted,
      isFirstInGroup: isFirstInGroup,
      isLastInGroup: isLastInGroup,
      scheme: scheme,
      accent1: accent1,
      accent2: accent2,
      accent3: accent3,
      myUserId: myUserId,
      myAvatarUrl: myAvatarUrl,
      chatId: chatId,
      myAvatarPlaceholder: myAvatarPlaceholder,
      otherAvatarPlaceholder: otherAvatarPlaceholder,
      memberByHandle: memberByHandle,
      onOpenSenderProfile: onOpenSenderProfile,
      onShowMessageMenu: onShowMessageMenu,
      onOpenImage: onOpenImage ?? () {},
      onOpenVideo: onOpenVideo ?? () {},
      buildVoiceBubble: buildVoiceBubble,
      isVoiceMessage: isVoiceMessage,
      formatBytes: formatBytes,
      formatDate: formatDate,
      buildMessageStatus: buildMessageStatus,
      onShowReactionPicker: onShowReactionPicker,
      onOpenUserProfileById: onOpenUserProfileById,
    );
  }
}
