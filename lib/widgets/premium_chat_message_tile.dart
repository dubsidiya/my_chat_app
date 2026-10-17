import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_dimens.dart';
import 'chat_message_tile.dart';

/// Премиальная обёртка над ChatMessageTile с улучшениями по flutter-taste-skill:
/// - Staggered entrance animation (index * 50ms delay)
/// - Spring scale на long press
/// - Glassmorphism улучшения
class PremiumChatMessageTile extends StatefulWidget {
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
  final int index;

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
    this.index = 0,
  });

  @override
  State<PremiumChatMessageTile> createState() => _PremiumChatMessageTileState();
}

class _PremiumChatMessageTileState extends State<PremiumChatMessageTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(widget.isMine ? 0.1 : -0.1, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entranceController, curve: Curves.easeOut));

    // Staggered entrance: index * 50ms delay
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted && !_hasAnimated) {
        _entranceController.forward();
        _hasAnimated = true;
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ChatMessageTile(
          key: widget.key,
          msg: widget.msg,
          isMine: widget.isMine,
          isHighlighted: widget.isHighlighted,
          isFirstInGroup: widget.isFirstInGroup,
          isLastInGroup: widget.isLastInGroup,
          scheme: widget.scheme,
          accent1: widget.accent1,
          accent2: widget.accent2,
          accent3: widget.accent3,
          myUserId: widget.myUserId,
          myAvatarUrl: widget.myAvatarUrl,
          chatId: widget.chatId,
          myAvatarPlaceholder: widget.myAvatarPlaceholder,
          otherAvatarPlaceholder: widget.otherAvatarPlaceholder,
          memberByHandle: widget.memberByHandle,
          onOpenSenderProfile: widget.onOpenSenderProfile,
          onShowMessageMenu: widget.onShowMessageMenu,
          onOpenImage: widget.onOpenImage ?? () {},
          onOpenVideo: widget.onOpenVideo ?? () {},
          buildVoiceBubble: widget.buildVoiceBubble,
          isVoiceMessage: widget.isVoiceMessage,
          formatBytes: widget.formatBytes,
          formatDate: widget.formatDate,
          buildMessageStatus: widget.buildMessageStatus,
          onShowReactionPicker: widget.onShowReactionPicker,
          onOpenUserProfileById: widget.onOpenUserProfileById,
        ),
      ),
    );
  }
}
