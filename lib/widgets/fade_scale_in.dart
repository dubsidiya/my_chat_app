import 'package:flutter/material.dart';

/// Однократная анимация появления: прозрачность 0→1 и лёгкий масштаб 0.96→1.
/// Используется для плавного появления нового сообщения в списке чата.
class FadeScaleIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final VoidCallback? onComplete;

  const FadeScaleIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
    this.delay = Duration.zero,
    this.curve = Curves.easeOut,
    this.onComplete,
  });

  @override
  State<FadeScaleIn> createState() => _FadeScaleInState();
}

class _FadeScaleInState extends State<FadeScaleIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    if (widget.onComplete != null) {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      });
    }
    // Staggered entrance: запускаем анимацию после задержки
    if (widget.delay > Duration.zero) {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
