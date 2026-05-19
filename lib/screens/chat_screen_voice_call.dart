part of 'chat_screen.dart';

extension _ChatScreenVoiceCallPart on _ChatScreenState {
  String? _peerUserIdForDm() {
    if (widget.isGroup) return null;
    for (final m in _chatMembers) {
      final id = (m['id'] ?? '').toString();
      if (id.isNotEmpty && id != widget.userId) return id;
    }
    return null;
  }

  Future<void> _startVoiceCall() async {
    if (widget.isGroup) return;
    try {
      final peerId = _peerUserIdForDm();
      if (peerId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось определить собеседника. Попробуйте позже.'),
            duration: Duration(seconds: 3),
          ),
        );
        if (_chatMembers.isEmpty) {
          await _loadChatMembers();
          if (!mounted) return;
          final retry = _peerUserIdForDm();
          if (retry == null) return;
          return _startVoiceCallWithPeer(retry);
        }
        return;
      }
      await _startVoiceCallWithPeer(peerId);
    } catch (_) {
      if (mounted) {
        _showVoiceCallStartError('Не удалось начать звонок');
      }
    }
  }

  Future<void> _startVoiceCallWithPeer(String peerId) async {
    // Освобождаем аудиосессию от just_audio (голосовые сообщения), иначе WebRTC на iOS
    // часто не получает микрофон.
    try {
      await _voicePlayer.pause();
    } catch (_) {}
    if (_isRecordingVoice) {
      await _cancelVoiceRecording();
    }

    final label = _chatTitle.trim().isNotEmpty ? _chatTitle : widget.chatName;
    final ok = await VoiceCallService.instance.startOutgoingCall(
      chatId: widget.chatId,
      peerUserId: peerId,
      peerLabel: label,
    );
    if (!ok && mounted) {
      _showVoiceCallStartError();
    }
  }

  void _showVoiceCallStartError([String? overrideMessage]) {
    final msg = overrideMessage ??
        VoiceCallService.instance.snapshot.statusMessage ??
        'Не удалось начать звонок';
    final permanent = VoiceCallService.instance.lastMicrophoneAccess ==
        MicrophoneAccess.permanentlyDenied;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 5),
        action: permanent
            ? SnackBarAction(
                label: 'Настройки',
                onPressed: () {
                  unawaited(MicrophonePermission.openSettings());
                },
              )
            : null,
      ),
    );
  }
}
