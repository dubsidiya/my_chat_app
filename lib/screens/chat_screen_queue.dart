// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenQueuePart on _ChatScreenState {
  /// Только реальные сбои транспорта / TLS / таймауты. Не использовать подстроку "connection"
  /// целиком — в тексте ошибок сервера часто встречается «database connection», «too many connections» и т.п.
  bool _isQueueableSendError(Object e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HandshakeException) return true;
    if (e is ClientException) return true;
    final text = e.toString().toLowerCase();
    return text.contains('нет подключения к интернету') ||
        text.contains('socketexception') ||
        text.contains('timeoutexception') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('connection aborted') ||
        text.contains('broken pipe') ||
        text.contains('handshakeexception');
  }

  String _generateIdempotencyKey() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rnd = Random.secure().nextInt(1 << 32);
    return '${widget.chatId}-$now-${rnd.toRadixString(16)}';
  }

  void _cleanupTempStateCache() {
    final liveTempIds = _messages
        .where((m) => m.id.startsWith('temp_'))
        .map((m) => m.id)
        .toSet();
    for (final id in liveTempIds) {
      _tempMessageStates.putIfAbsent(id, () => _OutgoingUiState.queued);
    }
    _tempMessageStates.removeWhere((id, _) => !liveTempIds.contains(id));
    _tempMessageIdempotencyKeys.removeWhere(
      (id, _) => !liveTempIds.contains(id),
    );
    final toRemove = _pendingUploadDrafts.keys
        .where((id) => !liveTempIds.contains(id))
        .toList();
    for (final id in toRemove) {
      _pendingUploadDrafts.remove(id);
      unawaited(
        LocalMessagesService.removePendingUploadDraft(widget.chatId, id),
      );
    }
  }

  String _pendingPlaceholderText(_PendingUploadDraft draft) {
    if (draft.text.trim().isNotEmpty) return draft.text.trim();
    if (draft.hasImage) return '🖼️ Изображение (в очереди)';
    if (looksLikeAudio(mime: draft.fileMime, fileName: draft.fileName)) {
      return '🎤 Голосовое сообщение (в очереди)';
    }
    if (draft.hasFile) return '📎 Файл (в очереди)';
    return 'Сообщение в очереди';
  }

  Map<String, dynamic> _pendingDraftToJson(_PendingUploadDraft draft) {
    return {
      'text': draft.text,
      'idempotencyKey': draft.idempotencyKey,
      'replyToMessageId': draft.replyToMessageId,
      'replyToMessage': draft.replyToMessage?.toJson(),
      'imageBytesB64': draft.imageBytes != null
          ? base64Encode(draft.imageBytes!)
          : null,
      'imagePath': draft.imagePath,
      'imageName': draft.imageName,
      'fileBytesB64': draft.fileBytes != null
          ? base64Encode(draft.fileBytes!)
          : null,
      'filePath': draft.filePath,
      'fileName': draft.fileName,
      'fileSize': draft.fileSize,
      'fileMime': draft.fileMime,
    };
  }

  _PendingUploadDraft? _pendingDraftFromJson(Map<String, dynamic> json) {
    try {
      final replyRaw = json['replyToMessage'];
      Message? reply;
      if (replyRaw is Map) {
        final data = <String, dynamic>{};
        replyRaw.forEach((k, v) => data[k.toString()] = v);
        reply = Message.fromJson(data);
      }
      final imageB64 = json['imageBytesB64']?.toString();
      final fileB64 = json['fileBytesB64']?.toString();
      return _PendingUploadDraft(
        text: (json['text'] ?? '').toString(),
        idempotencyKey:
            (json['idempotencyKey'] ?? '').toString().trim().isNotEmpty
            ? (json['idempotencyKey'] ?? '').toString().trim()
            : _generateIdempotencyKey(),
        replyToMessageId: json['replyToMessageId']?.toString(),
        replyToMessage: reply,
        imageBytes: (imageB64 != null && imageB64.isNotEmpty)
            ? base64Decode(imageB64)
            : null,
        imagePath: json['imagePath']?.toString(),
        imageName: json['imageName']?.toString(),
        fileBytes: (fileB64 != null && fileB64.isNotEmpty)
            ? base64Decode(fileB64)
            : null,
        filePath: json['filePath']?.toString(),
        fileName: json['fileName']?.toString(),
        fileSize: json['fileSize'] is int
            ? json['fileSize'] as int
            : int.tryParse((json['fileSize'] ?? '').toString()),
        fileMime: json['fileMime']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _restorePendingUploadDrafts() async {
    final raw = await LocalMessagesService.getPendingUploadDrafts(
      widget.chatId,
    );
    if (raw.isEmpty || !mounted) return;

    final existingIds = _messages.map((m) => m.id).toSet();
    final restored = <Message>[];
    raw.forEach((tempId, draftJson) {
      final draft = _pendingDraftFromJson(draftJson);
      if (draft == null) return;
      _pendingUploadDrafts[tempId] = draft;
      _tempMessageIdempotencyKeys[tempId] = draft.idempotencyKey;
      _tempMessageStates.putIfAbsent(tempId, () => _OutgoingUiState.queued);
      if (!existingIds.contains(tempId)) {
        restored.add(
          Message(
            id: tempId,
            chatId: widget.chatId,
            userId: widget.userId,
            content: _pendingPlaceholderText(draft),
            fileName: draft.fileName,
            fileSize: draft.fileSize,
            fileMime: draft.fileMime,
            messageType: draft.hasImage
                ? (draft.text.trim().isNotEmpty ? 'text_image' : 'image')
                : (draft.hasFile
                      ? (looksLikeAudio(
                              mime: draft.fileMime,
                              fileName: draft.fileName,
                            )
                            ? (draft.text.trim().isNotEmpty
                                  ? 'text_voice'
                                  : 'voice')
                            : (draft.text.trim().isNotEmpty
                                  ? 'text_file'
                                  : 'file'))
                      : 'text'),
            senderEmail: widget.userEmail,
            senderAvatarUrl: widget.myAvatarUrl,
            createdAt: DateTime.now().toIso8601String(),
            replyToMessageId: draft.replyToMessageId,
            replyToMessage: draft.replyToMessage,
          ),
        );
      }
    });

    if (restored.isNotEmpty && mounted) {
      setState(() {
        _messages = List<Message>.from(_messages)..addAll(restored);
      });
    }
  }

  void _enqueuePendingUploadDraft(_PendingUploadDraft draft) {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = _pendingPlaceholderText(draft);
    final tempMessage = Message(
      id: tempId,
      chatId: widget.chatId,
      userId: widget.userId,
      content: placeholder,
      fileName: draft.fileName,
      fileSize: draft.fileSize,
      fileMime: draft.fileMime,
      messageType: draft.hasImage
          ? (draft.text.trim().isNotEmpty ? 'text_image' : 'image')
          : (draft.hasFile
                ? (looksLikeAudio(
                        mime: draft.fileMime,
                        fileName: draft.fileName,
                      )
                      ? (draft.text.trim().isNotEmpty ? 'text_voice' : 'voice')
                      : (draft.text.trim().isNotEmpty ? 'text_file' : 'file'))
                : 'text'),
      senderEmail: widget.userEmail,
      senderAvatarUrl: widget.myAvatarUrl,
      createdAt: DateTime.now().toIso8601String(),
      replyToMessageId: draft.replyToMessageId,
      replyToMessage: draft.replyToMessage,
    );

    setState(() {
      _messages = List<Message>.from(_messages)..add(tempMessage);
      _tempMessageStates[tempId] = _OutgoingUiState.queued;
      _tempMessageIdempotencyKeys[tempId] = draft.idempotencyKey;
      _pendingUploadDrafts[tempId] = draft;
      _isUploadingImage = false;
      _isUploadingFile = false;
      _selectedImagePath = null;
      _selectedImageBytes = null;
      _selectedImageName = null;
      _selectedFilePath = null;
      _selectedFileBytes = null;
      _selectedFileName = null;
      _selectedFileSize = null;
      _replyToMessage = null;
    });
    unawaited(
      LocalMessagesService.savePendingUploadDraft(
        widget.chatId,
        tempId,
        _pendingDraftToJson(draft),
      ),
    );
    _controller.clear();
    _scrollToBottom();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 3),
        content: Text('Нет сети: вложение добавлено в очередь отправки'),
      ),
    );
  }

  Future<Message?> _sendPendingUploadDraft(_PendingUploadDraft draft) async {
    String? imageUrl;
    String? imageStorageKey;
    String? originalImageUrl;
    String? originalImageStorageKey;
    String? fileUrl;
    String? fileStorageKey;
    String? fileName;
    int? fileSize;
    String? fileMime;

    if (draft.hasImage) {
      Uint8List originalBytes;
      if (draft.imageBytes != null) {
        originalBytes = draft.imageBytes!;
      } else if (draft.imagePath != null && draft.imagePath!.isNotEmpty) {
        originalBytes = await File(draft.imagePath!).readAsBytes();
      } else {
        throw Exception('Изображение для очереди не найдено');
      }
      final compressed = await _compressImage(originalBytes);
      final imgName =
          draft.imageName ??
          (draft.imagePath != null && draft.imagePath!.isNotEmpty
              ? draft.imagePath!.split('/').last
              : 'image.jpg');
      final uploaded = await _messagesService.uploadImageWithUrls(
        compressed,
        imgName,
        originalBytes: originalBytes,
        chatId: widget.chatId.toString(),
      );
      imageUrl = uploaded.imageUrl;
      imageStorageKey = uploaded.imageStorageKey;
      originalImageUrl = uploaded.originalImageUrl;
      originalImageStorageKey = uploaded.originalImageStorageKey;
    }

    if (draft.hasFile) {
      List<int> bytes;
      if (draft.fileBytes != null) {
        bytes = draft.fileBytes!;
      } else if (draft.filePath != null && draft.filePath!.isNotEmpty) {
        bytes = await File(draft.filePath!).readAsBytes();
      } else {
        throw Exception('Файл для очереди не найден');
      }
      final name =
          draft.fileName ??
          (draft.filePath != null && draft.filePath!.isNotEmpty
              ? draft.filePath!.split('/').last
              : 'file');
      final meta = await _messagesService.uploadFile(bytes, name);
      fileUrl = meta['file_url']?.toString();
      fileStorageKey = meta['file_storage_key']?.toString();
      fileName = (meta['file_name'] ?? name).toString();
      fileSize =
          int.tryParse((meta['file_size'] ?? '').toString()) ??
          draft.fileSize ??
          bytes.length;
      fileMime = (meta['file_mime'] ?? draft.fileMime ?? '').toString();
    }

    return _messagesService.sendMessage(
      widget.chatId,
      draft.text,
      idempotencyKey: draft.idempotencyKey,
      imageUrl: imageUrl,
      imageStorageKey: imageStorageKey,
      originalImageUrl: originalImageUrl,
      originalImageStorageKey: originalImageStorageKey,
      fileUrl: fileUrl,
      fileStorageKey: fileStorageKey,
      fileName: fileName,
      fileSize: fileSize,
      fileMime: fileMime,
      replyToMessageId: draft.replyToMessageId,
    );
  }

  Future<void> _retryQueuedMessages() async {
    if (!mounted || _isRetryingQueuedMessages || _isSendingMessage) return;
    _cleanupTempStateCache();
    final queuedMessages = _messages
        .where(
          (m) =>
              m.id.startsWith('temp_') &&
              _tempMessageStates[m.id] == _OutgoingUiState.queued,
        )
        .toList();
    if (queuedMessages.isEmpty) return;

    _isRetryingQueuedMessages = true;
    try {
      for (final temp in queuedMessages) {
        if (!mounted) break;
        if (!_messages.any((m) => m.id == temp.id)) continue;
        setState(() => _tempMessageStates[temp.id] = _OutgoingUiState.sending);

        try {
          final draft = _pendingUploadDrafts[temp.id];
          final sent = draft != null
              ? await _sendPendingUploadDraft(draft)
              : await _messagesService.sendMessage(
                  widget.chatId,
                  temp.content,
                  idempotencyKey: _tempMessageIdempotencyKeys[temp.id],
                  imageUrl: temp.imageUrl,
                  originalImageUrl: temp.originalImageUrl,
                  fileUrl: temp.fileUrl,
                  fileName: temp.fileName,
                  fileSize: temp.fileSize,
                  fileMime: temp.fileMime,
                  replyToMessageId: temp.replyToMessageId,
                );

          if (!mounted) break;
          if (sent == null) {
            setState(
              () => _tempMessageStates[temp.id] = _OutgoingUiState.queued,
            );
            continue;
          }

          setState(() {
            final idx = _messages.indexWhere((m) => m.id == temp.id);
            final newMessages = List<Message>.from(_messages);
            if (idx != -1) {
              newMessages[idx] = sent;
            } else {
              newMessages.add(sent);
            }
            _messages = newMessages;
            _tempMessageStates.remove(temp.id);
            _tempMessageIdempotencyKeys.remove(temp.id);
            _pendingUploadDrafts.remove(temp.id);
            unawaited(
              LocalMessagesService.removePendingUploadDraft(
                widget.chatId,
                temp.id,
              ),
            );
            _cleanupTempStateCache();
          });
        } catch (e) {
          final shouldStayQueued = _isQueueableSendError(e);
          if (!mounted) break;
          setState(() {
            _tempMessageStates[temp.id] = shouldStayQueued
                ? _OutgoingUiState.queued
                : _OutgoingUiState.error;
          });
        }
      }
    } finally {
      _isRetryingQueuedMessages = false;
      if (mounted) {
        setState(() {
          _cleanupTempStateCache();
        });
      }
    }
  }

  Future<void> _retryErroredMessages() async {
    if (!mounted) return;
    setState(() {
      for (final entry in _tempMessageStates.entries.toList()) {
        if (entry.value == _OutgoingUiState.error) {
          _tempMessageStates[entry.key] = _OutgoingUiState.queued;
        }
      }
    });
    await _retryQueuedMessages();
  }

  Future<void> _clearPendingQueue() async {
    if (!mounted) return;
    final tempIds = _messages
        .where((m) => m.id.startsWith('temp_'))
        .map((m) => m.id)
        .toSet();
    if (tempIds.isEmpty) return;

    setState(() {
      _messages = _messages.where((m) => !tempIds.contains(m.id)).toList();
      for (final id in tempIds) {
        _tempMessageStates.remove(id);
        _pendingUploadDrafts.remove(id);
      }
    });
    await LocalMessagesService.clearPendingUploadDrafts(widget.chatId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Очередь отправки очищена'),
      ),
    );
  }
}
