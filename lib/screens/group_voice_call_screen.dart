import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../services/group_voice_call_service.dart';
import '../theme/app_colors.dart';
import '../utils/call_route_close_gate.dart';
import '../utils/microphone_permission.dart';

/// Full-screen UI for an active or ringing group voice call.
class GroupVoiceCallScreen extends StatefulWidget {
  const GroupVoiceCallScreen({super.key});

  @override
  State<GroupVoiceCallScreen> createState() => _GroupVoiceCallScreenState();
}

class _GroupVoiceCallScreenState extends State<GroupVoiceCallScreen> {
  final GroupVoiceCallService _calls = GroupVoiceCallService.instance;
  GroupCallSnapshot _snap = GroupVoiceCallService.instance.snapshot;
  StreamSubscription<GroupCallSnapshot>? _stateSub;
  late bool _speakerOn;
  bool _autoCloseScheduled = false;
  final CallRouteCloseGate _closeGate = CallRouteCloseGate();
  String? _boundCallId;

  @override
  void initState() {
    super.initState();
    _snap = _calls.snapshot;
    _boundCallId = _snap.callId;
    _speakerOn = _calls.preferredSpeakerOn;
    _stateSub = _calls.stateStream.listen(_onState);
    _applySpeakerphone(_speakerOn);
  }

