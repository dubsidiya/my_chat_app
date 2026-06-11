import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Плейсхолдер-скелетон при загрузке контента: подложка с бегущим
/// shimmer-бликом в фирменном фиолетовом оттенке.
/// Использовать в [CachedNetworkImage.placeholder] и списках-скелетонах.
class SkeletonPlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const SkeletonPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonPlaceholder> createState() => _SkeletonPlaceholderState();
}

class _SkeletonPlaceholderState extends State<SkeletonPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final highlight = AppColors.primaryGlow.withValues(
      alpha: AppColors.isLight ? 0.14 : 0.18,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Блик пробегает слева направо; стопы за пределами [0,1] обрезаются,
        // что и создаёт эффект «выезда» полосы из-за края.
        final t = -0.4 + _controller.value * 1.8;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            color: base,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: [t - 0.25, t, t + 0.25],
            ),
          ),
        );
      },
    );
  }
}
