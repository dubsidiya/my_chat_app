// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenTypingComposerPart on _ChatScreenState {
  void _scheduleTypingCleanup() {
    _typingCleanupTimer?.cancel();
    _typingCleanupTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final now = DateTime.now();
      final toRemove = _typingUntilByUserId.entries
          .where((e) => e.value.isBefore(now))
          .map((e) => e.key)
          .toList();
      if (toRemove.isEmpty) return;
      setState(() {
        for (final k in toRemove) {
          _typingUntilByUserId.remove(k);
        }
      });
    });
  }

  void _sendTyping(bool isTyping) {
    _sendWsJson({
      'type': 'typing',
      'chat_id': widget.chatId,
      'is_typing': isTyping,
    });
    _sentTyping = isTyping;
  }

  void _handleComposerChanged(String text) {
    final trimmed = text.trim();
    final shouldType = trimmed.isNotEmpty;

    if (shouldType && !_sentTyping) {
      _sendTyping(true);
    }
    if (!shouldType && _sentTyping) {
      _sendTyping(false);
    }

    _typingStopTimer?.cancel();
    if (shouldType) {
      _typingStopTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_sentTyping) _sendTyping(false);
      });
    }

    _updateMentionSuggestions(text);
  }

  String _handleFromEmail(String email) {
    final e = email.trim();
    final at = e.indexOf('@');
    final local = (at >= 1 ? e.substring(0, at) : e).trim().toLowerCase();
    if (local.isEmpty) return '';
    // ограничим безопасным набором, чтобы handle был стабильным
    final cleaned = local.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return cleaned;
  }

  void _updateMentionSuggestions(String text) {
    final sel = _controller.selection;
    int cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) cursor = text.length;

    final prefix = text.substring(0, cursor);
    final at = prefix.lastIndexOf('@');
    if (at == -1) {
      if (_mentionSuggestions.isNotEmpty || _mentionStart != -1) {
        setState(() {
          _mentionStart = -1;
          _mentionQuery = '';
          _mentionSuggestions = [];
        });
      }
      return;
    }

    // '@' должно начинать токен (после пробела/переноса/начала)
    if (at > 0) {
      final prev = prefix[at - 1];
      if (!RegExp(r'\s').hasMatch(prev)) {
        return;
      }
    }

    final q = prefix.substring(at + 1);
    if (q.contains(RegExp(r'\s')) || q.contains('/')) {
      // закрываем overlay, если завершили токен
      if (_mentionSuggestions.isNotEmpty || _mentionStart != -1) {
        setState(() {
          _mentionStart = -1;
          _mentionQuery = '';
          _mentionSuggestions = [];
        });
      }
      return;
    }

    final query = q.toLowerCase();
    final suggestions = <Map<String, String>>[];
    final seen = <String>{};
    for (final m in _chatMembers) {
      final id = (m['id'] ?? '').toString();
      final email = (m['email'] ?? '').toString();
      if (id.isEmpty || email.isEmpty) continue;
      final handle = _handleFromEmail(email);
      if (handle.isEmpty) continue;
      if (seen.contains(handle)) continue;
      final label = (m['displayName'] ?? m['display_name'] ?? email).toString();

      if (query.isNotEmpty) {
        if (!handle.contains(query) &&
            !label.toLowerCase().contains(query) &&
            !email.toLowerCase().contains(query)) {
          continue;
        }
      }

      suggestions.add({
        'id': id,
        'email': email,
        'label': label,
        'handle': handle,
      });
      seen.add(handle);
      if (suggestions.length >= 8) break;
    }

    final changed =
        _mentionStart != at ||
        _mentionQuery != query ||
        suggestions.length != _mentionSuggestions.length;
    if (!changed) return;
    setState(() {
      _mentionStart = at;
      _mentionQuery = query;
      _mentionSuggestions = suggestions;
    });
  }

  void _insertMention(String handle) {
    final text = _controller.text;
    final sel = _controller.selection;
    int cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    if (_mentionStart < 0 ||
        _mentionStart >= text.length ||
        _mentionStart > cursor)
      return;
    final before = text.substring(0, _mentionStart);
    final after = text.substring(cursor);
    final insert = '@$handle ';
    final next = '$before$insert$after';
    final nextCursor = (before.length + insert.length);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    setState(() {
      _mentionStart = -1;
      _mentionQuery = '';
      _mentionSuggestions = [];
    });
  }

  void _openUserProfileById(String userId, {String? fallbackLabel}) {
    final otherId = userId.toString().trim();
    if (otherId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            UserProfileScreen(userId: otherId, fallbackLabel: fallbackLabel),
      ),
    );
  }

  Future<void> _openMentions() async {
    final myHandle = _handleFromEmail(widget.userEmail);
    if (myHandle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Не удалось определить ваш handle'),
        ),
      );
      return;
    }
    final query = '@$myHandle';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<Map<String, dynamic>> results = [];
        bool isLoading = true;
        String? error;
        bool started = false;

        Future<void> load(StateSetter setModalState) async {
          setModalState(() {
            isLoading = true;
            error = null;
          });
          try {
            final found = await _messagesService.searchMessages(
              widget.chatId,
              query,
              limit: 50,
            );
            setModalState(() {
              results = found;
              isLoading = false;
            });
          } catch (e) {
            // fallback: локальный поиск в уже загруженных сообщениях
            final local = _messages
                .where(
                  (m) => m.content.toLowerCase().contains(query.toLowerCase()),
                )
                .take(50)
                .map(
                  (m) => {
                    'message_id': m.id,
                    'sender_email': m.senderEmail,
                    'content_snippet': m.content.length > 80
                        ? '${m.content.substring(0, 80)}…'
                        : m.content,
                    'created_at': m.createdAt,
                  },
                )
                .toList();
            setModalState(() {
              results = local;
              error = e.toString().replaceFirst('Exception: ', '');
              isLoading = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!started) {
              started = true;
              scheduleMicrotask(() => load(setModalState));
            }
            final scheme = Theme.of(context).colorScheme;
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.alternate_email_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Упоминания $query',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: isLoading
                                ? null
                                : () => load(setModalState),
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Обновить',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoading)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryGlow,
                          ),
                        ),
                      )
                    else if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Упоминаний пока нет',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: scheme.outline.withValues(alpha: 0.18),
                          ),
                          itemBuilder: (context, index) {
                            final r = results[index];
                            final mid = (r['message_id'] ?? r['id'] ?? '')
                                .toString();
                            final sender = (r['sender_email'] ?? '').toString();
                            final snippet =
                                (r['content_snippet'] ?? r['content'] ?? '')
                                    .toString();
                            return ListTile(
                              title: Text(
                                snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: sender.isEmpty
                                  ? null
                                  : Text(
                                      sender,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: mid.isEmpty
                                  ? null
                                  : () async {
                                      Navigator.pop(sheetContext);
                                      await _jumpToMessage(mid);
                                    },
                            );
                          },
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _buildChatStatusLine() {
    final now = DateTime.now();
    final typingIds = _typingUntilByUserId.entries
        .where((e) => e.value.isAfter(now))
        .map((e) => e.key)
        .where((id) => id != widget.userId.toString())
        .toList();

    if (typingIds.isNotEmpty) {
      final names = typingIds
          .map((id) => _memberEmailById[id] ?? 'Пользователь')
          .toList();
      if (names.length == 1) return '${names.first} печатает…';
      if (names.length == 2) return '${names[0]} и ${names[1]} печатают…';
      return 'Несколько участников печатают…';
    }

    // online count (кроме себя)
    final onlineOthers = _onlineUserIds
        .where((id) => id != widget.userId.toString())
        .length;
    if (onlineOthers > 0) return 'Онлайн: $onlineOthers';

    return 'Вы: ${widget.displayName ?? widget.userEmail}';
  }

}
