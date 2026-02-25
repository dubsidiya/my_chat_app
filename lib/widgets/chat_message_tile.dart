import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/link_preview.dart';
import '../models/message.dart';
import '../services/link_preview_service.dart';
import '../theme/app_colors.dart';
import '../utils/file_name_display.dart';
import 'link_preview_card.dart';
import 'mention_text.dart';

class ChatMessageTile extends StatelessWidget {
  final Message msg;
  final bool isMine;
  final bool isHighlighted;
  final ColorScheme scheme;
  final Color accent1;
  final Color accent2;
  final Color accent3;
  final String myUserId;
  final String? myAvatarUrl;
  final Widget myAvatarPlaceholder;
  final Widget otherAvatarPlaceholder;
  final Map<String, Map<String, String>> memberByHandle;

  final VoidCallback onOpenSenderProfile;
  final VoidCallback onShowMessageMenu;
  final VoidCallback onOpenImage;
  final Widget Function() buildVoiceBubble;
  final bool Function() isVoiceMessage;
  final String Function(int bytes) formatBytes;
  final String Function(String iso) formatDate;
  final Widget buildMessageStatus;
  final VoidCallback onShowReactionPicker;
  final void Function(String userId, String fallbackLabel) onOpenUserProfileById;

  const ChatMessageTile({
    super.key,
    required this.msg,
    required this.isMine,
    required this.isHighlighted,
    required this.scheme,
    required this.accent1,
    required this.accent2,
    required this.accent3,
    required this.myUserId,
    required this.myAvatarUrl,
    required this.myAvatarPlaceholder,
    required this.otherAvatarPlaceholder,
    required this.memberByHandle,
    required this.onOpenSenderProfile,
    required this.onShowMessageMenu,
    required this.onOpenImage,
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
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isHighlighted ? accent1.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              GestureDetector(
                onTap: onOpenSenderProfile,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: (msg.senderAvatarUrl == null || msg.senderAvatarUrl!.trim().isEmpty)
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [accent3, accent2],
                          )
                        : null,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.neonGlowSoft,
                  ),
                  child: ClipOval(
                    child: (msg.senderAvatarUrl != null && msg.senderAvatarUrl!.trim().isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: msg.senderAvatarUrl!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => otherAvatarPlaceholder,
                            errorWidget: (_, __, ___) => otherAvatarPlaceholder,
                          )
                        : otherAvatarPlaceholder,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: GestureDetector(
                onLongPress: onShowMessageMenu,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isMine
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [accent1, accent2],
                          )
                        : null,
                    color: isMine ? null : AppColors.cardElevatedDark,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMine ? 20 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 20),
                    ),
                    boxShadow: isMine
                        ? AppColors.neonGlowSoft
                        : [
                            BoxShadow(
                              color: scheme.outline.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                    border: isMine ? null : Border.all(color: scheme.outline.withValues(alpha: 0.18), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.isPinned) ...[
                        Row(
                          children: [
                            Icon(Icons.push_pin, size: 14, color: isMine ? Colors.white70 : Colors.amber.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Закреплено',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: isMine ? Colors.white70 : Colors.amber.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (msg.replyToMessage != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isMine ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(color: isMine ? Colors.white : accent1, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.replyToMessage!.senderEmail,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isMine ? Colors.white.withValues(alpha: 0.9) : accent1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (msg.replyToMessage!.hasFile)
                                Row(
                                  children: [
                                    Icon(Icons.insert_drive_file_rounded, size: 14, color: isMine ? Colors.white70 : Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        decodeFileNameForDisplay(msg.replyToMessage!.fileName),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isMine ? Colors.white70 : AppColors.onSurfaceVariantDark,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              else if (msg.replyToMessage!.hasImage)
                                Row(
                                  children: [
                                    Icon(Icons.image, size: 14, color: isMine ? Colors.white70 : Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Фото',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isMine ? Colors.white70 : AppColors.onSurfaceVariantDark,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  msg.replyToMessage!.content.length > 50 ? '${msg.replyToMessage!.content.substring(0, 50)}...' : msg.replyToMessage!.content,
                                  style: TextStyle(fontSize: 12, color: isMine ? Colors.white70 : AppColors.onSurfaceVariantDark),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (!isMine) ...[
                        GestureDetector(
                          onTap: onOpenSenderProfile,
                          child: Text(
                            msg.senderEmail,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent1),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (msg.hasImage) ...[
                        GestureDetector(
                          onTap: onOpenImage,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 250, maxHeight: 400),
                              child: CachedNetworkImage(
                                imageUrl: msg.imageUrl!,
                                fit: BoxFit.contain,
                                memCacheWidth: 500,
                                httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
                                placeholder: (_, __) => Container(
                                  width: 250,
                                  height: 200,
                                  color: Colors.grey.shade200,
                                  child: const Center(child: CircularProgressIndicator()),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  width: 250,
                                  height: 200,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.broken_image_rounded, color: Colors.red),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (msg.hasText || msg.hasFile) const SizedBox(height: 8),
                      ],
                      if (msg.hasFile) ...[
                        if (isVoiceMessage()) ...[
                          buildVoiceBubble(),
                        ] else ...[
                          GestureDetector(
                            onTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final uri = Uri.tryParse(msg.fileUrl ?? '');
                              if (uri == null) return;
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } else {
                                messenger.showSnackBar(const SnackBar(content: Text('Не удалось открыть файл')));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMine ? Colors.white.withValues(alpha: 0.18) : AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isMine ? Colors.white.withValues(alpha: 0.25) : AppColors.borderDark),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.insert_drive_file_rounded, size: 18, color: isMine ? Colors.white : accent2),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          decodeFileNameForDisplay(msg.fileName),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: isMine ? Colors.white : AppColors.onSurfaceDark, fontWeight: FontWeight.w600),
                                        ),
                                        if (msg.fileSize != null)
                                          Text(
                                            formatBytes(msg.fileSize!),
                                            style: TextStyle(fontSize: 12, color: isMine ? Colors.white70 : AppColors.onSurfaceVariantDark),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.open_in_new_rounded, size: 16, color: isMine ? Colors.white70 : AppColors.onSurfaceVariantDark),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (msg.hasText) ...[
                        Builder(builder: (context) {
                          final baseStyle = TextStyle(
                            color: isMine ? Colors.white : AppColors.onSurfaceDark,
                            fontSize: 15,
                            height: 1.4,
                          );
                          final mentionStyle = baseStyle.copyWith(
                            color: isMine ? Colors.white : AppColors.primaryGlow,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                            decorationColor: (isMine ? Colors.white : AppColors.primaryGlow).withValues(alpha: 0.7),
                          );
                          return MentionText(
                            text: msg.content,
                            style: baseStyle,
                            mentionStyle: mentionStyle,
                            onMentionTap: (handle) {
                              final key = handle.trim().toLowerCase();
                              final info = memberByHandle[key];
                              final uid = info?['id'];
                              if (uid == null || uid.trim().isEmpty) return;
                              onOpenUserProfileById(uid, '@$handle');
                            },
                          );
                        }),
                        Builder(builder: (context) {
                          final url = LinkPreviewService.extractFirstUrl(msg.content);
                          if (url == null) return const SizedBox.shrink();
                          return FutureBuilder<LinkPreview?>(
                            future: LinkPreviewService.instance.get(url),
                            builder: (context, snap) {
                              final p = snap.data;
                              if (p == null) return const SizedBox.shrink();
                              return LinkPreviewCard(url: url, preview: p, isMine: isMine);
                            },
                          );
                        }),
                      ],
                      if (msg.reactions != null && msg.reactions!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: msg.reactions!.map((reaction) {
                            return GestureDetector(
                              onTap: onShowReactionPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isMine ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(reaction.reaction, style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '1',
                                      style: TextStyle(fontSize: 11, color: isMine ? Colors.white70 : AppColors.onSurfaceVariantDark),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatDate(msg.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isMine ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade500,
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 4),
                            buildMessageStatus,
                          ],
                          if (msg.isEdited) ...[
                            const SizedBox(width: 4),
                            Text(
                              'отредактировано',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color: isMine ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isMine) ...[
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: AppColors.neonGlowSoft),
                child: ClipOval(
                  child: myAvatarUrl != null && myAvatarUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: myAvatarUrl!,
                          fit: BoxFit.cover,
                          width: 32,
                          height: 32,
                          placeholder: (_, __) => myAvatarPlaceholder,
                          errorWidget: (_, __, ___) => myAvatarPlaceholder,
                        )
                      : myAvatarPlaceholder,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

