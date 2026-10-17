import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Премиальный AppBar с flutter-taste-skill паттернами:
/// - Glassmorphism с backdrop blur
/// - Mesh gradient для hero variant
/// - Inner border для depth
/// - Spring scale feedback на actions
///
/// Design dials:
/// VARIANCE: 7 (glass default, mesh для hero)
/// MOTION: 5 (spring scale на buttons)
/// DENSITY: 5 (standard mobile spacing)
class PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool isHero; // Hero variant с mesh gradient
  final PreferredSizeWidget? bottom;

  const PremiumAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.isHero = false,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: isHero
              ? _buildHeroDecoration(scheme)
              : _buildGlassDecoration(scheme),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: kToolbarHeight,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Row(
                      children: [
                        if (leading != null) leading!,
                        SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: isHero ? 22 : 18,
                              fontWeight: isHero ? FontWeight.w800 : FontWeight.w700,
                              color: isHero
                                  ? Colors.white
                                  : scheme.onSurface,
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (actions != null) ...actions!,
                      ],
                    ),
                  ),
                ),
                if (bottom != null) bottom!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildHeroDecoration(ColorScheme scheme) {
    // Hero: mesh gradient + neon glow
    return BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topCenter,
        radius: 2.0,
        colors: [
          AppColors.primary.withValues(alpha: 0.95),
          AppColors.primaryDeep.withValues(alpha: 0.92),
        ],
      ),
      border: Border(
        bottom: BorderSide(
          color: AppColors.primaryGlow.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.20),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  BoxDecoration _buildGlassDecoration(ColorScheme scheme) {
    // Standard: glassmorphism
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          scheme.surface.withValues(alpha: 0.90),
          scheme.surface.withValues(alpha: 0.85),
        ],
      ),
      border: Border(
        bottom: BorderSide(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

/// Премиальная IconButton для AppBar actions с spring scale
class PremiumAppBarAction extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final String? tooltip;

  const PremiumAppBarAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
  });

  @override
  State<PremiumAppBarAction> createState() => _PremiumAppBarActionState();
}

class _PremiumAppBarActionState extends State<PremiumAppBarAction>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
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
      child: IconButton(
        onPressed: () {
          _scaleController.forward().then((_) {
            _scaleController.reverse();
            widget.onPressed();
          });
        },
        icon: Icon(widget.icon),
        color: widget.color ?? scheme.onSurface,
        tooltip: widget.tooltip,
        splashRadius: 24,
      ),
    );
  }
}
