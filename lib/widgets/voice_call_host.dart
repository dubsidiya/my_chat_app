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

  @override
  void initState() {
    super.initState();
    VoiceCallService.instance.bindUser(widget.userId);
    _sub = VoiceCallService.instance.stateStream.listen(_onCallState);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onCallState(VoiceCallSnapshot snap) {
    if (snap.isActive && !_routeOpen) {
      _routeOpen = true;
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const VoiceCallScreen(),
        ),
      ).whenComplete(() {
        _routeOpen = false;
      });
      return;
    }
    if (!snap.isActive) {
      _routeOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
