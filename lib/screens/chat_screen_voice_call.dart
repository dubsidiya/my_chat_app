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
  }

  Future<void> _startVoiceCallWithPeer(String peerId) async {
    final label = _chatTitle.trim().isNotEmpty ? _chatTitle : widget.chatName;
    final ok = await VoiceCallService.instance.startOutgoingCall(
      chatId: widget.chatId,
      peerUserId: peerId,
      peerLabel: label,
    );
    if (!ok && mounted) {
      final msg = VoiceCallService.instance.snapshot.statusMessage;
      if (msg != null && msg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
        );
      }
    }
  }
}
