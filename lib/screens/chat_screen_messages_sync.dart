// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenMessagesSyncPart on _ChatScreenState {
  Future<void> _loadMessages() async {
    if (!mounted) return;
    // Были ли мы у низа до перезагрузки — чтобы решить, возвращать ли к низу.
    final wasAtBottom = _isAtBottom();
    final loadGen = ++_messagesLoadGen;
    final decryptGen = loadGen;
    _cacheDecryptGen = decryptGen;
    final keepVisible = _messages.isNotEmpty;

    setState(() {
      if (!keepVisible) _isLoading = true;
      _hasMoreMessages = true;
      _oldestMessageId = null;
    });

    // Восстанавливаем отложенные вложения/голосовые, пережившие перезапуск приложения.
    await _restorePendingUploadDrafts();

    // Кэш показываем сразу. Расшифровка идёт следом и не держит спиннер.
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
      final visibleCached = cachedMessages
          .where((m) => !BlockedUsersCache.isBlocked(m.userId))
          .map(messageForImmediateDisplay)
          .toList();
      if (visibleCached.isNotEmpty && mounted && loadGen == _messagesLoadGen) {
        setState(() {
          final cachedIds = visibleCached.map((m) => m.id).toSet();
          final uniqueTempMessages = existingTempMessages
              .where((m) => !cachedIds.contains(m.id))
              .toList();
          _messages = [...visibleCached, ...uniqueTempMessages];
          _isLoading = false;
          _markMessagesSeen(_messages.map((m) => m.id));
        });
        unawaited(
          _decryptCachedMessages(
            cachedMessages
                .where((m) => !BlockedUsersCache.isBlocked(m.userId))
                .toList(),
            decryptGen,
          ),
        );
        if (kDebugMode) {
          print('✅ Показано ${visibleCached.length} сообщений из кэша');
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
        useCache: true,
      );

      if (mounted && loadGen == _messagesLoadGen) {
        if (_cacheDecryptGen == decryptGen) _cacheDecryptGen++;
        setState(() {
          final currentTempMessages = _messages
              .where(
                (m) =>
                    m.id.startsWith('temp_') &&
                    m.userId == widget.userId.toString(),
              )
              .toList();
          final serverMessages = result.messages
              .where((m) => !BlockedUsersCache.isBlocked(m.userId))
              .toList();
          final existingHistory = _messages
              .where((m) => !m.id.startsWith('temp_'))
              .toList();
          final merged = mergeMessageCache(
            existing: existingHistory,
            incoming: serverMessages,
            evictMissingInWindow: true,
          );
          final existingIds = merged.map((m) => m.id).toSet();
          final uniqueTempMessages = currentTempMessages
              .where((m) => !existingIds.contains(m.id))
              .toList();

          _messages = [...merged, ...uniqueTempMessages];
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
      if (mounted && loadGen == _messagesLoadGen) {
        if (_isLoading) {
          setState(() => _isLoading = false);
        }
        // reverse:true → чат открывается у низа сам, прокрутка не нужна.
        // При pull-to-refresh: если были у низа — останемся у низа; при чтении
        // истории позиция сохраняется reverse-списком.
        if (wasAtBottom) _scrollToBottom(animated: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && loadGen == _messagesLoadGen) _markInitialOpenComplete();
        });
      }
    }
  }

  Future<void> _decryptCachedMessages(List<Message> raw, int decryptGen) async {
    const batchSize = 4;
    for (var start = 0; start < raw.length; start += batchSize) {
      if (!mounted || decryptGen != _cacheDecryptGen) return;
      final end = start + batchSize < raw.length ? start + batchSize : raw.length;
      final decrypted = await Future.wait(
        raw.sublist(start, end).map(
          (message) => MessagesDecrypt.decryptOne(widget.chatId, message),
        ),
      );
      if (!mounted || decryptGen != _cacheDecryptGen) return;
      final patched = patchDecryptedPreviews(_messages, decrypted);
      if (patched == null) continue;
      setState(() => _messages = patched);
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
        useCache: true,
      );

      if (mounted && result.messages.isNotEmpty) {
        setState(() {
          final older = result.messages
              .where((m) => !BlockedUsersCache.isBlocked(m.userId))
              .toList();
          _messages.insertAll(0, older);
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
