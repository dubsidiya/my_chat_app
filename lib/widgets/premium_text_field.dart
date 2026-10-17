import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Премиальное текстовое поле с flutter-taste-skill паттернами:
/// - Glassmorphism с inner border
/// - Focused state с neon glow
/// - Spring scale feedback
/// - Pill-shaped (999px)
///
/// Design dials:
/// VARIANCE: 6 (glassmorphism + subtle animations)
/// MOTION: 5 (focus transitions)
/// DENSITY: 5 (standard mobile spacing)
class PremiumTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const PremiumTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  State<PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<PremiumTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _focusController;
  late Animation<double> _glowAnimation;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusController = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _focusController, curve: AppMotion.spring),
    );

    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
        if (_isFocused) {
          _focusController.forward();
        } else {
          _focusController.reverse();
        }
      });
    });
  }

  @override
  void dispose() {
    _focusController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.labelText != null) ...[
          Padding(
            padding: EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.xs),
            child: Text(
              widget.labelText!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.75),
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
        AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
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
                  color: _isFocused
                      ? AppColors.primary.withValues(alpha: 0.50 + _glowAnimation.value * 0.30)
                      : Colors.white.withValues(alpha: 0.10),
                  width: 1.5,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.15 * _glowAnimation.value),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                maxLines: widget.maxLines,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                enabled: widget.enabled,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.50),
                    letterSpacing: -0.1,
                  ),
                  prefixIcon: widget.prefixIcon != null
                      ? Icon(
                          widget.prefixIcon,
                          size: 22,
                          color: _isFocused
                              ? AppColors.primaryGlow
                              : scheme.onSurfaceVariant.withValues(alpha: 0.60),
                        )
                      : null,
                  suffixIcon: widget.suffixIcon,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: widget.prefixIcon == null ? AppSpacing.lg : AppSpacing.xs,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.errorText != null) ...[
          Padding(
            padding: EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.xs),
            child: Text(
              widget.errorText!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.error,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
