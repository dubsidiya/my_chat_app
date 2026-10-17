import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_design_tokens.dart';
import '../models/chat.dart';

/// Премиальная карточка чата следуя flutter-taste-skill паттернам:
/// - Glassmorphism с inner border
/// - Neon glow для непрочитанных
/// - Spring animations на press
/// - Mesh gradient overlay
class PremiumChatTile extends StatefulWidget {
  final Chat chat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAvatarTap;
  final Widget? trailing;
  final int index;

  const PremiumChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
    this.onAvatarTap,
    this.trailing,
    this.index = 0,
  });

  @override
  State<PremiumChatTile> createState() => _PremiumChatTileState();
}

class _PremiumChatTileState extends State<PremiumChatTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97, // flutter-taste-skill: scale to 0.97 on press
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: AppMotion.spring,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = widget.chat.unreadCount;
    final hasUnread = unread > 0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.lgAll,
          // Glassmorphism с inner border (критично для flutter-taste-skill)
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasUnread
                ? [
                    scheme.surfaceContainerHighest.withValues(alpha: 0.75),
                    scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  ]
                : [
                    scheme.surfaceContainerHighest.withValues(alpha: 0.40),
                    scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  ],
          ),
          border: Border.all(
            // Inner border для glassmorphism depth
            color: hasUnread
                ? scheme.primary.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
          // Compound shadow: ambient + neon glow
          boxShadow: hasUnread
              ? AppDesignTokens.neonGlow(intensity: 0.35)
              : AppDesignTokens.compoundShadow(scheme),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              _scaleController.forward().then((_) => _scaleController.reverse());
              widget.onTap();
            },
            onTapDown: (_) => _scaleController.forward(),
            onTapUp: (_) => _scaleController.reverse(),
            onTapCancel: () => _scaleController.reverse(),
            onLongPress: widget.onLongPress,
            borderRadius: AppRadius.lgAll,
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  // Avatar с neon border для непрочитанных
                  _buildAvatar(scheme, hasUnread),
                  SizedBox(width: AppSpacing.md),
                  // Content: name + preview
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildNameRow(scheme, hasUnread),
                        if (widget.chat.lastMessageAt != null) ...[
                          SizedBox(height: AppSpacing.xxs + 1),
                          _buildPreview(scheme),
                        ],
                        if ((widget.chat.folderName ?? '').trim().isNotEmpty) ...[
                          SizedBox(height: AppSpacing.xxs),
                          _buildFolderChip(scheme),
                        ],
                      ],
                    ),
                  ),
                  // Trailing: time + badge
                  SizedBox(width: AppSpacing.sm),
                  _buildTrailing(scheme, hasUnread),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme scheme, bool hasUnread) {
    final avatarUrl = widget.chat.otherUserAvatarUrl;
    final hasAvatar = !widget.chat.isGroup &&
        avatarUrl != null &&
        avatarUrl.trim().isNotEmpty;

    return GestureDetector(
      onTap: widget.onAvatarTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: hasAvatar
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.cyberAccent],
                ),
          borderRadius: BorderRadius.circular(14),
          // Neon border для непрочитанных
          border: hasUnread
              ? Border.all(
                  color: AppColors.primaryGlow.withValues(alpha: 0.6),
                  width: 2,
                )
              : null,
          // Glow только для непрочитанных
          boxShadow:
              hasUnread ? AppDesignTokens.neonGlow(intensity: 0.4) : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hasAvatar
              ? CachedNetworkImage(
                  imageUrl: avatarUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _avatarPlaceholder(),
                  errorWidget: (_, __, ___) => _avatarPlaceholder(),
                )
              : widget.chat.isGroup
                  ? Icon(
                      Icons.group_rounded,
                      color: Colors.white,
                      size: 24,
                    )
                  : _avatarPlaceholder(),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder() {
    final name = widget.chat.name.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: AppColors.primary.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryGlow,
          ),
        ),
      ),
    );
  }

  Widget _buildNameRow(ColorScheme scheme, bool hasUnread) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.chat.name,
            style: TextStyle(
              fontSize: 15,
              // Emphasized weight для непрочитанных (flutter-taste-skill)
              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
              color: scheme.onSurface,
              letterSpacing: -0.15,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(ColorScheme scheme) {
    final text = widget.chat.lastMessageText?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
        height: 1.3,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildFolderChip(ColorScheme scheme) {
    final folderName = widget.chat.folderName;
    if (folderName == null || folderName.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    
    final trimmedName = folderName.trim();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 1,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_rounded,
            size: 11,
            color: AppColors.primaryGlow,
          ),
          SizedBox(width: AppSpacing.xxs + 1),
          Text(
            trimmedName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryGlow,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing(ColorScheme scheme, bool hasUnread) {
    final unread = widget.chat.unreadCount;
    final lastMessageAt = widget.chat.lastMessageAt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Time
        if (lastMessageAt != null)
          Text(
            _formatTime(lastMessageAt),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: hasUnread
                  ? AppColors.primaryGlow
                  : scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        // Badge с neon glow
        if (hasUnread) ...[
          SizedBox(height: AppSpacing.xs),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: unread > 99 ? 6 : 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryGlow],
              ),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              // Neon glow на badge
              boxShadow: AppDesignTokens.neonGlow(
                color: AppColors.primaryGlow,
                intensity: 0.5,
              ),
            ),
            child: Text(
              unread > 99 ? '99+' : unread.toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return '';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final now = DateTime.now();
      final diff = now.difference(dateTime);

      if (diff.inDays == 0) {
        // Today: HH:mm
        return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays == 1) {
        return 'вчера';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}д';
      } else {
        return '${dateTime.day}.${dateTime.month}';
      }
    } catch (e) {
      return '';
    }
  }
}
