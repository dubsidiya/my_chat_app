// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenSendPart on _ChatScreenState {
  Widget _buildMessageStatus(Message msg) {
    if (msg.id.startsWith('temp_')) {
      final state = _tempMessageStates[msg.id] ?? _OutgoingUiState.sending;
      switch (state) {
        case _OutgoingUiState.queued:
          return Icon(
            Icons.schedule_rounded,
            size: 14,
            color: Colors.orange.shade300,
          );
        case _OutgoingUiState.sending:
          return Icon(
            Icons.schedule_send_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.7),
          );
        case _OutgoingUiState.error:
          return Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: Colors.red.shade300,
          );
      }
    }

    final status = msg.status;
    IconData icon;
    Color color;

    switch (status) {
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.white.withValues(alpha: 0.6);
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white.withValues(alpha: 0.6);
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = AppColors.accent; // прочитано — в стиле темы
        break;
    }

    return Icon(icon, size: 14, color: color);
  }

  Future<void> _sendMessage() async {
    if (kDebugMode) print('🔍 _sendMessage called');
    if (!mounted) {
      if (kDebugMode) print('⚠️ Widget not mounted, returning');
      return;
    }

    final text = _controller.text.trim();
    final hasImage = _selectedImagePath != null || _selectedImageBytes != null;
    final hasFile = _selectedFilePath != null || _selectedFileBytes != null;
    // Сохраняем до любых сбросов/ошибок для возможности поставить в очередь.
    final replyToMessageId = _replyToMessage?.id;
    final replyToMessage = _replyToMessage;

    if (kDebugMode) {
      print('🔍 Text: "$text", hasImage: $hasImage, hasFile: $hasFile');
    }

    if (text.isEmpty && !hasImage && !hasFile) {
      if (kDebugMode) print('⚠️ Text is empty and no attachments, returning');
      return;
    }

    if (_e2eeKeyState != _ChatScreenState._e2eeReady) {
      unawaited(_ensureE2eeKeyAndReloadIfMissing(widget.chatId.toString()));
    }

    if (_isSendingMessage) return;
    _isSendingMessage = true;

    try {
      if (kDebugMode) print('✅ Proceeding with message send');

      // ✅ Останавливаем typing-индикатор перед отправкой
      if (_sentTyping) {
        _typingStopTimer?.cancel();
        _sendTyping(false);
      }

      String? imageUrl;
      String? imageStorageKey;
      String? originalImageUrl;
      String? originalImageStorageKey;
      String? fileUrl;
      String? fileStorageKey;
      String? fileName;
      int? fileSize;
      String? fileMime;

      // Загружаем изображение, если выбрано
      if (hasImage) {
        setState(() => _isUploadingImage = true);
        try {
          Uint8List bytes;
          String fileName;

          Uint8List? originalBytes;

          if (kIsWeb) {
            // На веб используем bytes напрямую
            if (_selectedImageBytes != null) {
              originalBytes = _selectedImageBytes!;
              // ✅ Сжимаем изображение перед загрузкой (для отображения)
              bytes = await _compressImage(_selectedImageBytes!);
              fileName = _selectedImageName ?? 'image.jpg';
              // Очищаем оригинальные байты из памяти после загрузки
            } else {
              throw Exception('Изображение не выбрано');
            }
          } else {
            // На мобильных/десктоп читаем из файла
            if (_selectedImagePath != null) {
              final file = File(_selectedImagePath!);
              originalBytes = await file.readAsBytes();
              // ✅ Сжимаем изображение перед загрузкой (для отображения)
              bytes = await _compressImage(originalBytes);
              fileName = _selectedImagePath!.split('/').last;
            } else {
              throw Exception('Изображение не выбрано');
            }
          }

          // ✅ Загружаем и оригинал, и сжатое изображение
          final uploaded = await _messagesService.uploadImageWithUrls(
            bytes,
            fileName,
            originalBytes: originalBytes,
            chatId: widget.chatId.toString(),
          );
          imageUrl = uploaded.imageUrl;
          imageStorageKey = uploaded.imageStorageKey;
          originalImageUrl = uploaded.originalImageUrl;
          originalImageStorageKey = uploaded.originalImageStorageKey;

          // ✅ Очищаем память после успешной загрузки
          if (mounted) {
            setState(() {
              _selectedImagePath = null;
              _selectedImageBytes = null;
              _selectedImageName = null;
            });
          }
        } catch (e) {
          if (_isQueueableSendError(e)) {
            _enqueuePendingUploadDraft(
              _PendingUploadDraft(
                text: text,
                idempotencyKey: _generateIdempotencyKey(),
                replyToMessageId: replyToMessageId,
                replyToMessage: replyToMessage,
                imageBytes: _selectedImageBytes,
                imagePath: _selectedImagePath,
                imageName: _selectedImageName,
              ),
            );
            return;
          }
          if (mounted) {
            setState(() => _isUploadingImage = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 3),
                content: Text('Ошибка загрузки изображения: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        setState(() => _isUploadingImage = false);
      }

      // Загружаем файл, если выбран
      if (hasFile) {
        // Сервер сейчас не поддерживает "image+file" в одном сообщении.
        // Смотрим на уже загруженный imageUrl, а не на hasImage из начала метода (после upload путь к фото уже очищен).
        if (imageUrl != null && imageUrl.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                duration: Duration(seconds: 3),
                content: Text(
                  'Нельзя отправить изображение и файл в одном сообщении',
                ),
              ),
            );
          }
          return;
        }

        setState(() => _isUploadingFile = true);
        try {
          List<int> bytes;
          String name;

          // ✅ Поддержка bytes и на мобилках (нужно для voice-recording)
          if (_selectedFileBytes != null) {
            bytes = _selectedFileBytes!;
            name = _selectedFileName ?? 'file';
          } else if (_selectedFilePath != null) {
            final f = File(_selectedFilePath!);
            bytes = await f.readAsBytes();
            name = _selectedFileName ?? _selectedFilePath!.split('/').last;
          } else {
            throw Exception('Файл не выбран');
          }

          final meta = await _messagesService.uploadFile(bytes, name);
          fileUrl = meta['file_url']?.toString();
          fileStorageKey = meta['file_storage_key']?.toString();
          fileName = (meta['file_name'] ?? name).toString();
          fileSize =
              int.tryParse((meta['file_size'] ?? '').toString()) ??
              _selectedFileSize ??
              bytes.length;
          fileMime = (meta['file_mime'] ?? '').toString();

          if (fileUrl == null || fileUrl.isEmpty) {
            throw Exception('Сервер не вернул file_url');
          }

          if (mounted) {
            setState(() {
              _selectedFilePath = null;
              _selectedFileBytes = null;
              _selectedFileName = null;
              _selectedFileSize = null;
            });
          }
        } catch (e) {
          if (_isQueueableSendError(e)) {
            _enqueuePendingUploadDraft(
              _PendingUploadDraft(
                text: text,
                idempotencyKey: _generateIdempotencyKey(),
                replyToMessageId: replyToMessageId,
                replyToMessage: replyToMessage,
                fileBytes: _selectedFileBytes,
                filePath: _selectedFilePath,
                fileName: _selectedFileName,
                fileSize: _selectedFileSize,
                fileMime:
                    _selectedFileName?.toLowerCase().endsWith('.m4a') == true
                    ? 'audio/mp4'
                    : null,
              ),
            );
            return;
          }
          if (mounted) {
            setState(() => _isUploadingFile = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 3),
                content: Text(
                  'Ошибка загрузки файла: ${e.toString().replaceFirst('Exception: ', '')}',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        setState(() => _isUploadingFile = false);
      }

      // ✅ Создаем временное сообщение для оптимистичного обновления UI
      final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final idempotencyKey = _generateIdempotencyKey();
      final tempMessage = Message(
        id: tempMessageId,
        chatId: widget.chatId,
        userId: widget.userId,
        content: text,
        imageUrl: imageUrl,
        originalImageUrl: imageUrl, // Временно используем тот же URL
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        fileMime: fileMime,
        messageType: fileUrl != null
            ? (looksLikeAudio(mime: fileMime, fileName: fileName)
                  ? (text.isNotEmpty ? 'text_voice' : 'voice')
                  : (text.isNotEmpty ? 'text_file' : 'file'))
            : (imageUrl != null
                  ? (text.isNotEmpty ? 'text_image' : 'image')
                  : 'text'),
        senderEmail: widget.userEmail,
        senderAvatarUrl: widget.myAvatarUrl,
        createdAt: DateTime.now().toIso8601String(),
        isRead: false,
        replyToMessageId: replyToMessageId,
        replyToMessage: replyToMessage,
        keyVersion: 1,
      );

      // Собственное новое сообщение всегда показываем внизу. На web пересчёт layout
      // может занимать несколько кадров, поэтому ниже используем retry-скролл.
      if (mounted) {
        if (kDebugMode) {
          print(
            '🔍 Adding temp message to UI: id=$tempMessageId, content=$text',
          );
        }
        if (kDebugMode) {
          print('🔍 Current messages count before: ${_messages.length}');
        }
        setState(() {
          // ✅ Создаем новый список для гарантированного обновления UI
          final newMessages = List<Message>.from(_messages);
          newMessages.add(
            tempMessage,
          ); // Добавляем в конец, чтобы новые были снизу
          _messages = newMessages;
          _tempMessageStates[tempMessageId] = _OutgoingUiState.sending;
          _tempMessageIdempotencyKeys[tempMessageId] = idempotencyKey;
          // Очищаем поле ответа
          _replyToMessage = null;
        });
        if (kDebugMode) {
          print('✅ Temp message added to UI. New count: ${_messages.length}');
        }
        if (kDebugMode) {
          print(
            '✅ First message ID: ${_messages.isNotEmpty ? _messages[0].id : "none"}',
          );
        }
        _scrollToBottom();

        // ✅ НЕ сохраняем временное сообщение в кэш сразу
        // Оно будет сохранено только после получения реального ответа от сервера
        // Это предотвращает перезагрузку списка сообщений
      }

      try {
        // ✅ Отправляем сообщение и получаем ответ от сервера
        if (kDebugMode) {
          // ignore: avoid_print
          if (kDebugMode) {
            print(
              'sendMessage: chatId=${widget.chatId}, replyTo=$replyToMessageId',
            );
          }
        }
        final sentMessage = await _messagesService.sendMessage(
          widget.chatId,
          text,
          idempotencyKey: idempotencyKey,
          imageUrl: imageUrl,
          imageStorageKey: imageStorageKey,
          originalImageUrl: originalImageUrl,
          originalImageStorageKey: originalImageStorageKey,
          replyToMessageId: replyToMessageId,
          fileUrl: fileUrl,
          fileStorageKey: fileStorageKey,
          fileName: fileName,
          fileSize: fileSize,
          fileMime: fileMime,
        );
        if (kDebugMode) {
          print(
            '🔍 sendMessage service returned: ${sentMessage != null ? "message with id=${sentMessage.id}" : "null"}',
          );
        }

        if (mounted) {
          _controller.clear();
          // ✅ Память уже очищена выше после загрузки изображения
          // Дополнительная очистка на случай, если изображения не было
          if (_selectedImagePath != null || _selectedImageBytes != null) {
            setState(() {
              _selectedImagePath = null;
              _selectedImageBytes = null;
              _selectedImageName = null;
            });
          }
          if (_selectedFilePath != null || _selectedFileBytes != null) {
            setState(() {
              _selectedFilePath = null;
              _selectedFileBytes = null;
              _selectedFileName = null;
              _selectedFileSize = null;
            });
          }

          // ✅ Если получили сообщение от сервера, обновляем временное сообщение
          if (sentMessage != null) {
            if (kDebugMode) {
              print(
                '✅ Received message from server: id=${sentMessage.id}, content=${sentMessage.content}',
              );
            }
            if (kDebugMode) {
              print('🔍 Looking for temp message with id: $tempMessageId');
            }
            if (kDebugMode) {
              print('🔍 Current messages count: ${_messages.length}');
            }
            if (kDebugMode) {
              print(
                '🔍 Current message IDs: ${_messages.map((m) => m.id).toList()}',
              );
            }

            // ✅ Обновляем сразу, без WidgetsBinding, чтобы не потерять сообщение
            final tempIndex = _messages.indexWhere(
              (m) => m.id == tempMessageId,
            );
            if (kDebugMode) {
              print('🔍 Looking for temp message with id: $tempMessageId');
            }
            if (kDebugMode) {
              print('🔍 Current messages count: ${_messages.length}');
            }
            if (kDebugMode) {
              print(
                '🔍 Current message IDs: ${_messages.map((m) => m.id).toList()}',
              );
            }
            if (kDebugMode) print('🔍 Temp message found at index: $tempIndex');

            if (tempIndex != -1) {
              if (kDebugMode) {
                print(
                  '✅ Replacing temp message at index $tempIndex with real message ${sentMessage.id}',
                );
              }
              setState(() {
                // ✅ Создаем новый список для принудительного обновления UI
                final newMessages = List<Message>.from(_messages);
                newMessages[tempIndex] = sentMessage;

                // ✅ Если WebSocket успел добавить это же сообщение раньше, убираем дубликаты по id.
                // Оставляем только ту запись, которую мы сейчас поставили на место tempIndex.
                final realId = sentMessage.id;
                for (int i = newMessages.length - 1; i >= 0; i--) {
                  if (i == tempIndex) continue;
                  if (newMessages[i].id == realId) {
                    newMessages.removeAt(i);
                  }
                }
                _messages = newMessages;
                _tempMessageStates.remove(tempMessageId);
                _tempMessageIdempotencyKeys.remove(tempMessageId);
                _pendingUploadDrafts.remove(tempMessageId);
                unawaited(
                  LocalMessagesService.removePendingUploadDraft(
                    widget.chatId,
                    tempMessageId,
                  ),
                );
              });
              if (kDebugMode) {
                print(
                  '✅ Message updated in UI (new list created). Total messages: ${_messages.length}',
                );
              }
              if (kDebugMode) {
                print(
                  '✅ Message IDs after update: ${_messages.map((m) => m.id).toList()}',
                );
              }
            } else {
              // Если временное сообщение не найдено, проверяем, нет ли уже такого сообщения
              final existingIndex = _messages.indexWhere(
                (m) => m.id == sentMessage.id,
              );
              if (existingIndex != -1) {
                if (kDebugMode) {
                  print('⚠️ Message already exists at index $existingIndex');
                }
                // Обновляем сообщение на текущей позиции, без перемещения
                setState(() {
                  final newMessages = List<Message>.from(_messages);
                  newMessages[existingIndex] = sentMessage;

                  // ✅ Убираем возможные дубликаты по id (оставляем updated на existingIndex)
                  final realId = sentMessage.id;
                  for (int i = newMessages.length - 1; i >= 0; i--) {
                    if (i == existingIndex) continue;
                    if (newMessages[i].id == realId) {
                      newMessages.removeAt(i);
                    }
                  }
                  newMessages.removeWhere((m) => m.id == tempMessageId);

                  _messages = newMessages;
                  _tempMessageStates.remove(tempMessageId);
                  _tempMessageIdempotencyKeys.remove(tempMessageId);
                  _pendingUploadDrafts.remove(tempMessageId);
                  unawaited(
                    LocalMessagesService.removePendingUploadDraft(
                      widget.chatId,
                      tempMessageId,
                    ),
                  );
                });
                if (kDebugMode) {
                  print('✅ Message updated in place at index $existingIndex');
                }
              } else {
                if (kDebugMode) {
                  print(
                    '⚠️ Temp message not found and message not in list, adding it',
                  );
                }
                setState(() {
                  // ✅ Создаем новый список для принудительного обновления UI
                  final newMessages = List<Message>.from(_messages);
                  newMessages.add(
                    sentMessage,
                  ); // добавляем в конец, новые снизу

                  // ✅ Убираем возможные дубликаты по id (если WS уже добавил)
                  final realId = sentMessage.id;
                  for (int i = newMessages.length - 2; i >= 0; i--) {
                    if (newMessages[i].id == realId) {
                      newMessages.removeAt(i);
                    }
                  }
                  newMessages.removeWhere((m) => m.id == tempMessageId);

                  _messages = newMessages;
                  _tempMessageStates.remove(tempMessageId);
                  _tempMessageIdempotencyKeys.remove(tempMessageId);
                  _pendingUploadDrafts.remove(tempMessageId);
                  unawaited(
                    LocalMessagesService.removePendingUploadDraft(
                      widget.chatId,
                      tempMessageId,
                    ),
                  );
                });
                if (kDebugMode) {
                  print(
                    '✅ Message added to end. Total: ${_messages.length} (new list created)',
                  );
                }
              }
            }

            _scrollToBottom();

            // Принудительные обновления UI больше не нужны — список обновляется напрямую

            // Кэш обновляется в MessagesService на raw-ответе сервера, чтобы не сохранять plaintext E2EE.
          } else {
            if (kDebugMode) {
              print('⚠️ No message received from server response');
            }
          }

          // ✅ Fallback: Если через 3 секунды временное сообщение все еще есть,
          // значит WebSocket не получил сообщение - оставляем как есть
          // (сообщение уже обновлено из ответа сервера выше)
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && _messages.any((m) => m.id == tempMessageId)) {
              if (kDebugMode) {
                print(
                  '⚠️ Temp message still exists after 3s, but should be replaced by WebSocket or server response',
                );
              }
            }
          });
        }

        // ✅ Сообщение уже обновлено из ответа сервера
        // Также будет обновлено через WebSocket (если придет) для синхронизации с другими клиентами
      } catch (e, stackTrace) {
        if (kDebugMode) print('❌ Error sending message: $e');
        if (kDebugMode) print('❌ Stack trace: $stackTrace');
        final errorText = e.toString();
        final isE2eeKeyError = errorText.contains(
          'E2EE ключ для чата пока недоступен',
        );
        final isQueueableNetworkError = _isQueueableSendError(e);
        if (isE2eeKeyError) {
          unawaited(_ensureE2eeKeyAndReloadIfMissing(widget.chatId.toString()));
        }

        if (mounted) {
          setState(() {
            _tempMessageStates[tempMessageId] =
                (isE2eeKeyError || isQueueableNetworkError)
                ? _OutgoingUiState.queued
                : _OutgoingUiState.error;
          });

          // Восстанавливаем поле ответа, если была ошибка
          if (_replyToMessage == null && tempMessage.replyToMessage != null) {
            setState(() {
              _replyToMessage = tempMessage.replyToMessage;
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text(
                isQueueableNetworkError
                    ? 'Нет сети: сообщение оставлено в очереди и будет отправлено при подключении.'
                    : isE2eeKeyError
                    ? 'Ожидаем ключ шифрования. Попробуйте отправить снова через пару секунд.'
                    : 'Ошибка отправки сообщения: ${networkErrorMessage(e)}',
              ),
            ),
          );
        }
      }
    } finally {
      _isSendingMessage = false;
      if (mounted) setState(() {});
    }
  }
}
