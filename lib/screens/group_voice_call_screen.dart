import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/group_voice_call_service.dart';
import '../theme/app_colors.dart';

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
  bool _speakerOn = true;
  bool _autoCloseScheduled = false;

  @override
  void initState() {
    super.initState();
    _snap = _calls.snapshot;
    _stateSub = _calls.stateStream.listen(_onState);
    _applySpeakerphone(_speakerOn);
  }

  void _onState(GroupCallSnapshot s) {
    if (!mounted) return;
    setState(() => _snap = s);
    if (s.phase == GroupCallPhase.ended ||
        s.phase == GroupCallPhase.failed ||
        s.phase == GroupCallPhase.idle) {
      _scheduleAutoClose();
    }
  }

  void _scheduleAutoClose() {
    if (_autoCloseScheduled) return;
    _autoCloseScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final phase = _calls.snapshot.phase;
      if (phase == GroupCallPhase.ended ||
          phase == GroupCallPhase.failed ||
          phase == GroupCallPhase.idle) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        _autoCloseScheduled = false;
      }
    });
  }

  void _minimize() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
    _applySpeakerphone(_speakerOn);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    if (!kIsWeb) _applySpeakerphone(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (_snap.chatName ?? 'Групповой звонок').trim();
    final isIncoming = _snap.phase == GroupCallPhase.incoming;
    final canControls = _snap.phase == GroupCallPhase.connected ||
        _snap.phase == GroupCallPhase.connecting;
    final status = _snap.statusMessage ?? _phaseLabel(_snap.phase);
    final joined = _snap.roster.where((p) => p.state == 'joined').toList();
    final ringing = _snap.roster.where((p) => p.state == 'ringing').toList();

    return PopScope(
      canPop: true,
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
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    if (joined.isNotEmpty) ...[
                      Text(
                        'В звонке (${joined.length})',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...joined.map(_peerTile),
                    ],
                    if (ringing.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Звоним…',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...ringing.map(_peerTile),
                    ],
                  ],
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
                      if (!kIsWeb) ...[
                        const SizedBox(width: 24),
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
                        label: 'Принять',
                        onTap: () => unawaited(_calls.acceptIncoming()),
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

  Widget _peerTile(GroupCallPeer peer) {
    final initial =
        peer.label.isNotEmpty ? peer.label[0].toUpperCase() : '?';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.25),
        child: Text(initial, style: const TextStyle(color: Colors.white)),
      ),
      title: Text(
        peer.label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        peer.state == 'joined' ? 'В звонке' : 'Вызов…',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
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
      case GroupCallPhase.incoming:
        return 'Входящий групповой звонок';
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
