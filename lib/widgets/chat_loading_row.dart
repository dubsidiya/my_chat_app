import 'package:flutter/material.dart';

/// Индикатор загрузки сообщений в списке чата.
class ChatLoadingRow extends StatelessWidget {
  final Color? accentColor;

  const ChatLoadingRow({super.key, this.accentColor});

  static const Color _defaultAccent = Color(0xFF667eea);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accentColor ?? _defaultAccent;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Загрузка сообщений...',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
