import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_design_tokens.dart';

/// Премиальная карточка для profile screen с flutter-taste-skill паттернами:
/// - Glassmorphism с inner border
/// - Mesh gradиент фон для hero card (аватар + имя)
/// - Улучшенная типография
///
/// Design dials:
/// VARIANCE: 7 (Hero card с mesh gradient, другие — glass)
/// MOTION: 5 (Spring scale feedback)
/// DENSITY: 5 (Standard mobile spacing)
class PremiumProfileCard extends StatefulWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isHero; // Hero card с mesh gradient вместо glass

  const PremiumProfileCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isHero = false,
  });

  @override
  State<PremiumProfileCard> createState() => _PremiumProfileCardState();
}

class _PremiumProfileCardState extends State<PremiumProfileCard>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _scaleController, curve: AppMotion.spring),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => widget.onTap != null
            ? _scaleController.forward()
            : null,
        onTapUp: (_) {
          if (widget.onTap != null) {
            _scaleController.reverse();
            widget.onTap!();
          }
        },
        onTapCancel: () =>
            widget.onTap != null ? _scaleController.reverse() : null,
        child: Container(
          decoration: widget.isHero
              ? _buildHeroDecoration(scheme)
              : _buildGlassDecoration(scheme),
          padding: EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: widget.isHero ? 20 : 15,
                        fontWeight: widget.isHero ? FontWeight.w800 : FontWeight.w600,
                        color: widget.isHero
                            ? Colors.white
                            : scheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      SizedBox(height: AppSpacing.xxs),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: widget.isHero
                              ? Colors.white.withValues(alpha: 0.80)
                              : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                SizedBox(width: AppSpacing.sm),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildHeroDecoration(ColorScheme scheme) {
    // Hero card: mesh gradient + neon glow
    return BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      gradient: RadialGradient(
        center: Alignment.topLeft,
        radius: 1.8,
        colors: [
          AppColors.primary,
          AppColors.primaryDeep,
          AppColors.primary.withValues(alpha: 0.92),
        ],
        stops: const [0.0, 0.6, 1.0],
      ),
      border: Border.all(
        color: AppColors.primaryGlow.withValues(alpha: 0.45),
        width: 1,
      ),
      boxShadow: AppDesignTokens.neonGlow(intensity: 0.30),
    );
  }

  BoxDecoration _buildGlassDecoration(ColorScheme scheme) {
    // Standard card: glassmorphism
    return BoxDecoration(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          scheme.surfaceContainerHighest.withValues(alpha: 0.95),
          scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.12),
        width: 1,
      ),
      boxShadow: AppDesignTokens.compoundShadow(scheme),
    );
  }
}

/// Премиальная секция с заголовком
class PremiumProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const PremiumProfileSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
              letterSpacing: 0.8,
            ),
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}
