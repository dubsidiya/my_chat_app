import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_design_tokens.dart';

/// Премиальный пузырь сообщения с flutter-taste-skill паттернами:
/// - Glassmorphism с inner border
/// - Mesh градиенты для исходящих
/// - Улучшенная типография с emphasized weights
/// - Spring animations на long press
/// 
/// Design dials:
/// VARIANCE: 7 (использует Stack с overlapping accent)
/// MOTION: 5 (spring feedback на interactions)
/// DENSITY: 5 (стандартное mobile spacing)
class PremiumMessageBubble extends StatefulWidget {
  final String text;
  final bool isMine;
  final DateTime timestamp;
  final bool isRead;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final Widget? trailing;

  const PremiumMessageBubble({
    super.key,
    required this.text,
    required this.isMine,
    required this.timestamp,
    this.isRead = false,
    this.onLongPress,
    this.onTap,
    this.trailing,
  });

  @override
  State<PremiumMessageBubble> createState() => _PremiumMessageBubbleState();
}

class _PremiumMessageBubbleState extends State<PremiumMessageBubble>
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
      end: 0.98, // Subtle scale для message bubbles
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

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs + 1,
      ),
      child: Align(
        alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: GestureDetector(
            onTap: () {
              _scaleController.forward().then((_) => _scaleController.reverse());
              widget.onTap?.call();
            },
            onLongPress: () {
              _scaleController.forward().then((_) {
                widget.onLongPress?.call();
                _scaleController.reverse();
              });
            },
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: _buildDecoration(scheme),
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Message text с emphasized typography для incoming
                  Text(
                    widget.text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: widget.isMine ? FontWeight.w500 : FontWeight.w600,
                      color: widget.isMine
                          ? Colors.white
                          : scheme.onSurface,
                      height: 1.4,
                      letterSpacing: -0.1,
                    ),
                  ),
                  SizedBox(height: AppSpacing.xxs + 1),
                  // Timestamp + read status
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(widget.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: widget.isMine
                              ? Colors.white.withValues(alpha: 0.75)
                              : scheme.onSurfaceVariant.withValues(alpha: 0.65),
                        ),
                      ),
                      if (widget.isMine) ...[
                        SizedBox(width: AppSpacing.xxs + 1),
                        Icon(
                          widget.isRead
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 14,
                          color: widget.isRead
                              ? AppColors.cyberAccent
                              : Colors.white.withValues(alpha: 0.65),
                        ),
                      ],
                      if (widget.trailing != null) ...[
                        SizedBox(width: AppSpacing.xxs + 1),
                        widget.trailing!,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration(ColorScheme scheme) {
    if (widget.isMine) {
      // Исходящие: mesh gradient + neon glow
      return BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(AppRadius.xs),
        ),
        // Mesh gradient (multiple radial overlapping)
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.8,
          colors: [
            AppColors.primary,
            AppColors.primaryDeep,
            AppColors.primary.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        border: Border.all(
          // Inner border для depth
          color: AppColors.primaryGlow.withValues(alpha: 0.40),
          width: 1,
        ),
        // Neon glow для исходящих
        boxShadow: AppDesignTokens.neonGlow(intensity: 0.25),
      );
    } else {
      // Входящие: glassmorphism
      return BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(AppRadius.xs),
          bottomRight: Radius.circular(AppRadius.lg),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withValues(alpha: 0.95),
            scheme.surfaceContainerHighest.withValues(alpha: 0.80),
          ],
        ),
        border: Border.all(
          // Glassmorphism inner border
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
        boxShadow: AppDesignTokens.compoundShadow(scheme),
      );
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// Премиальный Empty State для пустого чата
/// Использует glow effects и mesh gradients
class PremiumEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const PremiumEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.chat_bubble_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon с mesh gradient background + neon glow
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.2,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.20),
                    AppColors.cyberAccent.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  width: 1,
                ),
                boxShadow: AppDesignTokens.neonGlow(intensity: 0.15),
              ),
              child: Icon(
                icon,
                size: 42,
                color: AppColors.primaryGlow,
              ),
            ),
            SizedBox(height: AppSpacing.xl),
            // Title с emphasized weight
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800, // Emphasized
                color: scheme.onSurface,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
