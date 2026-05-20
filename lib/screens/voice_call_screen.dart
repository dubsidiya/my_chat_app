import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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
  StreamSubscription<VoiceCallSnapshot>? _stateSub;
  Timer? _durationTicker;
  Timer? _ringerTicker;
  DateTime? _connectedAt;
  Duration _callDuration = Duration.zero;
  bool _speakerOn = true;
  bool _autoCloseScheduled = false;
  VoiceCallPhase? _lastHapticPhase;

  @override
  void initState() {
    super.initState();
    _snap = _calls.snapshot;
    _syncConnectedTimer();
    _syncRingerFor(_snap.phase);
    _initRenderer();
    _stateSub = _calls.stateStream.listen(_onCallState);
    _applySpeakerphone(_speakerOn);
  }

  void _onCallState(VoiceCallSnapshot s) {
    if (!mounted) return;
    setState(() => _snap = s);
    if (s.phase == VoiceCallPhase.connected) {
      _attachRemote();
    }
    _syncConnectedTimer();
    _syncRingerFor(s.phase);
    if (s.phase == VoiceCallPhase.failed &&
        (s.statusMessage?.contains('микрофон') ?? false)) {
      _showMicDeniedHint();
    }
    if (s.phase == VoiceCallPhase.ended ||
        s.phase == VoiceCallPhase.failed ||
        s.phase == VoiceCallPhase.idle) {
      _scheduleAutoClose();
    }
  }

  void _scheduleAutoClose() {
    if (_autoCloseScheduled) return;
    _autoCloseScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final phase = _calls.snapshot.phase;
      if (phase == VoiceCallPhase.ended ||
          phase == VoiceCallPhase.failed ||
          phase == VoiceCallPhase.idle) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        _autoCloseScheduled = false;
      }
    });
  }

  void _syncConnectedTimer() {
    if (_snap.phase == VoiceCallPhase.connected) {
      _connectedAt ??= DateTime.now();
      _callDuration = DateTime.now().difference(_connectedAt!);
      _durationTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _connectedAt == null) return;
        setState(() {
          _callDuration = DateTime.now().difference(_connectedAt!);
        });
      });
    } else {
      _durationTicker?.cancel();
      _durationTicker = null;
      if (_snap.phase != VoiceCallPhase.connecting) {
        _connectedAt = null;
        _callDuration = Duration.zero;
      }
    }
  }

  /// Mimic ringtone/ringback while the call is ringing in foreground: WS invite
  /// reaches us before any FCM banner (or instead of it), so the call screen
  /// would otherwise be silent until the peer picks up.
  void _syncRingerFor(VoiceCallPhase phase) {
    if (phase == VoiceCallPhase.incoming || phase == VoiceCallPhase.outgoing) {
      if (_lastHapticPhase == phase && _ringerTicker != null) return;
      _lastHapticPhase = phase;
      _ringerTicker?.cancel();
      _emitRingerHaptic(phase);
      _ringerTicker = Timer.periodic(
        phase == VoiceCallPhase.incoming
            ? const Duration(milliseconds: 1800)
            : const Duration(seconds: 3),
        (_) => _emitRingerHaptic(phase),
      );
    } else {
      _lastHapticPhase = phase;
      _ringerTicker?.cancel();
      _ringerTicker = null;
    }
  }

  void _emitRingerHaptic(VoiceCallPhase phase) {
    try {
      if (phase == VoiceCallPhase.incoming) {
        HapticFeedback.heavyImpact();
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (!mounted || _calls.snapshot.phase != VoiceCallPhase.incoming) {
            return;
          }
          HapticFeedback.heavyImpact();
        });
      } else {
        HapticFeedback.mediumImpact();
      }
    } catch (_) {}
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

  void _applySpeakerphone(bool enabled) {
    try {
      Helper.setSpeakerphoneOn(enabled);
    } catch (_) {}
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    _applySpeakerphone(_speakerOn);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _stateSub = null;
    _durationTicker?.cancel();
    _durationTicker = null;
    _ringerTicker?.cancel();
    _ringerTicker = null;
    _applySpeakerphone(false);
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
    final canShowMediaControls =
        isConnected || _snap.phase == VoiceCallPhase.connecting;
    final status = isConnected
        ? _formatDuration(_callDuration)
        : (_snap.statusMessage ?? _phaseLabel(_snap.phase));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // На входящем "back" семантически = «отклонить», иначе peer услышит
        // call_hangup до того, как зазвонило.
        if (_snap.phase == VoiceCallPhase.incoming) {
          unawaited(_calls.rejectIncoming());
        } else {
          unawaited(_calls.hangUp());
        }
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
                  if (canShowMediaControls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _mediaToggleButton(
                            icon: _snap.isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            onTap: () => unawaited(_calls.toggleMute()),
                          ),
                          const SizedBox(width: 24),
                          _mediaToggleButton(
                            icon: _speakerOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded,
                            onTap: _toggleSpeaker,
                          ),
                        ],
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

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _mediaToggleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 28),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        padding: const EdgeInsets.all(16),
      ),
    );
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
