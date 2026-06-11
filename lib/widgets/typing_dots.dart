import 'package:flutter/material.dart';

/// Три анимированные точки «печатает…» — волна прозрачности и лёгкого
/// подпрыгивания. Используется в статус-строке AppBar чата.
class TypingDots extends StatefulWidget {
  final Color color;
  final double dotSize;

  const TypingDots({
    super.key,
    required this.color,
    this.dotSize = 5,
  });

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            // Волна: каждая точка отстаёт по фазе на 0.2.
            final phase = (_controller.value - i * 0.2) % 1.0;
            final wave = phase < 0.5 ? (phase * 2) : (2 - phase * 2);
            final eased = Curves.easeInOut.transform(wave.clamp(0.0, 1.0));
            return Container(
              width: widget.dotSize,
              height: widget.dotSize,
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : 3,
                bottom: 1.5 + eased * 2.5,
              ),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.35 + eased * 0.65),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
