// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenMessagesSyncPart on _ChatScreenState {
  /// E2EE: после requestChatKey ждём появления ключа на сервере и перерисовываем сообщения (расшифровка чужих).
  Future<void> _retryChatKeyThenReloadMessages(
    String chatIdStr, {
    int? keyVersion,
  }) async {
    if (_isWaitingForE2eeKey) return;
    _isWaitingForE2eeKey = true;
    if (mounted) {
      setState(() => _e2eeKeyState = _ChatScreenState._e2eeRequesting);
    }
    _showE2eeWaitingSnack();
    final obtained = await E2eeService.waitForChatKeyFromServer(
      chatIdStr,
      keyVersion: keyVersion,
    );
    _isWaitingForE2eeKey = false;
    if (obtained && mounted) {
      setState(() => _e2eeKeyState = _ChatScreenState._e2eeReady);
      _hideE2eeWaitingSnack();
      _showE2eeReadySnack();
      await _loadMessages();
      unawaited(_retryQueuedMessages());
    } else if (mounted) {
      setState(() => _e2eeKeyState = _ChatScreenState._e2eeRetryBackoff);
      _hideE2eeWaitingSnack();
    }
  }

  Future<void> _ensureE2eeKeyAndReloadIfMissing(
    String chatIdStr, {
    int? keyVersion,
  }) async {
    if (_isWaitingForE2eeKey) return;
    if (mounted) {
      setState(() => _e2eeKeyState = _ChatScreenState._e2eeRequesting);
    }
    await E2eeService.requestChatKey(chatIdStr, keyVersion: keyVersion);
    unawaited(
      _retryChatKeyThenReloadMessages(chatIdStr, keyVersion: keyVersion),
    );
  }

  Future<void> _handleE2eeKeyRotation(
    String chatIdStr,
    int keyVersion,
    String? leaderUserId,
  ) async {
    if (!mounted) return;
    setState(() => _e2eeKeyState = _ChatScreenState._e2eeMissing);

    final myId = widget.userId.toString();
    final isLeader = leaderUserId != null && leaderUserId == myId;
    if (isLeader) {
      try {
        await E2eeService.ensureKeyPair();
        final members = await _chatsService.getChatMembers(chatIdStr);
        final memberIds = members
            .map((m) => m['id']?.toString() ?? '')
            .where((x) => x.isNotEmpty)
            .toList();
        final pubKeys = await E2eeService.fetchPublicKeys(memberIds);
        final keysMembers = memberIds
            .map(
              (id) => <String, dynamic>{
                'id': id,
                'publicKey': pubKeys[id] ?? '',
              },
            )
            .toList();
        await E2eeService.createChatKey(
          chatIdStr,
          keysMembers,
          keyVersion: keyVersion,
        );
        if (mounted) {
          setState(() => _e2eeKeyState = _ChatScreenState._e2eeReady);
          _showE2eeReadySnack();
        }
        await _loadMessages();
        return;
      } catch (_) {
        // Fall through to request/retry path.
      }
    }

    await _ensureE2eeKeyAndReloadIfMissing(chatIdStr, keyVersion: keyVersion);
  }

  String? _e2eeStatusText() {
    switch (_e2eeKeyState) {
      case _ChatScreenState._e2eeReady:
        return null;
      case _ChatScreenState._e2eeMissing:
        return 'Ключ шифрования отсутствует. Запрашиваем...';
      case _ChatScreenState._e2eeRequesting:
        return 'Ожидаем ключ шифрования от собеседника...';
      case _ChatScreenState._e2eeRetryBackoff:
        return 'Ключ не получен, повторим запрос автоматически.';
      case _ChatScreenState._e2eeFailed:
        return 'Не удалось получить ключ шифрования.';
      default:
        return 'Ключ шифрования отсутствует. Запрашиваем...';
    }
  }

  void _showE2eeWaitingSnack() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 20),
        content: Text('Ожидаем ключ шифрования от собеседника...'),
      ),
    );
  }

  void _hideE2eeWaitingSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _showE2eeReadySnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Ключ шифрования получен. Сообщения обновлены.'),
      ),
    );
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    final stickToBottom = _stickToBottom;

    setState(() {
      _isLoading = true;
      _hasMoreMessages = true;
      _oldestMessageId = null;
    });

    // Для аккаунтов, которые вошли по сохранённому токену (без ввода пароля),
    // гарантируем локальную E2EE-пару и публикацию public key перед обменом ключами чата.
    try {
      await E2eeService.ensureKeyPair();
    } catch (_) {}

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

        // E2EE: считаем требуемую (самую новую в истории) версию ключа.
        final newestMessageKeyVersion = result.messages.fold<int>(
          1,
          (best, m) => m.keyVersion > best ? m.keyVersion : best,
        );
        final knownCurrentVersion = await E2eeService.getCurrentKeyVersion(
          widget.chatId.toString(),
        );
        final requiredKeyVersion =
            knownCurrentVersion != null &&
                knownCurrentVersion > newestMessageKeyVersion
            ? knownCurrentVersion
            : newestMessageKeyVersion;
        await E2eeService.markCurrentKeyVersion(
          widget.chatId.toString(),
          requiredKeyVersion,
        );

        // E2EE: если у нас есть ключ требуемой версии — отдать участникам без ключа; иначе запросить именно эту версию.
        final chatIdStr = widget.chatId.toString();
        final hasKey =
            await E2eeService.getChatKey(
              chatIdStr,
              keyVersion: requiredKeyVersion,
            ) !=
            null;
        if (hasKey) {
          if (mounted) {
            setState(() => _e2eeKeyState = _ChatScreenState._e2eeReady);
          }
          await E2eeService.shareChatKeyWithNewMembers(chatIdStr);
          await E2eeService.processPendingKeyRequests(chatIdStr);
        } else {
          if (mounted) {
            setState(() => _e2eeKeyState = _ChatScreenState._e2eeMissing);
          }
          await E2eeService.requestChatKey(
            chatIdStr,
            keyVersion: requiredKeyVersion,
          );
          unawaited(
            _retryChatKeyThenReloadMessages(
              chatIdStr,
              keyVersion: requiredKeyVersion,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error loading messages: $e');
      if (mounted) setState(() => _e2eeKeyState = _ChatScreenState._e2eeFailed);
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
        if (ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
          stickToBottom: stickToBottom,
          initialOpenComplete: _initialOpenComplete,
          messageCount: _messages.length,
        )) {
          _completeInitialOpenScroll();
        } else if (ChatScrollPolicy.shouldMarkInitialOpenCompleteImmediately(
          messageCount: _messages.length,
        )) {
          _markInitialOpenComplete();
        } else if (ChatScrollPolicy.shouldAutoScrollAfterReload(
          stickToBottom: _stickToBottom,
        )) {
          // Reload (E2EE/pull-to-refresh) пока пользователь у низа — возвращаем
          // к низу; при чтении истории остаёмся на месте.
          _scrollToBottom();
        }
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!mounted || _isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      // Сохраняем текущую позицию скролла и максимальную высоту контента
      final currentScrollPosition = _scrollController.position.pixels;
      final maxScrollExtentBefore = _scrollController.position.maxScrollExtent;

      // Загружаем старые сообщения
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: _ChatScreenState._messagesPerPage,
        beforeMessageId: _oldestMessageId,
        useCache: false,
      );

      if (mounted && result.messages.isNotEmpty) {
        setState(() {
          // Добавляем новые сообщения в начало списка
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

        // Восстанавливаем позицию скролла после добавления сообщений
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && mounted) {
            // Вычисляем разницу в высоте контента
            final maxScrollExtentAfter =
                _scrollController.position.maxScrollExtent;
            // Новая позиция = старая позиция + разница в высоте
            // Это сохраняет видимую позицию пользователя
            final newScrollPosition =
                ChatScrollPolicy.preserveViewportAfterPrepend(
                  currentScrollPosition: currentScrollPosition,
                  maxScrollExtentBefore: maxScrollExtentBefore,
                  maxScrollExtentAfter: maxScrollExtentAfter,
                );

            // Прокручиваем к новой позиции
            _scrollController.jumpTo(
              newScrollPosition.clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              ),
            );
          }
        });
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

  // ✅ Виджет для отображения статуса сообщения
}
