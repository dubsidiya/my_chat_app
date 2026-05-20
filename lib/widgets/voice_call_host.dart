import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../main.dart' show navigatorKey;
import '../screens/voice_call_screen.dart';
import '../services/voice_call_service.dart';
import '../theme/app_colors.dart';

/// Opens [VoiceCallScreen] when a call becomes active; supports minimize (banner).
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
  StreamSubscription<VoiceCallSnapshot>? _sub;
  bool _routeOpen = false;
  bool _userMinimized = false;
  VoiceCallPhase? _lastPhase;
  int _openAttempts = 0;
  Timer? _openRetryTimer;
  static const int _maxOpenAttempts = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VoiceCallService.instance.bindUser(widget.userId);
    _sub = VoiceCallService.instance.stateStream.listen(_onCallState);
    final snap = VoiceCallService.instance.snapshot;
    _lastPhase = snap.phase;
    if (snap.isActive && !_userMinimized) {
      _scheduleOpenCallScreen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openRetryTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final snap = VoiceCallService.instance.snapshot;
    if (snap.isActive && !_routeOpen && !_userMinimized) {
      _scheduleOpenCallScreen();
    }
  }

  void _onCallState(VoiceCallSnapshot snap) {
    if (_lastPhase == VoiceCallPhase.idle && snap.isActive) {
      _userMinimized = false;
    }
    _lastPhase = snap.phase;

    if (snap.isActive) {
      if (!_routeOpen && !_userMinimized) {
        // Сразу, без postFrameCallback — иначе на iOS экран может ждать касания.
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
    if (!VoiceCallService.instance.snapshot.isActive) return;

    // На iOS при статичном UI кадры иногда не идут, пока пользователь не коснётся
    // экрана — тогда addPostFrameCallback не срабатывает и звонок «висит» в памяти.
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenCallScreen());

    _openRetryTimer?.cancel();
    _openRetryTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (_routeOpen || _userMinimized) return;
      if (!VoiceCallService.instance.snapshot.isActive) return;
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
    if (!VoiceCallService.instance.snapshot.isActive || _routeOpen) return;

    final nav = _rootNavigator();
    if (nav == null) {
      _openAttempts++;
      if (_openAttempts < _maxOpenAttempts) {
        // Только отложенный retry: microtask/postFrame в цикле давали 10 попыток
        // за один тик и abortActiveCall() до появления Navigator.
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
      unawaited(VoiceCallService.instance.abortActiveCall(
        'Не удалось открыть экран звонка',
      ));
      return;
    }

    _openAttempts = 0;
    _openRetryTimer?.cancel();
    _routeOpen = true;
    _userMinimized = false;
    nav
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const VoiceCallScreen(),
          ),
        )
        .whenComplete(() {
      if (!mounted) return;
      _routeOpen = false;
      if (VoiceCallService.instance.snapshot.isActive) {
        _userMinimized = true;
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = VoiceCallService.instance.snapshot;
    final showBanner = snap.isActive && !_routeOpen && _userMinimized;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _VoiceCallMinimizedBar(
              snapshot: snap,
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
        return 'Входящий звонок';
      case VoiceCallPhase.outgoing:
        return 'Вызов…';
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
                const Icon(Icons.call_rounded, color: Colors.white, size: 22),
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
