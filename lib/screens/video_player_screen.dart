import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _controlsVisible = true;
  String? _errorText;
  Timer? _controlsHideTimer;
  bool _wasPlaying = false;
  bool _wasBuffering = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        _controller.addListener(_handleControllerChanged);
        _controller.play();
        _scheduleAutoHideControls();
        setState(() {
          _wasPlaying = _controller.value.isPlaying;
          _wasBuffering = _controller.value.isBuffering;
        });
      }).catchError((error) {
        if (!mounted) return;
        setState(() {
          _errorText = error.toString().replaceFirst('Exception: ', '');
        });
      });
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final value = _controller.value;
    final playingChanged = value.isPlaying != _wasPlaying;
    final bufferingChanged = value.isBuffering != _wasBuffering;
    if (playingChanged || bufferingChanged) {
      _wasPlaying = value.isPlaying;
      _wasBuffering = value.isBuffering;
      if (value.isPlaying) {
        _scheduleAutoHideControls();
      } else {
        _controlsHideTimer?.cancel();
      }
      setState(() {});
    }
  }

  void _scheduleAutoHideControls() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_controller.value.isPlaying) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible && _controller.value.isPlaying) {
      _scheduleAutoHideControls();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _fmt(Duration d) {
    final total = d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildError(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 44),
            const SizedBox(height: 12),
            Text(
              _errorText ?? 'Не удалось загрузить видео',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Открыть во внешнем плеере'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initialized = _controller.value.isInitialized;
    final position = initialized ? _controller.value.position : Duration.zero;
    final duration = initialized ? _controller.value.duration : Duration.zero;
    final isPlaying = initialized && _controller.value.isPlaying;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Видео', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _openExternal,
            tooltip: 'Открыть во внешнем плеере',
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            Center(
              child: _errorText != null
                  ? _buildError(scheme)
                  : !initialized
                      ? const CircularProgressIndicator(color: Colors.white70)
                      : AspectRatio(
                          aspectRatio: _controller.value.aspectRatio > 0
                              ? _controller.value.aspectRatio
                              : 16 / 9,
                          child: VideoPlayer(_controller),
                        ),
            ),
            if (initialized && _controller.value.isBuffering)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2.4,
                ),
              ),
            if (_controlsVisible && initialized)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        const Spacer(),
                        IconButton(
                          onPressed: () async {
                            if (isPlaying) {
                              await _controller.pause();
                              _controlsHideTimer?.cancel();
                            } else {
                              await _controller.play();
                              _scheduleAutoHideControls();
                            }
                            if (!mounted) return;
                            setState(() {});
                          },
                          iconSize: 56,
                          color: Colors.white,
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Text(
                                _fmt(position),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Expanded(
                                child: VideoProgressIndicator(
                                  _controller,
                                  allowScrubbing: true,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                              ),
                              Text(
                                _fmt(duration),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
