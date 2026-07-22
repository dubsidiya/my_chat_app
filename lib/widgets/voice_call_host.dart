import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../main.dart' show navigatorKey;
import '../screens/group_voice_call_screen.dart';
import '../screens/voice_call_screen.dart';
import '../services/group_voice_call_service.dart';
import '../services/ios_callkit_service.dart';
import '../services/voice_call_service.dart';
import '../theme/app_colors.dart';

bool minimizedDmShouldReject(VoiceCallPhase phase) =>
    phase == VoiceCallPhase.incoming;

bool minimizedGroupShouldReject(GroupCallPhase phase) =>
    phase == GroupCallPhase.incoming;

bool shouldAutoOpenDmCall({
  required VoiceCallPhase phase,
  required bool callKitOwnsIncoming,
}) => phase != VoiceCallPhase.incoming || !callKitOwnsIncoming;

bool shouldAutoOpenGroupCall({
  required GroupCallPhase phase,
  required bool callKitOwnsIncoming,
}) => phase != GroupCallPhase.incoming || !callKitOwnsIncoming;

Future<void> performMinimizedDmEndAction({
  required VoiceCallPhase phase,
  required Future<void> Function() rejectIncoming,
  required Future<void> Function() hangUp,
}) {
  return minimizedDmShouldReject(phase) ? rejectIncoming() : hangUp();
}

Future<void> performMinimizedGroupEndAction({
  required GroupCallPhase phase,
  required Future<void> Function() rejectIncoming,
  required Future<void> Function() leave,
}) {
  return minimizedGroupShouldReject(phase) ? rejectIncoming() : leave();
}

/// Opens DM or group call screens when a call becomes active; supports minimize.
class VoiceCallHost extends StatefulWidget {
  final String userId;
  final Widget child;

  const VoiceCallHost({super.key, required this.userId, required this.child});

  @override
  State<VoiceCallHost> createState() => _VoiceCallHostState();
}

