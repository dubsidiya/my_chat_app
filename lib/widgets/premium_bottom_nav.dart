import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_design_tokens.dart';

/// Премиальный Bottom Navigation Bar с flutter-taste-skill паттернами:
/// - Glassmorphism с inner border + backdrop blur эффект
/// - Pill-shaped active indicator (Material 3 Expressive)
/// - Spring scale feedback на interactions
/// - Neon glow на active item
///
/// Design dials:
/// VARIANCE: 7 (используем glassmorphism + pill indicator)
/// MOTION: 6 (spring scale + staggered entrance)
/// DENSITY: 5 (standard mobile spacing)
class PremiumBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<PremiumNavItem> items;

  const PremiumBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  State<PremiumBottomNav> createState() => _PremiumBottomNavState();
}

class _PremiumBottomNavState extends State<PremiumBottomNav> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 68 + MediaQuery.of(context).padding.bottom,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surfaceContainerLowest.withValues(alpha: 0.92),
            scheme.surfaceContainerLowest.withValues(alpha: 0.96),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom,
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
            widget.items.length,
            (index) => _PremiumNavButton(
              item: widget.items[index],
              isActive: widget.currentIndex == index,
              onTap: () => widget.onTap(index),
              index: index,
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumNavButton extends StatefulWidget {
  final PremiumNavItem item;
  final bool isActive;
  final VoidCallback onTap;
  final int index;

  const _PremiumNavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.index,
  });

  @override
  State<_PremiumNavButton> createState() => _PremiumNavButtonState();
}

class _PremiumNavButtonState extends State<_PremiumNavButton>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
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

    return Expanded(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTapDown: (_) => _scaleController.forward(),
          onTapUp: (_) {
            _scaleController.reverse();
            widget.onTap();
          },
          onTapCancel: () => _scaleController.reverse(),
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.spring,
            padding: EdgeInsets.symmetric(
              vertical: AppSpacing.xs,
              horizontal: AppSpacing.sm,
            ),
            decoration: widget.isActive
                ? BoxDecoration(
                    // Pill-shaped indicator для active (Material 3 Expressive)
                    borderRadius: BorderRadius.circular(999),
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.5,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.20),
                        AppColors.primaryDeep.withValues(alpha: 0.12),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      width: 1,
                    ),
                    boxShadow: AppDesignTokens.neonGlow(intensity: 0.18),
                  )
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isActive ? widget.item.activeIcon : widget.item.icon,
                  size: 26,
                  color: widget.isActive
                      ? AppColors.primaryGlow
                      : scheme.onSurfaceVariant.withValues(alpha: 0.70),
                ),
                SizedBox(height: AppSpacing.xxs - 2),
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w600,
                    color: widget.isActive
                        ? AppColors.primaryGlow
                        : scheme.onSurfaceVariant.withValues(alpha: 0.65),
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const PremiumNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
