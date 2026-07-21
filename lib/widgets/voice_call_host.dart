import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../main.dart' show navigatorKey;
import '../screens/group_voice_call_screen.dart';
import '../screens/voice_call_screen.dart';
import '../services/group_voice_call_service.dart';
import '../services/voice_call_service.dart';
import '../theme/app_colors.dart';

/// Opens DM or group call screens when a call becomes active; supports minimize.
class VoiceCallHost extends StatefulWidget {
  final String userId;
  final Widget child;

  const VoiceCallHost({
    super.key,
    required this.userId,
    required this.child,
  });

  @override
  State<VoiceCallHost> createState() => _VoiceCallHostState();
}

class _VoiceCallHostState extends State<VoiceCallHost> with WidgetsBindingObserver {
  StreamSubscription<VoiceCallSnapshot>? _dmSub;
  StreamSubscription<GroupCallSnapshot>? _groupSub;
  bool _routeOpen = false;
  bool _userMinimized = false;
  VoiceCallPhase? _lastDmPhase;
  GroupCallPhase? _lastGroupPhase;
  int _openAttempts = 0;
  Timer? _openRetryTimer;
  static const int _maxOpenAttempts = 10;

  bool get _anyActive =>
      VoiceCallService.instance.snapshot.isActive ||
      GroupVoiceCallService.instance.snapshot.isActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VoiceCallService.instance.bindUser(widget.userId);
    GroupVoiceCallService.instance.bindUser(widget.userId);
    _dmSub = VoiceCallService.instance.stateStream.listen(_onDmState);
    _groupSub = GroupVoiceCallService.instance.stateStream.listen(_onGroupState);
    _lastDmPhase = VoiceCallService.instance.snapshot.phase;
    _lastGroupPhase = GroupVoiceCallService.instance.snapshot.phase;
    if (_anyActive && !_userMinimized) {
      _scheduleOpenCallScreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openRetryTimer?.cancel();
    _dmSub?.cancel();
    _groupSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_anyActive && !_routeOpen && !_userMinimized) {
      _scheduleOpenCallScreen();
    }
  }

  void _onDmState(VoiceCallSnapshot snap) {
    if (_lastDmPhase == VoiceCallPhase.idle && snap.isActive) {
      _userMinimized = false;
    }
    _lastDmPhase = snap.phase;
    _handleActiveChange();
  }

  void _onGroupState(GroupCallSnapshot snap) {
    if (_lastGroupPhase == GroupCallPhase.idle && snap.isActive) {
      _userMinimized = false;
    }
    _lastGroupPhase = snap.phase;
    _handleActiveChange();
  }

  void _handleActiveChange() {
    if (_anyActive) {
      if (!_routeOpen && !_userMinimized) {
        _tryOpenCallScreen();
        _scheduleOpenCallScreen();
      }
      if (mounted) setState(() {});
      return;
    }
    _routeOpen = false;
    _userMinimized = false;
    _openAttempts = 0;
    if (mounted) setState(() {});
  }

  void _scheduleOpenCallScreen() {
    if (!mounted) return;
    if (_routeOpen || _userMinimized) return;
    if (!_anyActive) return;

    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenCallScreen());

    _openRetryTimer?.cancel();
    _openRetryTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (_routeOpen || _userMinimized) return;
      if (!_anyActive) return;
      _tryOpenCallScreen();
    });
  }

  NavigatorState? _rootNavigator() {
    final fromKey = navigatorKey.currentState;
    if (fromKey != null) return fromKey;
    if (!mounted) return null;
    return Navigator.maybeOf(context, rootNavigator: true);
  }

  void _expandCallScreen() {
    _userMinimized = false;
    _scheduleOpenCallScreen();
  }

  void _tryOpenCallScreen() {
    if (!mounted) return;
    if (!_anyActive || _routeOpen) return;

    final nav = _rootNavigator();
    if (nav == null) {
      _openAttempts++;
      if (_openAttempts < _maxOpenAttempts) {
        _openRetryTimer?.cancel();
        _openRetryTimer = Timer(
          Duration(milliseconds: 40 * _openAttempts),
          () {
            if (!mounted) return;
            _tryOpenCallScreen();
          },
        );
        SchedulerBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenCallScreen());
        return;
      }
      if (GroupVoiceCallService.instance.snapshot.isActive) {
        unawaited(GroupVoiceCallService.instance.abortActiveCall(
          'Не удалось открыть экран звонка',
        ));
      } else {
        unawaited(VoiceCallService.instance.abortActiveCall(
          'Не удалось открыть экран звонка',
        ));
      }
      return;
    }

    _openAttempts = 0;
    _openRetryTimer?.cancel();
    _routeOpen = true;
    _userMinimized = false;
    final openGroup = GroupVoiceCallService.instance.snapshot.isActive;
    nav
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => openGroup
                ? const GroupVoiceCallScreen()
                : const VoiceCallScreen(),
          ),
        )
        .whenComplete(() {
      if (!mounted) return;
      _routeOpen = false;
      if (_anyActive) {
        _userMinimized = true;
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dm = VoiceCallService.instance.snapshot;
    final group = GroupVoiceCallService.instance.snapshot;
    final showBanner = _anyActive && !_routeOpen && _userMinimized;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: group.isActive
                ? _GroupCallMinimizedBar(
                    snapshot: group,
                    onExpand: _expandCallScreen,
                    onLeave: () => unawaited(GroupVoiceCallService.instance.leave()),
                  )
                : _VoiceCallMinimizedBar(
                    snapshot: dm,
                    onExpand: _expandCallScreen,
                    onHangUp: () => unawaited(VoiceCallService.instance.hangUp()),
                  ),
          ),
      ],
    );
  }
}

