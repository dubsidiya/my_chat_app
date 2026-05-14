import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';

class _VideoThumbData {
  final Uint8List? bytes;
  final Duration? duration;

  const _VideoThumbData({
    required this.bytes,
    required this.duration,
  });
}

class VideoThumbnailView extends StatelessWidget {
  final String videoUrl;
  final BorderRadius borderRadius;
  final Widget? overlay;
  final BoxFit fit;
  final Color fallbackColor;
  final bool showDuration;
  final TextStyle? durationTextStyle;
  final Color durationBadgeColor;

  const VideoThumbnailView({
    super.key,
    required this.videoUrl,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.overlay,
    this.fit = BoxFit.cover,
    this.fallbackColor = const Color(0xFF1F232B),
    this.showDuration = false,
    this.durationTextStyle,
    this.durationBadgeColor = const Color(0xB3000000),
  });

  static final Map<String, Future<_VideoThumbData>> _thumbCache =
      <String, Future<_VideoThumbData>>{};

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<_VideoThumbData> _thumbnailFuture(String url) {
    return _thumbCache.putIfAbsent(url, () async {
      Uint8List? bytes;
      Duration? duration;
      try {
        bytes = await VideoThumbnail.thumbnailData(
          video: url,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 768,
          quality: 65,
        );
      } catch (_) {
        bytes = null;
      }

      try {
        final controller = VideoPlayerController.networkUrl(Uri.parse(url));
        await controller.initialize();
        duration = controller.value.duration;
        await controller.dispose();
      } catch (_) {
        duration = null;
      }

      return _VideoThumbData(bytes: bytes, duration: duration);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VideoThumbData>(
      future: _thumbnailFuture(videoUrl),
      builder: (context, snapshot) {
        final bytes = snapshot.data?.bytes;
        final duration = snapshot.data?.duration;
        final base = bytes != null && bytes.isNotEmpty
            ? Image.memory(
                bytes,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
              )
            : Container(
                color: fallbackColor,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.movie_creation_outlined,
                  color: Colors.white54,
                  size: 30,
                ),
              );

        return ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              base,
              if (overlay != null) overlay!,
              if (showDuration)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: durationBadgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _formatDuration(duration),
                      style:
                          durationTextStyle ??
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