class _VoiceCallHostState extends State<VoiceCallHost>
    with WidgetsBindingObserver {
  StreamSubscription<VoiceCallSnapshot>? _dmSub;
  StreamSubscription<GroupCallSnapshot>? _groupSub;
  bool _routeOpen = false;
  bool _userMinimized = false;
  VoiceCallPhase? _lastDmPhase;
  GroupCallPhase? _lastGroupPhase;
  int _openAttempts = 0;
  Timer? _openRetryTimer;
  bool _openScheduled = false;
  static const int _maxNavNullAttempts = 40;

  bool get _anyActive =>
      VoiceCallService.instance.snapshot.isActive ||
      GroupVoiceCallService.instance.snapshot.isActive;

  bool get _hasRoutableCall {
    final dm = VoiceCallService.instance.snapshot;
    final group = GroupVoiceCallService.instance.snapshot;
    if (group.isActive) {
      return shouldAutoOpenGroupCall(
        phase: group.phase,
        callKitOwnsIncoming: IOSCallKitService.instance.ownsIncomingUI(
          group.callId,
        ),
      );
    }
    if (dm.isActive) {
      return shouldAutoOpenDmCall(
        phase: dm.phase,
        callKitOwnsIncoming: IOSCallKitService.instance.ownsIncomingUI(
          dm.callId,
        ),
      );
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VoiceCallService.instance.bindUser(widget.userId);
    GroupVoiceCallService.instance.bindUser(widget.userId);
    _dmSub = VoiceCallService.instance.stateStream.listen(_onDmState);
    _groupSub = GroupVoiceCallService.instance.stateStream.listen(
      _onGroupState,
    );
    _lastDmPhase = VoiceCallService.instance.snapshot.phase;
    _lastGroupPhase = GroupVoiceCallService.instance.snapshot.phase;
    if (_hasRoutableCall && !_userMinimized) {
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
    unawaited(VoiceCallService.instance.onNetworkOrAppResume());
    if (_hasRoutableCall && !_routeOpen && !_userMinimized) {
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
      if (_hasRoutableCall && !_routeOpen && !_userMinimized) {
        _scheduleOpenCallScreen();
      }
      if (mounted) setState(() {});
      return;
    }
    // Не сбрасываем _routeOpen пока экран ended ещё на стеке —
    // иначе новый звонок запушит второй route поверх.
    _userMinimized = false;
    _openAttempts = 0;
    if (mounted) setState(() {});
  }

  void _scheduleOpenCallScreen() {
    if (!mounted) return;
    if (_routeOpen || _userMinimized) return;
    if (!_hasRoutableCall) return;
    if (_openScheduled) return;
    _openScheduled = true;

    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openScheduled = false;
      _tryOpenCallScreen();
    });

    _openRetryTimer?.cancel();
    _openRetryTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (_routeOpen || _userMinimized) return;
      if (!_hasRoutableCall) return;
      _tryOpenCallScreen();
    });
  }

  NavigatorState? _rootNavigator() {
    final fromKey = navigatorKey.currentState;
    if (fromKey != null) {
      // Navigator появился после synthetic minimize — даём ещё попытки.
      if (_userMinimized && _openAttempts >= _maxNavNullAttempts) {
        _userMinimized = false;
        _openAttempts = 0;
      }
      return fromKey;
    }
    if (!mounted) return null;
    return Navigator.maybeOf(context, rootNavigator: true);
  }

  void _expandCallScreen() {
    _userMinimized = false;
    _openAttempts = 0;
    _scheduleOpenCallScreen();
  }

  void _tryOpenCallScreen() {
    if (!mounted) return;
    if (!_hasRoutableCall || _routeOpen || _userMinimized) return;

    final nav = _rootNavigator();
    if (nav == null) {
      _openAttempts++;
      if (_openAttempts > _maxNavNullAttempts) {
        // Не рвём звонок навсегда — останавливаем poll; user может expand
        // после появления navigator / тапа по баннеру.
        _userMinimized = true;
        if (mounted) setState(() {});
        return;
      }
      final delayMs = (80 * _openAttempts).clamp(80, 2000);
      _openRetryTimer?.cancel();
      _openRetryTimer = Timer(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        if (_routeOpen || _userMinimized || !_hasRoutableCall) return;
        _tryOpenCallScreen();
      });
      return;
    }

    _openAttempts = 0;
    _openRetryTimer?.cancel();
    _routeOpen = true;
    _userMinimized = false;
    final openGroup = GroupVoiceCallService.instance.snapshot.isActive;
    nav
        .push<String>(
          MaterialPageRoute<String>(
            fullscreenDialog: true,
            builder: (_) => openGroup
                ? const GroupVoiceCallScreen()
                : const VoiceCallScreen(),
          ),
        )
        .then((result) {
          if (!mounted) return;
          _routeOpen = false;
          if (!_anyActive) {
            _userMinimized = false;
            setState(() {});
            return;
          }
          // Явный minimize → banner. auto_close / иначе → открыть если ещё active.
          if (result == 'minimize') {
            _userMinimized = true;
            setState(() {});
            return;
          }
          _userMinimized = false;
          _scheduleOpenCallScreen();
          setState(() {});
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
                    onEnd: () => unawaited(
                      performMinimizedGroupEndAction(
                        phase: group.phase,
                        rejectIncoming: () =>
                            GroupVoiceCallService.instance.rejectIncoming(),
                        leave: () => GroupVoiceCallService.instance.leave(),
                      ),
                    ),
                  )
                : _VoiceCallMinimizedBar(
                    snapshot: dm,
                    onExpand: _expandCallScreen,
                    onEnd: () => unawaited(
                      performMinimizedDmEndAction(
                        phase: dm.phase,
                        rejectIncoming: () =>
                            VoiceCallService.instance.rejectIncoming(),
                        hangUp: () => VoiceCallService.instance.hangUp(),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _VoiceCallMinimizedBar extends StatelessWidget {
  final VoiceCallSnapshot snapshot;
  final VoidCallback onExpand;
  final VoidCallback onEnd;

  const _VoiceCallMinimizedBar({
    required this.snapshot,
    required this.onExpand,
    required this.onEnd,
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
                  icon: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Развернуть',
                  onPressed: onExpand,
                ),
                IconButton(
                  icon: Icon(
                    Icons.call_end_rounded,
                    color: Colors.red.shade300,
                  ),
                  tooltip: minimizedDmShouldReject(snapshot.phase)
                      ? 'Отклонить'
                      : 'Завершить',
                  onPressed: onEnd,
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
  final VoidCallback onEnd;

  const _GroupCallMinimizedBar({
    required this.snapshot,
    required this.onExpand,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final label = (snapshot.chatName ?? 'Групповой звонок').trim();
    final joined = snapshot.roster.where((p) => p.state == 'joined').length;
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
                      ? Icons.video_call_rounded
                      : Icons.groups_rounded,
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
                        snapshot.statusMessage ??
                            (joined > 0
                                ? 'В звонке: $joined'
                                : 'Групповой звонок'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Развернуть',
                  onPressed: onExpand,
                ),
                IconButton(
                  icon: Icon(
                    Icons.call_end_rounded,
                    color: Colors.red.shade300,
                  ),
                  tooltip: minimizedGroupShouldReject(snapshot.phase)
                      ? 'Отклонить'
                      : 'Выйти',
                  onPressed: onEnd,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
