import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart' show navigatorKey;
import '../screens/voice_call_screen.dart';
import '../services/voice_call_service.dart';

/// Opens [VoiceCallScreen] when a call becomes active (global, not tied to chat route).
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

class _VoiceCallHostState extends State<VoiceCallHost> {
  StreamSubscription<VoiceCallSnapshot>? _sub;
  bool _routeOpen = false;
  int _openAttempts = 0;
  static const int _maxOpenAttempts = 10;

  @override
  void initState() {
    super.initState();
    VoiceCallService.instance.bindUser(widget.userId);
    _sub = VoiceCallService.instance.stateStream.listen(_onCallState);
    if (VoiceCallService.instance.snapshot.isActive) {
      _scheduleOpenCallScreen();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onCallState(VoiceCallSnapshot snap) {
    if (snap.isActive) {
      if (!_routeOpen) {
        _scheduleOpenCallScreen();
      }
      return;
    }
    _routeOpen = false;
    _openAttempts = 0;
  }

  void _scheduleOpenCallScreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenCallScreen());
  }

  void _tryOpenCallScreen() {
    if (!mounted) return;
    if (!VoiceCallService.instance.snapshot.isActive || _routeOpen) return;

    final nav = navigatorKey.currentState;
    if (nav == null) {
      _openAttempts++;
      if (_openAttempts < _maxOpenAttempts) {
        _scheduleOpenCallScreen();
        return;
      }
      unawaited(VoiceCallService.instance.abortActiveCall(
        'Не удалось открыть экран звонка',
      ));
      return;
    }

    _openAttempts = 0;
    _routeOpen = true;
    nav
        .push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const VoiceCallScreen(),
          ),
        )
        .whenComplete(() {
      _routeOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
