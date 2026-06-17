// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenScrollPart on _ChatScreenState {
  /// Низ считается «достигнутым», если до него осталось меньше этого зазора.
  static const double _bottomReanchorEpsilon = 2;

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
      // Пользователь листает к старым сообщениям — перестаём «прилипать».
      _disableStickToBottom();
      _markInitialOpenComplete();
    } else if (direction == ScrollDirection.forward &&
        _scrollController.hasClients &&
        _isNearBottom()) {
      _enableStickToBottom();
    }
    return false;
  }

  /// Размеры контента изменились без участия пользователя (догрузилась картинка,
  /// раскрылся многострочный текст, добавилось сообщение). Это надёжная точка,
  /// чтобы удержать низ, пока пользователь «прилип» — в отличие от `_onScroll`,
  /// который при чистом росте контента не вызывается.
  bool _handleScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_stickToBottom) {
      _pinToBottomSoon();
    }
    return false;
  }

  /// Прыжок к низу после ближайшего кадра. Безопасно вызывать многократно:
  /// фактический `jumpTo` произойдёт, только если пользователь всё ещё «прилип».
  void _pinToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _pinToBottomNow());
  }

  void _pinToBottomNow() {
    if (!mounted || !_stickToBottom) return;
    if (!_scrollController.hasClients || _messages.isEmpty) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    if (max > 0 && (max - position.pixels) > _bottomReanchorEpsilon) {
      _scrollController.jumpTo(max);
    }
  }

  /// Несколько кадров подряд удерживаем низ — нужно при первом открытии и после
  /// собственной отправки, когда layout (или локальное медиа) может занять более
  /// одного кадра. Долгую асинхронную дозагрузку медиа добивает
  /// [_handleScrollMetricsNotification].
  void _pinToBottomRepeated(int attemptsLeft, {VoidCallback? onFinished}) {
    if (!mounted || !_stickToBottom || attemptsLeft <= 0) {
      onFinished?.call();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stickToBottom) {
        onFinished?.call();
        return;
      }
      _pinToBottomNow();
      _pinToBottomRepeated(attemptsLeft - 1, onFinished: onFinished);
    });
  }

  /// Принудительно «прилипнуть» к низу (после собственной отправки) и удержать
  /// его, пока подгружается медиа.
  void _stickAndPinToBottom() {
    _enableStickToBottom();
    _pinToBottomRepeated(3);
  }

  /// Автоскролл к низу при входящих сообщениях/после reload — только если
  /// пользователь уже «прилип» к низу.
  void _scrollToBottom() {
    if (!ChatScrollPolicy.shouldAutoScroll(stickToBottom: _stickToBottom)) {
      return;
    }
    _pinToBottomSoon();
  }

  /// Первичное открытие: «прилипаем» к низу и помечаем открытие завершённым.
  /// Дальше низ удерживается через [_handleScrollMetricsNotification], пока
  /// пользователь не пролистает вверх — это надёжнее подсчёта кадров/таймеров,
  /// когда последние сообщения это изображения, грузящиеся из сети.
  void _completeInitialOpenScroll() {
    if (_initialOpenComplete) return;
    _enableStickToBottom();
    _pinToBottomRepeated(3, onFinished: _markInitialOpenComplete);
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

  /// Переход к закреплённому сообщению. Если оно уже отрисовано — плавно
  /// прокручиваем через `ensureVisible`; иначе подгружаем историю вокруг него.
  Future<void> _goToPinnedMessage(Message pinned) async {
    // Пользователь явно прыгает по чату — снимаем «прилипание» к низу.
    _disableStickToBottom();
    _markInitialOpenComplete();

    final hasRenderedContext =
        _messageKeys[pinned.id]?.currentContext != null;
    if (hasRenderedContext) {
      await _scrollToMessage(pinned.id);
      _flashHighlight(pinned.id);
    } else {
      // Сообщение не в текущем окне списка — догружаем вокруг и прыгаем.
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

    // После первичного открытия: уход от низа сразу отклеивает (надёжнее на iOS).
    if (_initialOpenComplete &&
        _stickToBottom &&
        !ChatScrollPolicy.isNearBottom(
          pixels: position.pixels,
          maxScrollExtent: position.maxScrollExtent,
        )) {
      _disableStickToBottom();
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
