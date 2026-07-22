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
    await _startCall(CallMediaType.audio);
  }

  Future<void> _startVideoCall() async {
    await _startCall(CallMediaType.video);
  }

  Future<void> _startCall(CallMediaType mediaType) async {
    if (widget.isGroup) return;
    try {
      final peerId = _peerUserIdForDm();
      if (peerId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось определить собеседника. Попробуйте позже.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        if (_chatMembers.isEmpty) {
          await _loadChatMembers();
          if (!mounted) return;
          final retry = _peerUserIdForDm();
          if (retry == null) return;
          return _startCallWithPeer(retry, mediaType);
        }
        return;
      }
      await _startCallWithPeer(peerId, mediaType);
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('chat_screen voice call start: $e\n$st');
      }
      if (mounted) {
        _showVoiceCallStartError('Не удалось начать звонок: ${_shortErr(e)}');
      }
    }
  }

  String _shortErr(Object e) {
    final raw = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isEmpty) return 'неизвестная ошибка';
    return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
  }

  Future<void> _startCallWithPeer(
    String peerId,
    CallMediaType mediaType,
  ) async {
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
      mediaType: mediaType,
    );
    if (!ok && mounted) {
      _showVoiceCallStartError();
    }
  }

  void _showVoiceCallStartError([String? overrideMessage]) {
    final msg =
        overrideMessage ??
        VoiceCallService.instance.snapshot.statusMessage ??
        GroupVoiceCallService.instance.snapshot.statusMessage ??
        'Не удалось начать звонок';
    final permanent =
        VoiceCallService.instance.lastMicrophoneAccess ==
            MicrophoneAccess.permanentlyDenied ||
        GroupVoiceCallService.instance.lastMicrophoneAccess ==
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

  Future<void> _startGroupVoiceCall() async {
    if (!widget.isGroup) return;
    final mediaType = await showModalBottomSheet<GroupCallMediaType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_rounded),
              title: const Text('Аудиозвонок'),
              onTap: () => Navigator.pop(context, GroupCallMediaType.audio),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('Видеозвонок'),
              subtitle: const Text('Камеру можно выключить в любой момент'),
              onTap: () => Navigator.pop(context, GroupCallMediaType.video),
            ),
          ],
        ),
      ),
    );
    if (mediaType == null || !mounted) return;
    await _startSelectedGroupCall(mediaType);
  }

  Future<void> _startSelectedGroupCall(GroupCallMediaType mediaType) async {
    try {
      try {
        await _voicePlayer.pause();
      } catch (_) {}
      if (_isRecordingVoice) {
        await _cancelVoiceRecording();
      }
      final name = _chatTitle.trim().isNotEmpty ? _chatTitle : widget.chatName;
      final ok = await GroupVoiceCallService.instance.startGroupCall(
        chatId: widget.chatId,
        chatName: name,
        mediaType: mediaType,
      );
      if (!ok && mounted) {
        _showVoiceCallStartError();
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('chat_screen group call start: $e\n$st');
      }
      if (mounted) {
        _showVoiceCallStartError('Не удалось начать звонок: ${_shortErr(e)}');
      }
    }
  }
}
