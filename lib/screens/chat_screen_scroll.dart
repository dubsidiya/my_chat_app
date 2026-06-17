// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenScrollPart on _ChatScreenState {
  /// «У низа» (видны новые сообщения). В reverse-списке низ — смещение 0.
  /// До построения списка считаем, что мы у низа (чат открывается у новых).
  bool _isAtBottom({double threshold = 120}) {
    if (!_scrollController.hasClients) return true;
    return ChatScrollPolicy.isAtBottom(
      pixels: _scrollController.position.pixels,
      threshold: threshold,
    );
  }

  void _markInitialOpenComplete() {
    if (_initialOpenComplete) return;
    _initialOpenComplete = true;
  }

  /// Прокрутить к низу (к новым сообщениям). В reverse низ — это смещение 0:
  /// точное значение, поэтому ни прыжков к оценочному maxScrollExtent, ни
  /// «пружины» здесь нет. Если уже у низа — no-op.
  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels <= 0) return;
      if (animated) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// Переход к закреплённому сообщению. Если оно уже отрисовано — плавно
  /// прокручиваем через `ensureVisible`; иначе подгружаем историю вокруг него.
  Future<void> _goToPinnedMessage(Message pinned) async {
    _markInitialOpenComplete();
    final hasRenderedContext = _messageKeys[pinned.id]?.currentContext != null;
    if (hasRenderedContext) {
      await _scrollToMessage(pinned.id);
      _flashHighlight(pinned.id);
    } else {
      await _jumpToMessage(pinned.id);
    }
  }

  void _flashHighlight(String messageId) {
    if (!mounted) return;
    setState(() => _highlightMessageId = messageId);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_highlightMessageId == messageId) {
        setState(() => _highlightMessageId = null);
      }
    });
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
    // В reverse: верх списка (старые сообщения) — это близко к maxScrollExtent.
    if (!ChatScrollPolicy.shouldLoadMoreOnScroll(
      isLoading: _isLoading,
      initialOpenComplete: _initialOpenComplete,
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
    )) {
      return;
    }

    if (!_isLoadingMore && _hasMoreMessages && _messages.isNotEmpty) {
      _loadMoreMessages();
    }
  }
}
