import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/voice_call_service.dart';
import '../theme/app_colors.dart';
import '../utils/call_route_close_gate.dart';
import '../utils/camera_permission.dart';
import '../utils/microphone_permission.dart';

/// Full-screen UI for an active or ringing voice/video call.
class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final VoiceCallService _calls = VoiceCallService.instance;
  RTCVideoRenderer? _remoteRenderer;
  RTCVideoRenderer? _localRenderer;
  VoiceCallSnapshot _snap = VoiceCallService.instance.snapshot;
  StreamSubscription<VoiceCallSnapshot>? _stateSub;
  Timer? _durationTicker;
  Timer? _ringerTicker;
  DateTime? _connectedAt;
  Duration _callDuration = Duration.zero;

  /// Голосовой: разговорный динамик; видео: громкая связь по умолчанию.
  late bool _speakerOn;
  bool _autoCloseScheduled = false;
  final CallRouteCloseGate _closeGate = CallRouteCloseGate();
  VoiceCallPhase? _lastHapticPhase;
  String? _boundCallId;

  @override
  void initState() {
    super.initState();
    _snap = _calls.snapshot;
    _boundCallId = _snap.callId;
    _speakerOn = _calls.preferredSpeakerOn;
    _syncConnectedTimer();
    _syncRingerFor(_snap.phase);
    _initRenderers();
    _stateSub = _calls.stateStream.listen(_onCallState);
    _applySpeakerphone(_speakerOn);
  }

  void _onCallState(VoiceCallSnapshot s) {
    if (!mounted) return;
    setState(() => _snap = s);
    if (s.phase == VoiceCallPhase.connected || s.isVideo) {
      _attachStreams();
    }
    if (s.phase == VoiceCallPhase.connected) {
      // После configure audio session на iOS ранний setSpeakerphoneOn в initState
      // часто игнорируется — повторяем выбранный маршрут при «На связи».
      _applySpeakerphone(_speakerOn);
    }
    _syncConnectedTimer();
    _syncRingerFor(s.phase);
    if (s.phase == VoiceCallPhase.failed &&
        ((s.statusMessage?.contains('микрофон') ?? false) ||
            (s.statusMessage?.contains('камер') ?? false))) {
      _showPermissionDeniedHint();
      // Не auto-close поверх dialog — иначе pop закрывает только dialog.
      return;
    }
    if (s.phase == VoiceCallPhase.ended ||
        s.phase == VoiceCallPhase.failed ||
        s.phase == VoiceCallPhase.idle) {
      _scheduleAutoClose();
    }
  }

  void _scheduleAutoClose() {
    if (_autoCloseScheduled) return;
    if (!_closeGate.requestClose()) return;
    _autoCloseScheduled = true;
    final boundId = _boundCallId;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final snap = _calls.snapshot;
      // Не поп'аем чужой/новый звонок: только если это наш callId или
      // активный звонок уже другой (наш сеанс точно закончился).
      final sameOrGone =
          boundId == null ||
          snap.callId == null ||
          snap.callId == boundId ||
          !snap.isActive;
      if (!sameOrGone) {
        _autoCloseScheduled = false;
        return;
      }
      final phase = snap.phase;
      if (phase == VoiceCallPhase.ended ||
          phase == VoiceCallPhase.failed ||
          phase == VoiceCallPhase.idle ||
          (boundId != null && snap.callId != boundId)) {
        if (!_closeGate.requestClose()) {
          _autoCloseScheduled = false;
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop('auto_close');
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

  Future<void> _initRenderers() async {
    final remote = RTCVideoRenderer();
    final local = RTCVideoRenderer();
    await remote.initialize();
    await local.initialize();
    if (!mounted) {
      await remote.dispose();
      await local.dispose();
      return;
    }
    setState(() {
      _remoteRenderer = remote;
      _localRenderer = local;
    });
    _attachStreams();
  }

  void _attachStreams() {
    final remote = _calls.remoteStream;
    final local = _calls.localStream;
    if (remote != null && _remoteRenderer != null) {
      _remoteRenderer!.srcObject = remote;
    }
    if (local != null && _localRenderer != null) {
      _localRenderer!.srcObject = local;
    }
  }

  void _showPermissionDeniedHint() {
    final micDenied =
        _calls.lastMicrophoneAccess != null &&
        _calls.lastMicrophoneAccess != MicrophoneAccess.granted;
    final camDenied =
        _calls.lastCameraAccess != null &&
        _calls.lastCameraAccess != MicrophoneAccess.granted;
    if (!micDenied && !camDenied) {
      _scheduleAutoClose();
      return;
    }
    if (!_closeGate.beginDialog()) return;
    final needCamera = camDenied && _snap.isVideo;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _closeGate.endDialog();
        return;
      }
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(needCamera ? 'Нужна камера' : 'Нужен микрофон'),
          content: Text(
            kIsWeb
                ? (needCamera
                      ? 'Разрешите камеру и микрофон для этого сайта в настройках '
                            'браузера, затем повторите звонок.'
                      : 'Разрешите микрофон для этого сайта в настройках браузера '
                            '(иконка замка в адресной строке), затем повторите звонок.')
                : (needCamera
                      ? 'Разрешите доступ к камере (и микрофону) в Настройках → '
                            'Reollity, затем повторите звонок.'
                      : 'Разрешите доступ к микрофону в Настройках → Reollity → '
                            'Микрофон, затем повторите звонок.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(
                  needCamera
                      ? CameraPermission.openSettings()
                      : MicrophonePermission.openSettings(),
                );
              },
              child: const Text('Настройки'),
            ),
          ],
        ),
      ).whenComplete(() {
        final deferredClose = _closeGate.endDialog();
        if (!mounted) return;
        final phase = _calls.snapshot.phase;
        final terminal =
            phase == VoiceCallPhase.ended ||
            phase == VoiceCallPhase.failed ||
            phase == VoiceCallPhase.idle;
        if (deferredClose || terminal) _scheduleAutoClose();
      });
    });
  }

  /// Свернуть экран звонка без завершения (плашка в [VoiceCallHost]).
  void _minimizeCall() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop('minimize');
    }
  }

  void _applySpeakerphone(bool enabled) {
    if (kIsWeb) return;
    try {
      Helper.setSpeakerphoneOn(enabled);
    } catch (_) {}
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    _calls.setPreferredSpeakerOn(_speakerOn);
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
    if (!kIsWeb && !_calls.snapshot.isActive) {
      _applySpeakerphone(false);
    }
    _remoteRenderer?.srcObject = null;
    _localRenderer?.srcObject = null;
    _remoteRenderer?.dispose();
    _localRenderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _attachStreams();
    final scheme = Theme.of(context).colorScheme;
    final label = (_snap.peerLabel ?? 'Звонок').trim();
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final isIncoming = _snap.phase == VoiceCallPhase.incoming;
    final isConnected = _snap.phase == VoiceCallPhase.connected;
    final canShowMediaControls =
        isConnected || _snap.phase == VoiceCallPhase.connecting;
    final showVideoUi = _snap.isVideo;
    final status = isConnected
        ? _formatDuration(_callDuration)
        : (_snap.statusMessage ?? _phaseLabel(_snap.phase));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Stack(
            children: [
              if (showVideoUi) ...[
                Positioned.fill(
                  child: _snap.hasRemoteVideo && _remoteRenderer != null
                      ? RTCVideoView(
                          _remoteRenderer!,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : ColoredBox(
                          color: AppColors.backgroundDark,
                          child: Center(
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.25,
                              ),
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                if (_localRenderer != null && !_snap.isCameraOff)
                  Positioned(
                    right: 16,
                    top: 56,
                    width: 112,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RTCVideoView(
                        _localRenderer!,
                        mirror: _snap.isUsingFrontCamera,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
              ] else if (_remoteRenderer != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 1,
                  child: Opacity(
                    opacity: 0.01,
                    child: RTCVideoView(
                      _remoteRenderer!,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              Column(
                children: [
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: scheme.onSurface,
                      ),
                      tooltip: 'Свернуть',
                      onPressed: _minimizeCall,
                    ),
                  ),
                  if (!showVideoUi || !isConnected) ...[
                    const Spacer(),
                    // Video ringing already draws the avatar in the full-bleed
                    // placeholder above — avoid a second overlapping circle.
                    if (!showVideoUi)
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.25,
                        ),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (!showVideoUi) const SizedBox(height: 20),
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
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(blurRadius: 8, color: Colors.black54),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            status,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 14,
                              shadows: const [
                                Shadow(blurRadius: 8, color: Colors.black54),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
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
                          if (showVideoUi) ...[
                            const SizedBox(width: 16),
                            _mediaToggleButton(
                              icon: _snap.isCameraOff
                                  ? Icons.videocam_off_rounded
                                  : Icons.videocam_rounded,
                              onTap: () => unawaited(_calls.toggleCamera()),
                            ),
                            if (!kIsWeb) ...[
                              const SizedBox(width: 16),
                              _mediaToggleButton(
                                icon: Icons.cameraswitch_rounded,
                                onTap: () => unawaited(_calls.switchCamera()),
                              ),
                            ],
                          ],
                          if (!kIsWeb) ...[
                            const SizedBox(width: 16),
                            _mediaToggleButton(
                              icon: _speakerOn
                                  ? Icons.volume_up_rounded
                                  : Icons.phone_in_talk_rounded,
                              onTap: _toggleSpeaker,
                            ),
                          ],
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
                            icon: showVideoUi
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
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
        return _snap.isVideo ? 'Видеовызов…' : 'Вызов…';
      case VoiceCallPhase.connecting:
        return 'Соединение…';
      case VoiceCallPhase.connected:
        return 'На связи';
      case VoiceCallPhase.incoming:
        return _snap.isVideo ? 'Входящий видеозвонок' : 'Входящий звонок';
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
