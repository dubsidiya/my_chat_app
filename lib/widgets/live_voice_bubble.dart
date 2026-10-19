import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'chat_voice_bubble.dart';

/// Состояние воспроизведения одного голосового. Слушают только пузыри,
/// поэтому тики позиции не пересобирают весь экран чата.
class VoicePlaybackSignal extends ChangeNotifier {
  String? messageId;
  Duration position = Duration.zero;
  Duration? duration;
  bool playing = false;
  ProcessingState processing = ProcessingState.idle;

  void sync({
    required String? messageId,
    required Duration position,
    required Duration? duration,
    required bool playing,
    required ProcessingState processing,
  }) {
    if (this.messageId == messageId &&
        this.position == position &&
        this.duration == duration &&
        this.playing == playing &&
        this.processing == processing) {
      return;
    }
    this.messageId = messageId;
    this.position = position;
    this.duration = duration;
    this.playing = playing;
    this.processing = processing;
    notifyListeners();
  }
}

/// Пузырь, который сам подписан на [VoicePlaybackSignal].
class LiveVoiceBubble extends StatelessWidget {
  final VoicePlaybackSignal signal;
  final String messageId;
  final bool isMine;
  final int seed;
  final VoidCallback onPlayPause;
  final void Function(int millis)? onPreviewPosition;
  final Future<void> Function(int millis)? onSeekEnd;

  const LiveVoiceBubble({
    super.key,
    required this.signal,
    required this.messageId,
    required this.isMine,
    required this.seed,
    required this.onPlayPause,
    this.onPreviewPosition,
    this.onSeekEnd,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: signal,
      builder: (context, _) {
        final isCurrent = signal.messageId == messageId;
        final total = isCurrent ? (signal.duration ?? Duration.zero) : Duration.zero;
        final position = isCurrent ? signal.position : Duration.zero;
        final isBusy =
            isCurrent &&
            (signal.processing == ProcessingState.loading ||
                signal.processing == ProcessingState.buffering);
        return ChatVoiceBubble(
          isMine: isMine,
          isBusy: isBusy,
          showPlaying: isCurrent && signal.playing,
          position: position,
          totalDuration: total,
          seed: seed,
          onPlayPause: onPlayPause,
          onPositionDrag: isCurrent && onPreviewPosition != null
              ? (value) => onPreviewPosition!(value.toInt())
              : null,
          onSeekEnd: isCurrent && onSeekEnd != null
              ? (value) => onSeekEnd!(value.toInt())
              : null,
        );
      },
    );
  }
}
