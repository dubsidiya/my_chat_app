// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenMessagesSyncPart on _ChatScreenState {
  Future<void> _loadMessages() async {
    if (!mounted) return;
    // Были ли мы у низа до перезагрузки — чтобы решить, возвращать ли к низу.
    final wasAtBottom = _isAtBottom();

    setState(() {
      _isLoading = true;
      _hasMoreMessages = true;
      _oldestMessageId = null;
    });

    // Восстанавливаем отложенные вложения/голосовые, пережившие перезапуск приложения.
    await _restorePendingUploadDrafts();

    // ✅ Сначала загружаем из кэша для быстрого отображения
    final existingTempMessages = _messages
        .where(
          (m) =>
              m.id.startsWith('temp_') && m.userId == widget.userId.toString(),
        )
        .toList();

    try {
      final cachedMessages = await LocalMessagesService.getMessages(
        widget.chatId,
      );
      if (cachedMessages.isNotEmpty && mounted) {
        setState(() {
          // ✅ Сохраняем временные сообщения при загрузке из кэша
          final cachedIds = cachedMessages.map((m) => m.id).toSet();
          final uniqueTempMessages = existingTempMessages
              .where((m) => !cachedIds.contains(m.id))
              .toList();
          // старые сверху, временные (новые) в конце
          _messages = [...cachedMessages, ...uniqueTempMessages];
          _markMessagesSeen(_messages.map((m) => m.id));
        });
        if (kDebugMode) {
          print('✅ Загружено ${cachedMessages.length} сообщений из кэша');
        }
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Ошибка загрузки из кэша: $e');
    }

    // ✅ Затем загружаем с сервера и обновляем
    try {
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: _ChatScreenState._messagesPerPage,
        offset: 0,
        useCache:
            false, // ✅ НЕ используем кэш при загрузке с сервера, чтобы не перезаписывать текущие сообщения
      );

      if (mounted) {
        setState(() {
          // ✅ Объединяем существующие сообщения с новыми (сохраняем временные сообщения)
          final currentTempMessages = _messages
              .where(
                (m) =>
                    m.id.startsWith('temp_') &&
                    m.userId == widget.userId.toString(),
              )
              .toList();
          final newMessages = result.messages;

          // ✅ Удаляем дубликаты и сохраняем временные сообщения
          final existingIds = newMessages.map((m) => m.id).toSet();
          final uniqueTempMessages = currentTempMessages
              .where((m) => !existingIds.contains(m.id))
              .toList();

          // старые сверху, новые снизу: серверные сообщения + временные в конце
          _messages = [...newMessages, ...uniqueTempMessages];
          _hasMoreMessages = result.hasMore;
          _oldestMessageId = result.oldestMessageId;
          _markMessagesSeen(_messages.map((m) => m.id));
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading messages: $e');
      // ✅ Если ошибка, но есть кэш - не показываем ошибку
      if (_messages.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка загрузки сообщений: ${networkErrorMessage(e)}',
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => _loadMessages(),
            ),
          ),
        );
      } else if (mounted) {
        // Показываем уведомление об офлайн режиме
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Офлайн режим. Показаны сохраненные сообщения.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        // reverse:true → чат открывается у низа сам, прокрутка не нужна.
        // При pull-to-refresh: если были у низа — останемся у низа; при чтении
        // истории позиция сохраняется reverse-списком.
        if (wasAtBottom) _scrollToBottom(animated: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _markInitialOpenComplete();
        });
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!mounted || _isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      // Загружаем старые сообщения
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: _ChatScreenState._messagesPerPage,
        beforeMessageId: _oldestMessageId,
        useCache: false,
      );

      if (mounted && result.messages.isNotEmpty) {
        setState(() {
          // Добавляем старые сообщения в начало списка
          _messages.insertAll(0, result.messages);
          // Удаляем дубликаты (на случай если сообщение уже есть)
          final seen = <String>{};
          _messages.removeWhere((msg) {
            final id = msg.id.toString();
            if (seen.contains(id)) {
              return true;
            }
            seen.add(id);
            return false;
          });
          // Сортируем по времени
          _messages.sort((a, b) {
            try {
              final aTime = DateTime.parse(a.createdAt);
              final bTime = DateTime.parse(b.createdAt);
              return aTime.compareTo(bTime);
            } catch (e) {
              return 0;
            }
          });

          _hasMoreMessages = result.hasMore;
          _oldestMessageId = result.oldestMessageId;
          _markMessagesSeen(result.messages.map((m) => m.id));
        });

        // В ListView(reverse: true) старые сообщения добавляются «выше» якоря-низа
        // и не сдвигают видимую область — позиция сохраняется автоматически,
        // без ручного пересчёта maxScrollExtent.
      } else if (mounted) {
        // Если нет новых сообщений, значит больше загружать нечего
        setState(() {
          _hasMoreMessages = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Error loading more messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка загрузки сообщений: ${networkErrorMessage(e)}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }
}