class _VoiceCallMinimizedBar extends StatelessWidget {
  final VoiceCallSnapshot snapshot;
  final VoidCallback onExpand;
  final VoidCallback onHangUp;

  const _VoiceCallMinimizedBar({
    required this.snapshot,
    required this.onExpand,
    required this.onHangUp,
  });

  String get _status {
    switch (snapshot.phase) {
      case VoiceCallPhase.connected:
        return snapshot.statusMessage ?? 'На связи';
      case VoiceCallPhase.incoming:
        return snapshot.isVideo ? 'Входящий видеозвонок' : 'Входящий звонок';
      case VoiceCallPhase.outgoing:
        return snapshot.isVideo ? 'Видеовызов…' : 'Вызов…';
      case VoiceCallPhase.connecting:
        return 'Соединение…';
      default:
        return snapshot.statusMessage ?? 'Звонок';
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = (snapshot.peerLabel ?? 'Звонок').trim();
    return Material(
      color: AppColors.primaryDeep.withValues(alpha: 0.96),
      elevation: 6,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  snapshot.isVideo
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _status,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                  tooltip: 'Развернуть',
                  onPressed: onExpand,
                ),
                IconButton(
                  icon: Icon(Icons.call_end_rounded, color: Colors.red.shade300),
                  tooltip: 'Завершить',
                  onPressed: onHangUp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCallMinimizedBar extends StatelessWidget {
  final GroupCallSnapshot snapshot;
  final VoidCallback onExpand;
  final VoidCallback onLeave;

  const _GroupCallMinimizedBar({
    required this.snapshot,
    required this.onExpand,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final label = (snapshot.chatName ?? 'Групповой звонок').trim();
    final joined =
        snapshot.roster.where((p) => p.state == 'joined').length;
    return Material(
      color: AppColors.primaryDeep.withValues(alpha: 0.96),
      elevation: 6,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: onExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        snapshot.statusMessage ??
                            (joined > 0 ? 'В звонке: $joined' : 'Групповой звонок'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                  tooltip: 'Развернуть',
                  onPressed: onExpand,
                ),
                IconButton(
                  icon: Icon(Icons.call_end_rounded, color: Colors.red.shade300),
                  tooltip: 'Выйти',
                  onPressed: onLeave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
