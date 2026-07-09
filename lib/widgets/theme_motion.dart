import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_variant.dart';

/// Медленный «волновой» сдвиг градиента фона (Ocean Pulse).
///
/// Для остальных тем отдаёт статичный [AppColors.homeBodyGradient].
class AnimatedHomeBody extends StatefulWidget {
  final Widget child;

  const AnimatedHomeBody({super.key, required this.child});

  @override
  State<AnimatedHomeBody> createState() => _AnimatedHomeBodyState();
}

class _AnimatedHomeBodyState extends State<AnimatedHomeBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    ThemeController.instance.addListener(_syncMotion);
    _syncMotion();
  }

  void _syncMotion() {
    final wantsMotion = ThemeController.instance.variant.hasMotion;
    if (wantsMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_syncMotion);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variant = ThemeController.instance.variant;
    if (!variant.hasMotion) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.homeBodyGradient),
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final begin = Alignment(-1.0 + t * 0.45, -1.0 + t * 0.1);
        final end = Alignment(1.0 - t * 0.15, 1.0 - t * 0.35);
        // Волна должна «прокатывать» яркий cyan из галереи, не только navy.
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              stops: const [0.0, 0.22, 0.48, 0.72, 1.0],
              colors: [
                const Color(0xFF04121C),
                Color.lerp(
                  const Color(0xFF0B2F42),
                  const Color(0xFF0E7490),
                  t,
                )!,
                Color.lerp(
                  const Color(0xFF0E7490),
                  const Color(0xFF22D3EE),
                  0.35 + t * 0.55,
                )!,
                Color.lerp(
                  const Color(0xFF155E75),
                  const Color(0xFF67E8F9),
                  t * 0.45,
                )!,
                const Color(0xFF06202C),
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Точка «онлайн» с дыханием свечения (Ocean Pulse).
class PulsingOnlineDot extends StatefulWidget {
  final double size;

  const PulsingOnlineDot({super.key, this.size = 7});

  @override
  State<PulsingOnlineDot> createState() => _PulsingOnlineDotState();
}

class _PulsingOnlineDotState extends State<PulsingOnlineDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (ThemeController.instance.variant.hasMotion) {
      _controller.repeat(reverse: true);
    }
    ThemeController.instance.addListener(_onTheme);
  }

  void _onTheme() {
    final motion = ThemeController.instance.variant.hasMotion;
    if (motion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onTheme);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.online;
    final motion = ThemeController.instance.variant.hasMotion;

    if (!motion) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 6,
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final blur = 5.0 + t * 10.0;
        final alpha = 0.35 + t * 0.45;
        final scale = 1.0 + t * 0.18;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: alpha),
                  blurRadius: blur,
                  spreadRadius: t * 1.5,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Мягкое «дыхание» свечения вокруг FAB / CTA (только Ocean Pulse).
class PulsingGlow extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;

  const PulsingGlow({
    super.key,
    required this.child,
    this.borderRadius,
  });

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    ThemeController.instance.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (ThemeController.instance.variant.hasMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ThemeController.instance.variant.hasMotion) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final glow = Color.lerp(
          AppColors.primaryGlow,
          AppColors.cyberAccent,
          t,
        )!;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.28 + t * 0.32),
                blurRadius: 14 + t * 18,
                spreadRadius: -2 + t * 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
