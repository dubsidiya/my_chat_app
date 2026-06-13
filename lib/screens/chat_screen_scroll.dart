// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenScrollPart on _ChatScreenState {
  /// Прокрутить список к самому низу (к новым сообщениям).
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients && _messages.isNotEmpty) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          _scrollController.jumpTo(maxScroll);
        }
      }
    });
  }

  /// Более надежная прокрутка к низу: пробуем несколько раз,
  /// потому что при открытии чата layout может достраиваться не в один кадр.
  void _scrollToBottomWithRetry({
    int attempts = 3,
    Duration delay = const Duration(milliseconds: 80),
    VoidCallback? onFinished,
  }) {
    void tryScroll(int left) {
      if (!mounted || left <= 0) {
        onFinished?.call();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients && _messages.isNotEmpty) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(maxScroll.clamp(0.0, double.infinity));
        }
        if (left > 1) {
          Future.delayed(delay, () => tryScroll(left - 1));
        } else {
          onFinished?.call();
        }
      });
    }

    tryScroll(attempts);
  }

  /// Первичное открытие чата: держим низ, пока медиа и layout не стабилизируются.
  void _completeInitialOpenScroll() {
    _scrollToBottomUntilSettled(
      onFinished: () {
        if (mounted) {
          _didInitialOpenScrollToBottom = true;
        }
      },
    );
  }

  void _scrollToBottomUntilSettled({
    int maxAttempts = 24,
    Duration delay = const Duration(milliseconds: 100),
    VoidCallback? onFinished,
  }) {
    void tryScroll(int attempt, double? previousMaxExtent) {
      if (!mounted) return;
      if (attempt >= maxAttempts) {
        onFinished?.call();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients && _messages.isNotEmpty) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(maxScroll.clamp(0.0, double.infinity));
          if (ChatScrollPolicy.shouldStopInitialScrollSettling(
            attempt: attempt,
            maxAttempts: maxAttempts,
            previousMaxScrollExtent: previousMaxExtent,
            currentMaxScrollExtent: maxScroll,
            isNearBottom: _isNearBottom(),
          )) {
            onFinished?.call();
            return;
          }
          Future.delayed(delay, () => tryScroll(attempt + 1, maxScroll));
        } else {
          Future.delayed(delay, () => tryScroll(attempt + 1, previousMaxExtent));
        }
      });
    }

    tryScroll(0, null);
  }

  bool _isNearBottom({double threshold = 140}) {
    if (!_scrollController.hasClients) return true;
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

      // Сохраняем временные сообщения (если есть), чтобы не потерять офлайн/отправленные
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
    // Пока список скрыт спиннером или не завершён первичный скролл к низу,
    // не подгружаем старые сообщения — иначе чат «прыгает» в середину истории.
    if (!ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
      isLoading: _isLoading,
      didInitialOpenScrollToBottom: _didInitialOpenScrollToBottom,
      pixels: _scrollController.position.pixels,
    )) {
      return;
    }

    if (!_isLoadingMore && _hasMoreMessages && _messages.isNotEmpty) {
      _loadMoreMessages();
    }
  }
}
