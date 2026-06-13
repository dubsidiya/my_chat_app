// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenScrollPart on _ChatScreenState {
  void _enableStickToBottom() {
    _stickToBottom = true;
  }

  void _disableStickToBottom() {
    _stickToBottom = false;
  }

  void _markInitialOpenComplete() {
    if (_initialOpenComplete) return;
    _initialOpenComplete = true;
  }

  bool _handleUserScrollNotification(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    final direction = notification.direction;
    if (direction == ScrollDirection.reverse) {
      _disableStickToBottom();
      _markInitialOpenComplete();
    } else if (direction == ScrollDirection.forward &&
        _scrollController.hasClients &&
        _isNearBottom()) {
      _enableStickToBottom();
    }
    return false;
  }

  void _scrollToBottom() {
    if (!ChatScrollPolicy.shouldAutoScroll(stickToBottom: _stickToBottom)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stickToBottom) return;
      _jumpToBottomIfPossible();
    });
  }

  void _jumpToBottomIfPossible() {
    if (!_scrollController.hasClients || _messages.isEmpty) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      _scrollController.jumpTo(maxScroll);
    }
  }

  void _scrollToBottomWithRetry({
    int attempts = 3,
    Duration delay = const Duration(milliseconds: 80),
    VoidCallback? onFinished,
  }) {
    _enableStickToBottom();
    _scrollToBottomAfterLayout(
      attempts: attempts,
      delay: delay,
      onFinished: onFinished,
    );
  }

  void _completeInitialOpenScroll() {
    _enableStickToBottom();
    _scrollToBottomAfterLayout(
      attempts: 3,
      onFinished: _markInitialOpenComplete,
    );
  }

  void _scrollToBottomAfterLayout({
    int attempts = 3,
    Duration delay = const Duration(milliseconds: 80),
    VoidCallback? onFinished,
  }) {
    void tryScroll(int left) {
      if (!mounted || left <= 0 || !_stickToBottom) {
        onFinished?.call();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_stickToBottom) {
          onFinished?.call();
          return;
        }
        _jumpToBottomIfPossible();
        if (left > 1) {
          Future.delayed(delay, () => tryScroll(left - 1));
        } else {
          onFinished?.call();
        }
      });
    }

    tryScroll(attempts);
  }

  bool _isNearBottom({double threshold = 140}) {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return ChatScrollPolicy.isNearBottom(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
      threshold: threshold,
    );
  }

  Future<void> _scrollToMessage(String messageId) async {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  Future<void> _jumpToMessage(String messageId) async {
    try {
      final around = await _messagesService.fetchMessagesAround(
        widget.chatId,
        messageId,
        limit: 50,
      );
      if (!mounted) return;

      final temp = _messages.where((m) => m.id.startsWith('temp_')).toList();
      final aroundIds = around.map((m) => m.id).toSet();
      final uniqueTemp = temp.where((m) => !aroundIds.contains(m.id)).toList();

      final minId = around
          .map((m) => int.tryParse(m.id) ?? 1 << 30)
          .fold<int>(1 << 30, (a, b) => a < b ? a : b);

      setState(() {
        _messages = [...around, ...uniqueTemp];
        _messages.sort((a, b) {
          try {
            return DateTime.parse(
              a.createdAt,
            ).compareTo(DateTime.parse(b.createdAt));
          } catch (_) {
            return 0;
          }
        });
        _oldestMessageId = (minId == (1 << 30)) ? null : minId.toString();
        _hasMoreMessages = true;
        _highlightMessageId = messageId;
      });

      _disableStickToBottom();
      _markInitialOpenComplete();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _scrollToMessage(messageId);
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_highlightMessageId == messageId) {
          setState(() => _highlightMessageId = null);
        }
      });
    } catch (e) {
      if (kDebugMode) print('Ошибка перехода к сообщению: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Не удалось перейти к сообщению'),
        ),
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
      stickToBottom: _stickToBottom,
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
    )) {
      position.jumpTo(position.maxScrollExtent);
    }

    if (!ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
      isLoading: _isLoading,
      initialOpenComplete: _initialOpenComplete,
      pixels: position.pixels,
    )) {
      return;
    }

    if (!_isLoadingMore && _hasMoreMessages && _messages.isNotEmpty) {
      _loadMoreMessages();
    }
  }
}
