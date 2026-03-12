import 'package:flutter/material.dart';

/// Плавный переход при навигации: слайд справа + лёгкое затухание.
/// Использовать вместо [MaterialPageRoute] для экранов чата, профиля и т.д.
PageRouteBuilder<T> slideAndFadeRoute<T>({
  required Widget page,
  RouteSettings? settings,
  Duration duration = const Duration(milliseconds: 280),
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeOutCubic;
      final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      final offsetAnimation = animation.drive(tween);
      final fadeAnimation = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      );
      return SlideTransition(
        position: offsetAnimation,
        child: FadeTransition(
          opacity: fadeAnimation,
          child: child,
        ),
      );
    },
    transitionDuration: duration,
  );
}
