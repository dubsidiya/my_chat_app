import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_design_tokens.dart';

/// Премиальная кнопка с flutter-taste-skill паттернами:
/// - Mesh градиент фон вместо flat color
/// - Neon glow shadows
/// - Spring scale feedback на press
/// - Inner border для depth
enum PremiumButtonVariant {
  primary, // Mesh gradient primary
  secondary, // Glassmorphism outline
  ghost, // Transparent с hover
}

class PremiumButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final PremiumButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final EdgeInsets? padding;

  const PremiumButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = PremiumButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expanded = false,
    this.padding,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: AppMotion.fast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.96, // Spring scale feedback
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
    final enabled = widget.onPressed != null && !widget.loading;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTapDown: enabled ? (_) {
          setState(() => _isPressed = true);
          _scaleController.forward();
        } : null,
        onTapUp: enabled ? (_) {
          setState(() => _isPressed = false);
          _scaleController.reverse();
        } : null,
        onTapCancel: enabled ? () {
          setState(() => _isPressed = false);
          _scaleController.reverse();
        } : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.5,
          duration: AppMotion.fast,
          child: Container(
            width: widget.expanded ? double.infinity : null,
            height: 48,
            decoration: _buildDecoration(scheme, enabled),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? () {
                  _scaleController.forward().then((_) {
                    _scaleController.reverse();
                    widget.onPressed?.call();
                  });
                } : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: widget.padding ??
                      EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.md,
                      ),
                  child: Center(
                    child: widget.loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation(
                                _getTextColor(scheme),
                              ),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  size: 18,
                                  color: _getTextColor(scheme),
                                ),
                                SizedBox(width: AppSpacing.sm),
                              ],
                              Text(
                                widget.text,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _getTextColor(scheme),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration(ColorScheme scheme, bool enabled) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          // Mesh gradient background
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [
              AppColors.primary,
              AppColors.primaryDeep,
              AppColors.primary.withValues(alpha: 0.95),
            ],
            stops: const [0.0, 0.65, 1.0],
          ),
          border: Border.all(
            // Inner border для depth
            color: AppColors.primaryGlow.withValues(alpha: 0.45),
            width: 1,
          ),
          // Neon glow для primary button
          boxShadow: enabled && !_isPressed
              ? AppDesignTokens.neonGlow(intensity: 0.4)
              : null,
        );

      case PremiumButtonVariant.secondary:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          // Glassmorphism background
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surfaceContainerHighest.withValues(alpha: 0.65),
              scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            ],
          ),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: AppDesignTokens.compoundShadow(scheme),
        );

      case PremiumButtonVariant.ghost:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          color: _isPressed && enabled
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        );
    }
  }

  Color _getTextColor(ColorScheme scheme) {
    switch (widget.variant) {
      case PremiumButtonVariant.primary:
        return Colors.white;
      case PremiumButtonVariant.secondary:
        return AppColors.primary;
      case PremiumButtonVariant.ghost:
        return scheme.onSurface;
    }
  }
}

/// FAB с premium эффектами
class PremiumFAB extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltip;
  final bool mini;

  const PremiumFAB({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.mini = false,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip,
      mini: mini,
      elevation: 0,
      highlightElevation: 0,
      child: Container(
        width: mini ? 40 : 56,
        height: mini ? 40 : 56,
        decoration: BoxDecoration(
          // Mesh gradient для FAB
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.3,
            colors: [
              AppColors.primary,
              AppColors.cyberAccent,
              AppColors.primaryDeep,
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: AppColors.primaryGlow.withValues(alpha: 0.5),
            width: 1,
          ),
          // Strong neon glow для FAB
          boxShadow: AppDesignTokens.neonGlow(
            color: AppColors.primaryGlow,
            intensity: 0.6,
          ),
        ),
        child: Icon(
          icon,
          size: mini ? 20 : 24,
          color: Colors.white,
        ),
      ),
    );
  }
}
