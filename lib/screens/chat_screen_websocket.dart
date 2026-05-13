// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenWebSocketPart on _ChatScreenState {
  // ✅ Отметить конкретное сообщение как прочитанное
  // (функция была неиспользуемой; при необходимости можно вернуть и вызывать при отображении сообщения)

  void _setupWebSocketListener() {
    _webSocketSubscription?.cancel();
    _webSocketSubscription = WebSocketService.instance.stream.listen(
      (event) async {
        if (!mounted) return;
        try {
          final data = event is Map
              ? event as Map<String, dynamic>
              : (event is String
                    ? jsonDecode(event) as Map<String, dynamic>?
                    : null);
          if (data == null) return;
          if (kDebugMode) print('WebSocket received: $data');

          // Проверяем тип сообщения
          final messageType = data['type'];

          // ✅ Переподключение WebSocket — заново подписываемся на чат
          if (messageType == '_ws_reconnected') {
            if (mounted) {
              final now = DateTime.now();
              if (!ChatSyncPolicy.shouldRunReconnectSync(
                now: now,
                lastRunAt: _lastWsReconnectHandledAt,
              )) {
                return;
              }
              _lastWsReconnectHandledAt = now;
              _subscribedToChatRealtime = false;
              _subscribeToChatRealtime();
              final currentChatId = widget.chatId.toString();
              // После восстановления сокета подбираем отложенные E2EE-запросы.
              unawaited(E2eeService.processPendingKeyRequests(currentChatId));
              // Если ключ недоступен/в бэкоффе — мягко перезапускаем цикл запроса.
              if (_e2eeKeyState != _ChatScreenState._e2eeReady) {
                unawaited(_ensureE2eeKeyAndReloadIfMissing(currentChatId));
              }
              // Единая точка ретрая очереди исходящих temp-сообщений.
              unawaited(_retryQueuedMessages());
              // После восстановления сети добираем возможные пропуски в истории.
              unawaited(_pollForNewMessages());
            }
            return;
          }

          // ✅ E2EE: другой участник запросил ключ чата — отдаём ему ключ, если он у нас есть
          if (messageType == 'e2ee_request_key') {
            final chatId = data['chatId']?.toString();
            final requesterUserId = data['userId']?.toString();
            final keyVersion = data['keyVersion'] is int
                ? data['keyVersion'] as int
                : int.tryParse((data['keyVersion'] ?? '').toString());
            if (chatId != null) {
              if (requesterUserId != null && requesterUserId.isNotEmpty) {
                unawaited(
                  E2eeService.shareChatKeyWithUsers(chatId, [
                    requesterUserId,
                  ], keyVersion: keyVersion),
                );
              } else {
                unawaited(E2eeService.shareChatKeyWithNewMembers(chatId));
              }
            }
            return;
          }

          // ✅ E2EE rotation after member leave/remove: leader bootstraps a fresh key for new version.
          if (messageType == 'e2ee_key_rotated') {
            final chatId = data['chatId']?.toString();
            final keyVersion = data['keyVersion'] is int
                ? data['keyVersion'] as int
                : int.tryParse((data['keyVersion'] ?? '').toString());
            final leaderUserId = data['leaderUserId']?.toString();
            if (chatId == widget.chatId.toString() &&
                keyVersion != null &&
                keyVersion > 0) {
              unawaited(
                _handleE2eeKeyRotation(chatId!, keyVersion, leaderUserId),
              );
            }
            return;
          }

          // ✅ Новое сообщение (realtime) — type == 'message' просто не возвращаемся, идём к обработке chat_id ниже

          // ✅ Presence: начальное состояние
          if (messageType == 'presence_state') {
            final chatId = data['chat_id']?.toString();
            if (chatId == widget.chatId.toString() && mounted) {
              final list = (data['online_user_ids'] as List<dynamic>? ?? []);
              setState(() {
                _onlineUserIds
                  ..clear()
                  ..addAll(list.map((e) => e.toString()));
              });
            }
            return;
          }

          // ✅ Presence: online/offline события
          if (messageType == 'presence') {
            final chatId = data['chat_id']?.toString();
            if (chatId == widget.chatId.toString() && mounted) {
              final uid = data['user_id']?.toString();
              final status = data['status']?.toString();
              if (uid != null && uid.isNotEmpty) {
                setState(() {
                  if (status == 'online') {
                    _onlineUserIds.add(uid);
                  } else if (status == 'offline') {
                    _onlineUserIds.remove(uid);
                    _typingUntilByUserId.remove(uid);
                  }
                });
              }
            }
            return;
          }

          // ✅ Typing indicator
          if (messageType == 'typing') {
            final chatId = data['chat_id']?.toString();
            final uid = data['user_id']?.toString();
            final isTyping = data['is_typing'] == true;
            if (chatId == widget.chatId.toString() &&
                uid != null &&
                uid.isNotEmpty &&
                uid != widget.userId.toString() &&
                mounted) {
              setState(() {
                if (isTyping) {
                  _typingUntilByUserId[uid] = DateTime.now().add(
                    const Duration(seconds: 5),
                  );
                } else {
                  _typingUntilByUserId.remove(uid);
                }
              });
              _scheduleTypingCleanup();
            }
            return;
          }

          if (messageType == 'message_deleted') {
            // Обработка уведомления об удалении сообщения
            final deletedMessageId = data['message_id']?.toString();
            final chatId = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();

            if (chatId == currentChatId && deletedMessageId != null) {
              if (kDebugMode)
                print('Message deleted notification: $deletedMessageId');
              if (mounted) {
                setState(() {
                  _messages.removeWhere(
                    (m) => m.id.toString() == deletedMessageId,
                  );
                  _pinnedMessages.removeWhere(
                    (m) => m.id.toString() == deletedMessageId,
                  );
                  if (kDebugMode)
                    print(
                      'Message removed from list. Remaining messages: ${_messages.length}',
                    );
                });

                // ✅ Удаляем сообщение из кэша
                LocalMessagesService.removeMessage(
                  widget.chatId,
                  deletedMessageId,
                );
              }
            }
            return;
          }

          // ✅ Обработка события прочтения сообщения
          if (messageType == 'message_read') {
            final messageId = data['message_id']?.toString();
            if (messageId != null && mounted) {
              setState(() {
                final index = _messages.indexWhere(
                  (m) => m.id.toString() == messageId,
                );
                if (index != -1) {
                  // Обновляем статус сообщения
                  final msg = _messages[index];
                  final updatedMessage = Message(
                    id: msg.id,
                    chatId: msg.chatId,
                    userId: msg.userId,
                    content: msg.content,
                    imageUrl: msg.imageUrl,
                    originalImageUrl: msg.originalImageUrl,
                    fileUrl: msg.fileUrl,
                    fileName: msg.fileName,
                    fileSize: msg.fileSize,
                    fileMime: msg.fileMime,
                    messageType: msg.messageType,
                    senderEmail: msg.senderEmail,
                    senderAvatarUrl: msg.senderAvatarUrl,
                    createdAt: msg.createdAt,
                    deliveredAt: msg.deliveredAt,
                    editedAt: msg.editedAt,
                    isRead: true,
                    readAt:
                        data['read_at']?.toString() ??
                        DateTime.now().toIso8601String(),
                    keyVersion: msg.keyVersion,
                  );
                  _messages[index] = updatedMessage;

                  // ✅ Обновляем в кэше
                  LocalMessagesService.updateMessage(
                    widget.chatId,
                    updatedMessage,
                  );
                }
              });
            }
            return;
          }

          // ✅ Обработка события прочтения нескольких сообщений
          if (messageType == 'messages_read') {
            final chatId = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            if (chatId == currentChatId && mounted) {
              // Обновляем статусы всех сообщений текущего пользователя в этом чате
              setState(() {
                for (int i = 0; i < _messages.length; i++) {
                  final msg = _messages[i];
                  if (msg.userId == widget.userId) {
                    _messages[i] = Message(
                      id: msg.id,
                      chatId: msg.chatId,
                      userId: msg.userId,
                      content: msg.content,
                      imageUrl: msg.imageUrl,
                      originalImageUrl: msg.originalImageUrl,
                      fileUrl: msg.fileUrl,
                      fileName: msg.fileName,
                      fileSize: msg.fileSize,
                      fileMime: msg.fileMime,
                      messageType: msg.messageType,
                      senderEmail: msg.senderEmail,
                      senderAvatarUrl: msg.senderAvatarUrl,
                      createdAt: msg.createdAt,
                      deliveredAt: msg.deliveredAt,
                      editedAt: msg.editedAt,
                      isRead: true,
                      readAt:
                          data['read_at']?.toString() ??
                          DateTime.now().toIso8601String(),
                      keyVersion: msg.keyVersion,
                    );
                  }
                }
              });
            }
            return;
          }

          // ✅ Обработка события редактирования сообщения (E2EE: контент с сервера может быть зашифрован)
          if (messageType == 'message_edited') {
            final messageId = data['id']?.toString();
            final chatIdWs = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            if (chatIdWs == currentChatId && messageId != null && mounted) {
              final index = _messages.indexWhere(
                (m) => m.id.toString() == messageId,
              );
              if (index != -1) {
                final msg = _messages[index];
                final rawContent = (data['content'] ?? msg.content).toString();
                final updatedRaw = Message(
                  id: msg.id,
                  chatId: msg.chatId,
                  userId: msg.userId,
                  content: rawContent,
                  imageUrl: data['image_url'] ?? msg.imageUrl,
                  originalImageUrl: msg.originalImageUrl,
                  fileUrl: data['file_url'] ?? msg.fileUrl,
                  fileName: data['file_name'] ?? msg.fileName,
                  fileSize: data['file_size'] ?? msg.fileSize,
                  fileMime: data['file_mime'] as String? ?? msg.fileMime,
                  messageType: data['message_type'] ?? msg.messageType,
                  senderAvatarUrl:
                      data['sender_avatar_url'] ?? msg.senderAvatarUrl,
                  senderEmail: msg.senderEmail,
                  createdAt: msg.createdAt,
                  deliveredAt: msg.deliveredAt,
                  editedAt: data['edited_at']?.toString(),
                  isRead: msg.isRead,
                  readAt: msg.readAt,
                  replyToMessageId: msg.replyToMessageId,
                  replyToMessage: msg.replyToMessage,
                  isPinned: msg.isPinned,
                  reactions: msg.reactions,
                  isForwarded: msg.isForwarded,
                  originalChatName: msg.originalChatName,
                  keyVersion: msg.keyVersion,
                );
                LocalMessagesService.updateMessage(widget.chatId, updatedRaw);
                final displayMessage =
                    await MessagesService.decryptMessageForChat(
                      currentChatId,
                      updatedRaw,
                    );
                if (E2eeService.isEncrypted(updatedRaw.content) &&
                    displayMessage.content == '[зашифровано]') {
                  unawaited(
                    _ensureE2eeKeyAndReloadIfMissing(
                      currentChatId,
                      keyVersion: updatedRaw.keyVersion,
                    ),
                  );
                }
                if (mounted) {
                  setState(() {
                    _messages[index] = displayMessage;
                  });
                }
              }
            }
            return;
          }

          // ✅ Обработка событий реакций
          if (messageType == 'reaction_added' ||
              messageType == 'reaction_removed') {
            final messageId = data['message_id']?.toString();
            final reaction = data['reaction'] as String?;
            final userId = data['user_id']?.toString();

            if (messageId != null && mounted) {
              setState(() {
                final index = _messages.indexWhere(
                  (m) => m.id.toString() == messageId,
                );
                if (index != -1) {
                  final msg = _messages[index];
                  final currentReactions = List<MessageReaction>.from(
                    msg.reactions ?? [],
                  );

                  if (messageType == 'reaction_added' && reaction != null) {
                    // Добавляем реакцию, если её еще нет
                    if (!currentReactions.any(
                      (r) => r.reaction == reaction && r.userId == userId,
                    )) {
                      currentReactions.add(
                        MessageReaction(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          messageId: messageId,
                          userId: userId ?? '',
                          reaction: reaction,
                          createdAt: DateTime.now().toIso8601String(),
                          userEmail: data['user_email'] as String?,
                        ),
                      );
                    }
                  } else if (messageType == 'reaction_removed' &&
                      reaction != null) {
                    // Удаляем реакцию
                    currentReactions.removeWhere(
                      (r) => r.reaction == reaction && r.userId == userId,
                    );
                  }

                  // Обновляем сообщение с новыми реакциями
                  _messages[index] = Message(
                    id: msg.id,
                    chatId: msg.chatId,
                    userId: msg.userId,
                    content: msg.content,
                    imageUrl: msg.imageUrl,
                    originalImageUrl: msg.originalImageUrl,
                    fileUrl: msg.fileUrl,
                    fileName: msg.fileName,
                    fileSize: msg.fileSize,
                    fileMime: msg.fileMime,
                    messageType: msg.messageType,
                    senderEmail: msg.senderEmail,
                    senderAvatarUrl: msg.senderAvatarUrl,
                    createdAt: msg.createdAt,
                    deliveredAt: msg.deliveredAt,
                    editedAt: msg.editedAt,
                    isRead: msg.isRead,
                    readAt: msg.readAt,
                    replyToMessageId: msg.replyToMessageId,
                    replyToMessage: msg.replyToMessage,
                    isPinned: msg.isPinned,
                    reactions: currentReactions,
                    isForwarded: msg.isForwarded,
                    originalChatName: msg.originalChatName,
                    keyVersion: msg.keyVersion,
                  );

                  // Обновляем в кэше
                  LocalMessagesService.updateMessage(
                    widget.chatId,
                    _messages[index],
                  );
                }
              });
            }
            return;
          }

          // Проверяем, что это сообщение для текущего чата
          // Преобразуем chat_id в строку для сравнения
          final chatId =
              data['chat_id']?.toString() ?? data['chatId']?.toString();
          final currentChatId = widget.chatId.toString();

          if (kDebugMode)
            print(
              'WebSocket chat_id: $chatId, current chat_id: $currentChatId',
            );

          if (chatId == currentChatId) {
            if (kDebugMode) print('Message is for current chat');
            try {
              final rawMessage = Message.fromJson(data);
              LocalMessagesService.updateMessage(widget.chatId, rawMessage);
              final message = await MessagesService.decryptMessageForChat(
                widget.chatId.toString(),
                rawMessage,
              );
              if (E2eeService.isEncrypted(rawMessage.content) &&
                  message.content == '[зашифровано]') {
                unawaited(
                  _ensureE2eeKeyAndReloadIfMissing(
                    currentChatId,
                    keyVersion: rawMessage.keyVersion,
                  ),
                );
              }
              if (kDebugMode)
                print('Parsed message: ${message.id} - ${message.content}');
              if (mounted) {
                final shouldKeepAtBottom = _isNearBottom();
                var didAppendMessage = false;
                setState(() {
                  // ✅ Проверяем, есть ли временное сообщение от текущего пользователя
                  // (чтобы заменить его на реальное сообщение от сервера)
                  final tempIndex = _messages.indexWhere(
                    (m) =>
                        m.id.startsWith('temp_') &&
                        m.userId == widget.userId.toString() &&
                        // Проверяем содержимое (текст или изображение)
                        ((m.content == message.content &&
                                m.content.isNotEmpty) ||
                            _sameOutgoingImageUrl(
                              m.imageUrl,
                              message.imageUrl,
                            ) ||
                            (m.content.isEmpty &&
                                m.imageUrl == null &&
                                message.content.isEmpty &&
                                message.imageUrl == null)),
                  );

                  if (tempIndex != -1) {
                    // ✅ Заменяем временное сообщение на реальное (но не перезаписываем контент пустым — на части устройств WS приходит с пустым content)
                    if (kDebugMode)
                      print(
                        '✅ WebSocket: Replacing temp message at index $tempIndex with real message ${message.id}',
                      );
                    if (kDebugMode)
                      print(
                        '   Temp: ${_messages[tempIndex].id}, Real: ${message.id}',
                      );
                    final existing = _messages[tempIndex];
                    final merged = _mergeMessageKeepContent(existing, message);

                    // ✅ Создаем новый список для принудительного обновления UI
                    final newMessages = List<Message>.from(_messages);
                    final tempId = newMessages[tempIndex]
                        .id; // Сохраняем ID временного сообщения
                    newMessages[tempIndex] = merged;
                    _messages = newMessages;
                    _tempMessageStates.remove(tempId);
                    _pendingUploadDrafts.remove(tempId);
                    unawaited(
                      LocalMessagesService.removePendingUploadDraft(
                        widget.chatId,
                        tempId,
                      ),
                    );
                    if (kDebugMode)
                      print(
                        '✅ WebSocket: Message updated in UI. Total: ${_messages.length}',
                      );
                  } else {
                    // Проверяем, нет ли уже такого сообщения (избегаем дубликатов)
                    final exists = _messages.any((m) => m.id == message.id);
                    if (!exists) {
                      // ✅ Если это сообщение от текущего пользователя и недавно отправлено,
                      // возможно временное сообщение уже было удалено или не найдено
                      // В этом случае просто добавляем реальное сообщение
                      // НО: если это сообщение от текущего пользователя, возможно оно уже обновлено из ответа сервера
                      // Проверяем, нет ли временного сообщения с таким же содержимым
                      final hasMatchingTemp = _messages.any(
                        (m) =>
                            m.id.startsWith('temp_') &&
                            m.userId == widget.userId.toString() &&
                            ((m.content == message.content &&
                                    m.content.isNotEmpty) ||
                                _sameOutgoingImageUrl(
                                  m.imageUrl,
                                  message.imageUrl,
                                )),
                      );

                      if (hasMatchingTemp) {
                        // ✅ Есть временное сообщение - не добавляем дубликат, оно будет заменено выше
                        if (kDebugMode)
                          print(
                            '⚠️ WebSocket: Found matching temp message, skipping duplicate add',
                          );
                      } else {
                        // ⚠️ Защита: на части устройств/сетей может прийти WS-эвент с пустым content для СВОЕГО сообщения.
                        // В этом случае не добавляем "пустышку" — своё сообщение корректно придёт из HTTP-ответа и/или будет заменено.
                        final isSelf =
                            message.userId == widget.userId.toString();
                        final isEmptyTextOnly =
                            message.content.trim().isEmpty &&
                            (message.imageUrl == null ||
                                message.imageUrl!.isEmpty) &&
                            (message.fileUrl == null ||
                                message.fileUrl!.isEmpty);
                        if (isSelf && isEmptyTextOnly) {
                          final pendingIdx =
                              _singleRecentSendingImageTempIndex();
                          if (pendingIdx != null) {
                            if (kDebugMode) {
                              print(
                                '⚠️ WebSocket: empty self payload (id=${message.id}); merging into temp ${_messages[pendingIdx].id}',
                              );
                            }
                            final tempId = _messages[pendingIdx].id;
                            final existing = _messages[pendingIdx];
                            final merged = _mergeMessageKeepContent(
                              existing,
                              message,
                            );
                            final newMessages = List<Message>.from(_messages);
                            newMessages[pendingIdx] = merged;
                            final realId = merged.id;
                            for (int j = newMessages.length - 1; j >= 0; j--) {
                              if (j == pendingIdx) continue;
                              if (newMessages[j].id == realId) {
                                newMessages.removeAt(j);
                              }
                            }
                            _messages = newMessages;
                            _tempMessageStates.remove(tempId);
                            _pendingUploadDrafts.remove(tempId);
                            unawaited(
                              LocalMessagesService.removePendingUploadDraft(
                                widget.chatId,
                                tempId,
                              ),
                            );
                            return;
                          }
                          if (kDebugMode)
                            print(
                              '⚠️ WebSocket: Skip empty self message (id=${message.id})',
                            );
                          return;
                        }

                        // ✅ Добавляем сообщение только если нет временного
                        final newMessages = List<Message>.from(_messages);
                        newMessages.add(
                          message,
                        ); // В конец: список "старые сверху, новые снизу"
                        _messages = newMessages;
                        didAppendMessage = true;
                        if (kDebugMode) {
                          if (kDebugMode)
                            print(
                              '✅ WebSocket: Message added to list. Total: ${_messages.length}',
                            );
                        }
                        // Звук/вибрация при новом сообщении от другого пользователя
                        if (message.userId != widget.userId.toString()) {
                          NotificationFeedbackService.onNewMessage();
                        }
                      }
                    } else {
                      // ✅ Если сообщение уже есть, обновляем (не затираем непустой контент пустым из WS)
                      final existingIndex = _messages.indexWhere(
                        (m) => m.id == message.id,
                      );
                      if (existingIndex != -1) {
                        final existing = _messages[existingIndex];
                        final merged = _mergeMessageKeepContent(
                          existing,
                          message,
                        );
                        final newMessages = List<Message>.from(_messages);
                        newMessages[existingIndex] = merged;
                        _messages = newMessages;
                        if (kDebugMode)
                          print(
                            '✅ WebSocket: Message updated at index $existingIndex. Total: ${_messages.length}',
                          );
                      } else {
                        if (kDebugMode)
                          print(
                            '⚠️ WebSocket: Message exists check failed, but index not found',
                          );
                      }
                    }
                  }
                });
                if (didAppendMessage && shouldKeepAtBottom) {
                  _scrollToBottom();
                }
              }
            } catch (parseError) {
              if (kDebugMode)
                print('Error parsing Message from WebSocket data: $parseError');
              if (kDebugMode) print('Data: $data');
            }
          } else {
            if (kDebugMode)
              print(
                'Message is for different chat: $chatId (current: $currentChatId)',
              );
          }
        } catch (e) {
          if (kDebugMode) print('Error processing WebSocket message: $e');
          if (kDebugMode) print('Raw event: $event');
        }
      },
      onError: (error) {
        if (kDebugMode) print('WebSocket error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Ошибка WebSocket: $error'),
            ),
          );
        }
      },
      onDone: () {
        if (kDebugMode) print('WebSocket connection closed');
      },
    );

    // ✅ Подписываемся на realtime события этого чата
    _subscribeToChatRealtime();

    // Добавляем listener для автоматической подгрузки при скролле вверх
    _scrollController.addListener(_onScroll);
  }

  bool _sendWsJson(Map<String, dynamic> payload) {
    try {
      return WebSocketService.instance.send(payload);
    } catch (e) {
      if (kDebugMode) print('Ошибка отправки WS payload: $e');
      return false;
    }
  }

  void _subscribeToChatRealtime() {
    if (_subscribedToChatRealtime) return;
    final sent = _sendWsJson({'type': 'subscribe', 'chat_id': widget.chatId});
    if (sent) {
      _subscribedToChatRealtime = true;
    }
  }

  Future<void> _initWebSocket() async {
    try {
      await WebSocketService.instance.connectIfNeeded();
      unawaited(
        E2eeService.processPendingKeyRequests(widget.chatId.toString()),
      );
      if (mounted) {
        _setupWebSocketListener();
      }
    } catch (e) {
      // Не логируем чувствительные данные
    }
  }
}