  void _onState(GroupCallSnapshot s) {
    if (!mounted) return;
    setState(() {
      _snap = s;
      _speakerOn = s.isSpeakerOn;
    });
    if (s.phase == GroupCallPhase.connected ||
        s.phase == GroupCallPhase.reconnecting) {
      _applySpeakerphone(_speakerOn);
    }
    if (s.phase == GroupCallPhase.failed &&
        (s.statusMessage?.contains('микрофон') ?? false)) {
      _showMicrophoneDeniedHint();
      return;
    }
    if (s.phase == GroupCallPhase.ended ||
        s.phase == GroupCallPhase.failed ||
        s.phase == GroupCallPhase.idle) {
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
      if (phase == GroupCallPhase.ended ||
          phase == GroupCallPhase.failed ||
          phase == GroupCallPhase.idle ||
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

  void _showMicrophoneDeniedHint() {
    final denied =
        _calls.lastMicrophoneAccess != null &&
        _calls.lastMicrophoneAccess != MicrophoneAccess.granted;
    if (!denied) {
      _scheduleAutoClose();
      return;
    }
    if (!_closeGate.beginDialog()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _closeGate.endDialog();
        return;
      }
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Нужен микрофон'),
          content: const Text(
            kIsWeb
                ? 'Разрешите микрофон для этого сайта в настройках браузера '
                      '(иконка замка в адресной строке), затем повторите звонок.'
                : 'Разрешите доступ к микрофону в Настройках → Reollity → '
                      'Микрофон, затем повторите звонок.',
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
      ).whenComplete(() {
        final deferredClose = _closeGate.endDialog();
        if (!mounted) return;
        final phase = _calls.snapshot.phase;
        final terminal =
            phase == GroupCallPhase.ended ||
            phase == GroupCallPhase.failed ||
            phase == GroupCallPhase.idle;
        if (deferredClose || terminal) _scheduleAutoClose();
      });
    });
  }

  void _minimize() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop('minimize');
    }
  }

  void _applySpeakerphone(bool enabled) {
    if (_snap.transport == GroupCallTransport.livekit) {
      _calls.setPreferredSpeakerOn(enabled);
      return;
    }
    if (kIsWeb) return;
    try {
      Helper.setSpeakerphoneOn(enabled);
    } catch (_) {}
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    _calls.setPreferredSpeakerOn(_speakerOn);
    if (_snap.transport == GroupCallTransport.mesh) {
      _applySpeakerphone(_speakerOn);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    if (!kIsWeb && !_calls.snapshot.isActive) {
      _applySpeakerphone(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (_snap.chatName ?? 'Групповой звонок').trim();
    final isIncoming = _snap.phase == GroupCallPhase.incoming;
    final canControls =
        _snap.phase == GroupCallPhase.connected ||
        _snap.phase == GroupCallPhase.connecting ||
        _snap.phase == GroupCallPhase.reconnecting;
    final status = _snap.statusMessage ?? _phaseLabel(_snap.phase);
    final joined = _snap.roster.where((p) => p.state == 'joined').toList()
      ..sort((a, b) {
        if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
        if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
        return a.label.compareTo(b.label);
      });
    final ringing = _snap.roster
        .where(
          (p) =>
              p.state == 'ringing' ||
              p.state == 'invited' ||
              p.state == 'joining',
        )
        .toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _minimize();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurface,
                  ),
                  tooltip: 'Свернуть',
                  onPressed: _minimize,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  title,
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
              const SizedBox(height: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (joined.isNotEmpty)
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: joined.length == 1 ? 1 : 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: joined.length == 1
                                      ? 0.95
                                      : 0.78,
                                ),
                            itemCount: joined.length,
                            itemBuilder: (context, index) =>
                                _participantTile(joined[index]),
                          ),
                        )
                      else
                        const Spacer(),
                      if (ringing.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Ожидаем: ${ringing.map((p) => p.label).join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.62),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              if (_snap.webAudioBlocked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    onPressed: () => unawaited(_calls.recoverWebAudio()),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('Включить звук'),
                  ),
                ),
              if (canControls)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _toggleBtn(
                        icon: _snap.isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        onTap: () => unawaited(_calls.toggleMute()),
                      ),
                      if (_snap.transport == GroupCallTransport.livekit) ...[
                        const SizedBox(width: 16),
                        _toggleBtn(
                          icon: _snap.isCameraEnabled
                              ? Icons.videocam_rounded
                              : Icons.videocam_off_rounded,
                          onTap: () => unawaited(_calls.toggleCamera()),
                        ),
                        if (_snap.isCameraEnabled) ...[
                          const SizedBox(width: 16),
                          _toggleBtn(
                            icon: Icons.cameraswitch_rounded,
                            onTap: () => unawaited(_calls.switchCamera()),
                          ),
                        ],
                      ],
                      if (!kIsWeb) ...[
                        const SizedBox(width: 16),
                        _toggleBtn(
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
                      _roundBtn(
                        color: Colors.red.shade600,
                        icon: Icons.call_end_rounded,
                        label: 'Отклонить',
                        onTap: () => unawaited(_calls.rejectIncoming()),
                      ),
                      _roundBtn(
                        color: Colors.green.shade600,
                        icon: Icons.call_rounded,
                        label: _snap.mediaType == GroupCallMediaType.video
                            ? 'С аудио'
                            : 'Принять',
                        onTap: () =>
                            unawaited(_calls.acceptIncoming(withVideo: false)),
                      ),
                      if (_snap.mediaType == GroupCallMediaType.video)
                        _roundBtn(
                          color: Colors.green.shade700,
                          icon: Icons.videocam_rounded,
                          label: 'С видео',
                          onTap: () =>
                              unawaited(_calls.acceptIncoming(withVideo: true)),
                        ),
                    ] else
                      _roundBtn(
                        color: Colors.red.shade600,
                        icon: Icons.call_end_rounded,
                        label: 'Выйти',
                        onTap: () => unawaited(_calls.leave()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _participantTile(GroupCallPeer peer) {
    final initial = peer.label.isNotEmpty ? peer.label[0].toUpperCase() : '?';
    final track = peer.videoTrack;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: peer.isSpeaking
              ? Colors.greenAccent
              : Colors.white.withValues(alpha: 0.08),
          width: peer.isSpeaking ? 2.5 : 1,
        ),
        boxShadow: peer.isSpeaking
            ? [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track is lk.VideoTrack && peer.isCameraEnabled)
            lk.VideoTrackRenderer(
              track,
              fit: lk.VideoViewFit.cover,
              mirrorMode: peer.isLocal
                  ? lk.VideoViewMirrorMode.mirror
                  : lk.VideoViewMirrorMode.off,
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.45),
                    AppColors.primaryDeep.withValues(alpha: 0.72),
                  ],
                ),
              ),
              child: Center(
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 28, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        peer.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (peer.connectionQuality == 'poor')
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.signal_cellular_alt_1_bar_rounded,
                          color: Colors.orangeAccent,
                          size: 18,
                        ),
                      ),
                    Icon(
                      peer.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: peer.isMuted ? Colors.redAccent : Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(GroupCallPhase phase) {
    switch (phase) {
      case GroupCallPhase.outgoing:
        return 'Создаём звонок…';
      case GroupCallPhase.connecting:
        return 'Подключение…';
      case GroupCallPhase.connected:
        return 'На связи';
      case GroupCallPhase.reconnecting:
        return 'Восстанавливаем соединение…';
      case GroupCallPhase.incoming:
        return _snap.mediaType == GroupCallMediaType.video
            ? 'Входящий групповой видеозвонок'
            : 'Входящий групповой звонок';
      default:
        return '';
    }
  }

  Widget _toggleBtn({required IconData icon, required VoidCallback onTap}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 28),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _roundBtn({
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
