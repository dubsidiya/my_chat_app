import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_design_tokens.dart';

/// Премиальная кнопка с flutter-taste-skill паттернами:
/// - Primary: mesh gradient + neon glow
/// - Secondary: glassmorphism
/// - Outlined: glass с border
/// - Spring scale feedback
/// - Pill-shaped (999px border radius)
///
/// Design dials:
/// VARIANCE: 7 (mesh gradient для primary, glass для остальных)
/// MOTION: 6 (spring scale feedback)
/// DENSITY: 5 (standard mobile spacing)
enum PremiumButtonVariant { primary, secondary, outlined, text }

class PremiumButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final PremiumButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  const PremiumButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PremiumButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
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
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    Widget content = Row(
      mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getLoadingColor(scheme),
              ),
            ),
          )
        else if (widget.icon != null)
          Icon(
            widget.icon,
            size: 20,
            color: _getContentColor(scheme),
          ),
        if ((widget.isLoading || widget.icon != null))
          SizedBox(width: AppSpacing.xs),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _getContentColor(scheme),
            letterSpacing: -0.2,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: isEnabled ? 1.0 : 0.55,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTapDown: (_) => isEnabled ? _scaleController.forward() : null,
          onTapUp: (_) {
            if (isEnabled) {
              _scaleController.reverse();
              widget.onPressed!();
            }
          },
          onTapCancel: () => isEnabled ? _scaleController.reverse() : null,
          child: Container(
            constraints: BoxConstraints(
              minHeight: 50,
              minWidth: widget.isFullWidth ? double.infinity : 120,
            ),
            decoration: _buildDecoration(scheme),
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration(ColorScheme scheme) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        // Primary: mesh gradient + neon glow
        return BoxDecoration(
          borderRadius: BorderRadius.circular(999), // Pill shape
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
          boxShadow: AppDesignTokens.neonGlow(intensity: 0.35),
        );

      case PremiumButtonVariant.secondary:
        // Secondary: glassmorphism
        return BoxDecoration(
          borderRadius: BorderRadius.circular(999),
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

      case PremiumButtonVariant.outlined:
        // Outlined: transparent с border
        return BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.50),
            width: 1.5,
          ),
        );

      case PremiumButtonVariant.text:
        // Text: no decoration
        return const BoxDecoration();
    }
  }

  Color _getContentColor(ColorScheme scheme) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return Colors.white;
      case PremiumButtonVariant.secondary:
        return scheme.onSurface;
      case PremiumButtonVariant.outlined:
      case PremiumButtonVariant.text:
        return AppColors.primaryGlow;
    }
  }

  Color _getLoadingColor(ColorScheme scheme) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return Colors.white.withValues(alpha: 0.85);
      case PremiumButtonVariant.secondary:
        return scheme.onSurface.withValues(alpha: 0.75);
      case PremiumButtonVariant.outlined:
      case PremiumButtonVariant.text:
        return AppColors.primaryGlow;
    }
  }
}

/// Премиальная floating action button (FAB)
/// Rounded square shape по Material 3 Expressive (не круг!)
class PremiumFab extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const PremiumFab({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  State<PremiumFab> createState() => _PremiumFabState();
}

class _PremiumFabState extends State<PremiumFab>
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
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: (_) => _scaleController.forward(),
        onTapUp: (_) {
          _scaleController.reverse();
          widget.onPressed();
        },
        onTapCancel: () => _scaleController.reverse(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            // Rounded square, не круг (Material 3 Expressive)
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.5,
              colors: [
                AppColors.primary,
                AppColors.primaryDeep,
              ],
            ),
            border: Border.all(
              color: AppColors.primaryGlow.withValues(alpha: 0.50),
              width: 1,
            ),
            boxShadow: AppDesignTokens.neonGlow(intensity: 0.40),
          ),
          child: Icon(
            widget.icon,
            size: 26,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
