import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/voice_message_utils.dart';

/// Пузырь голосового сообщения (плей/пауза, слайдер, длительность).
class ChatVoiceBubble extends StatelessWidget {
  final bool isMine;
  final bool isBusy;
  final bool showPlaying;
  final Duration position;
  final Duration totalDuration;
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
    required this.onPlayPause,
    this.onPositionDrag,
    this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context) {
    const incomingAccent = AppColors.primary;
    final maxMs = totalDuration.inMilliseconds > 0 ? totalDuration.inMilliseconds : 1;
    final posMs = position.inMilliseconds.clamp(0, maxMs);

    final playColor = isMine ? Colors.white : incomingAccent;
    final trackInactive = isMine ? Colors.white.withValues(alpha: 0.35) : Colors.grey.shade300;
    final bubbleBg = isMine ? Colors.white.withValues(alpha: 0.22) : Colors.grey.shade50;
    final borderColor = isMine ? Colors.white.withValues(alpha: 0.35) : Colors.grey.shade200;
    final textColor = isMine ? Colors.white.withValues(alpha: 0.95) : AppColors.onSurfaceDark;
    final textSecondary = isMine ? Colors.white.withValues(alpha: 0.75) : AppColors.onSurfaceVariantDark;

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isMine ? 0.08 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          if (isMine)
            BoxShadow(
              color: (Theme.of(context).brightness == Brightness.dark ? incomingAccent : AppColors.primary)
                  .withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isBusy)
            SizedBox(
              width: 48,
              height: 48,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(playColor),
                ),
              ),
            )
          else
            Material(
              color: isMine ? Colors.white.withValues(alpha: 0.28) : Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isMine ? Colors.white.withValues(alpha: 0.4) : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onPlayPause,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    showPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 28,
                    color: playColor,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 14,
                      color: textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Голосовое сообщение',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                    activeTrackColor: playColor,
                    inactiveTrackColor: trackInactive,
                    thumbColor: playColor,
                  ),
                  child: Slider(
                    value: posMs.toDouble(),
                    min: 0,
                    max: maxMs.toDouble(),
                    onChanged: onPositionDrag,
                    onChangeEnd: onSeekEnd,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatVoiceDuration(position),
                      style: TextStyle(
                        fontSize: 13,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      totalDuration == Duration.zero ? '—:—' : formatVoiceDuration(totalDuration),
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
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
