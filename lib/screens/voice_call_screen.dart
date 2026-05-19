import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/voice_call_service.dart';
import '../theme/app_colors.dart';
import '../utils/microphone_permission.dart';

/// Full-screen UI for an active or ringing voice call.
class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final VoiceCallService _calls = VoiceCallService.instance;
  RTCVideoRenderer? _remoteRenderer;
  VoiceCallSnapshot _snap = VoiceCallService.instance.snapshot;

  @override
  void initState() {
    super.initState();
    _snap = _calls.snapshot;
    _initRenderer();
    _calls.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _snap = s);
      if (s.phase == VoiceCallPhase.failed &&
          (s.statusMessage?.contains('микрофон') ?? false)) {
        _showMicDeniedHint();
      }
      if (s.phase == VoiceCallPhase.ended ||
          s.phase == VoiceCallPhase.failed ||
          s.phase == VoiceCallPhase.idle) {
        Future<void>.delayed(const Duration(milliseconds: 1200), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });
    Helper.setSpeakerphoneOn(true);
  }

  Future<void> _initRenderer() async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    if (!mounted) {
      await renderer.dispose();
      return;
    }
    setState(() => _remoteRenderer = renderer);
    _attachRemote();
  }

  void _attachRemote() {
    final stream = _calls.remoteStream;
    final renderer = _remoteRenderer;
    if (stream != null && renderer != null) {
      renderer.srcObject = stream;
    }
  }

  void _showMicDeniedHint() {
    final permanent =
        _calls.lastMicrophoneAccess == MicrophoneAccess.permanentlyDenied;
    if (!permanent) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Нужен микрофон'),
          content: const Text(
            'Разрешите доступ к микрофону в Настройках → Reollity → Микрофон, '
            'затем повторите звонок.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(MicrophonePermission.openSettings());
              },
              child: const Text('Настройки'),
            ),
          ],
        ),
      );
    });
  }

  @override
  void dispose() {
    Helper.setSpeakerphoneOn(false);
    _remoteRenderer?.srcObject = null;
    _remoteRenderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _attachRemote();
    final scheme = Theme.of(context).colorScheme;
    final label = (_snap.peerLabel ?? 'Звонок').trim();
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final isIncoming = _snap.phase == VoiceCallPhase.incoming;
    final isConnected = _snap.phase == VoiceCallPhase.connected;
    final status = _snap.statusMessage ?? _phaseLabel(_snap.phase);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_calls.hangUp());
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Stack(
            children: [
              if (_remoteRenderer != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 1,
                  child: Opacity(
                    opacity: 0.01,
                    child: RTCVideoView(
                      _remoteRenderer!,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              Column(
                children: [
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.onSurface),
                      onPressed: () => unawaited(_calls.hangUp()),
                    ),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  if (isConnected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        onPressed: () => unawaited(_calls.toggleMute()),
                        icon: Icon(
                          _snap.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (isIncoming) ...[
                          _roundButton(
                            color: Colors.red.shade600,
                            icon: Icons.call_end_rounded,
                            label: 'Отклонить',
                            onTap: () => unawaited(_calls.rejectIncoming()),
                          ),
                          _roundButton(
                            color: Colors.green.shade600,
                            icon: Icons.call_rounded,
                            label: 'Принять',
                            onTap: () => unawaited(_calls.acceptIncoming()),
                          ),
                        ] else
                          _roundButton(
                            color: Colors.red.shade600,
                            icon: Icons.call_end_rounded,
                            label: 'Завершить',
                            onTap: () => unawaited(_calls.hangUp()),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _phaseLabel(VoiceCallPhase phase) {
    switch (phase) {
      case VoiceCallPhase.outgoing:
        return 'Вызов…';
      case VoiceCallPhase.connecting:
        return 'Соединение…';
      case VoiceCallPhase.connected:
        return 'На связи';
      case VoiceCallPhase.incoming:
        return 'Входящий звонок';
      default:
        return '';
    }
  }

  Widget _roundButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
