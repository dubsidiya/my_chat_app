import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/voice_message_utils.dart';

/// Голосовое сообщение в стиле современных мессенджеров (Telegram-like):
/// круглая кнопка play/pause с градиентом, живая «волна» (waveform) с прогрессом
/// и перемоткой по тапу/драгу, аккуратный таймер. Без отдельной «коробки» —
/// контент лежит прямо в пузыре сообщения.
class ChatVoiceBubble extends StatelessWidget {
  final bool isMine;
  final bool isBusy;
  final bool showPlaying;
  final Duration position;
  final Duration totalDuration;

  /// Стабильный seed для генерации формы волны (обычно `msg.id.hashCode`),
  /// чтобы у одного сообщения волна всегда выглядела одинаково.
  final int seed;

  final VoidCallback onPlayPause;
  final ValueChanged<double>? onPositionDrag;
  final ValueChanged<double>? onSeekEnd;

  const ChatVoiceBubble({
    super.key,
    required this.isMine,
    required this.isBusy,
    required this.showPlaying,
    required this.position,
    required this.totalDuration,
    this.seed = 0,
    required this.onPlayPause,
    this.onPositionDrag,
    this.onSeekEnd,
  });

  /// Детерминированная форма волны: псевдослучайные, но стабильные амплитуды
  /// с лёгким сглаживанием, чтобы выглядело как реальная звуковая дорожка.
  List<double> _waveform(int count) {
    final rng = math.Random(seed == 0 ? 7 : seed);
    final raw = List<double>.generate(count, (_) => rng.nextDouble());
    return List<double>.generate(count, (i) {
      final prev = i > 0 ? raw[i - 1] : raw[i];
      final next = i < count - 1 ? raw[i + 1] : raw[i];
      final smooth = (raw[i] * 0.6 + prev * 0.2 + next * 0.2);
      return (0.18 + smooth * 0.82).clamp(0.18, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxMs =
        totalDuration.inMilliseconds > 0 ? totalDuration.inMilliseconds : 1;
    final posMs = position.inMilliseconds.clamp(0, maxMs);
    final progress =
        totalDuration.inMilliseconds > 0 ? posMs / maxMs : 0.0;

    // Активная/неактивная часть волны и кнопка play подбираются под фон пузыря.
    final activeWave = isMine ? Colors.white : AppColors.primaryGlow;
    final inactiveWave = isMine
        ? Colors.white.withValues(alpha: 0.40)
        : AppColors.onSurfaceVariantDark.withValues(alpha: 0.40);
    final playIconColor = isMine ? AppColors.primary : Colors.white;
    final textColor = isMine
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.onSurfaceVariantDark;

    final showElapsed = showPlaying || posMs > 0;
    final timeLabel = showElapsed
        ? formatVoiceDuration(position)
        : (totalDuration == Duration.zero
            ? ''
            : formatVoiceDuration(totalDuration));

    final canSeek = onPositionDrag != null;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 196, maxWidth: 264),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PlayButton(
            isMine: isMine,
            isBusy: isBusy,
            showPlaying: showPlaying,
            iconColor: playIconColor,
            onTap: isBusy ? null : onPlayPause,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 30,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.isFinite &&
                              constraints.maxWidth > 0
                          ? constraints.maxWidth
                          : 160.0;
                      final barCount = (width / 6).floor().clamp(14, 40);

                      void seekTo(double dx) {
                        final frac = (dx / width).clamp(0.0, 1.0);
                        onPositionDrag?.call(frac * maxMs);
                      }

                      void endAt(double dx) {
                        final frac = (dx / width).clamp(0.0, 1.0);
                        onSeekEnd?.call(frac * maxMs);
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown:
                            canSeek ? (d) => seekTo(d.localPosition.dx) : null,
                        onTapUp:
                            canSeek ? (d) => endAt(d.localPosition.dx) : null,
                        onHorizontalDragUpdate:
                            canSeek ? (d) => seekTo(d.localPosition.dx) : null,
                        onHorizontalDragEnd: canSeek
                            ? (_) => onSeekEnd?.call(posMs.toDouble())
                            : null,
                        child: CustomPaint(
                          size: Size(width, 30),
                          painter: _WaveformPainter(
                            bars: _waveform(barCount),
                            progress: progress,
                            active: activeWave,
                            inactive: inactiveWave,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, size: 13, color: textColor),
                    const SizedBox(width: 4),
                    Text(
                      timeLabel.isEmpty ? '0:00' : timeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isMine;
  final bool isBusy;
  final bool showPlaying;
  final Color iconColor;
  final VoidCallback? onTap;

  const _PlayButton({
    required this.isMine,
    required this.isBusy,
    required this.showPlaying,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Свои сообщения — белый круг на градиенте; входящие — кибер-градиент.
          color: isMine ? Colors.white : null,
          gradient: isMine ? null : AppColors.cyberGradient,
          boxShadow: [
            BoxShadow(
              color: (isMine ? Colors.black : AppColors.primary)
                  .withValues(alpha: 0.20),
              blurRadius: 10,
              spreadRadius: -2,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isBusy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(iconColor),
                ),
              )
            : Icon(
                showPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 26,
                color: iconColor,
              ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color active;
  final Color inactive;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.active,
    required this.inactive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    if (n == 0) return;
    final per = size.width / n;
    final barW = (per * 0.55).clamp(2.0, 5.0);
    final progressX = size.width * progress.clamp(0.0, 1.0);
    final cy = size.height / 2;
    final activePaint = Paint()..color = active;
    final inactivePaint = Paint()..color = inactive;

    for (var i = 0; i < n; i++) {
      final centerX = per * i + per / 2;
      final h = (bars[i] * size.height).clamp(3.0, size.height);
      final rect = Rect.fromLTWH(centerX - barW / 2, cy - h / 2, barW, h);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(barW / 2));
      canvas.drawRRect(rrect, centerX <= progressX ? activePaint : inactivePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.active != active ||
      old.inactive != inactive ||
      old.bars.length != bars.length;
}
