// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenMessageActionsPart on _ChatScreenState {
  /// Установить сообщение как ответ и прокрутить к полю ввода (для свайпа «Ответить» и меню).
  void _setReplyAndScrollToInput(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Меню действий с сообщением.
  Future<void> _showMessageMenu(Message message, {bool isMine = true}) async {
    if (!mounted) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final canEdit =
            isMine && message.hasText && !message.hasImage && !message.hasFile;

        Widget chip({
          required IconData icon,
          required String label,
          required String value,
        }) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context, value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.cardDark, AppColors.surfaceDark],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderDark),
              boxShadow: AppColors.neonGlowSoft,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Действия',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    chip(
                      icon: Icons.reply_rounded,
                      label: 'Ответить',
                      value: 'reply',
                    ),
                    chip(
                      icon: Icons.forward_rounded,
                      label: 'Переслать',
                      value: 'forward',
                    ),
                    chip(
                      icon: Icons.emoji_emotions_rounded,
                      label: 'Реакция',
                      value: 'reaction',
                    ),
                    if (canEdit)
                      chip(
                        icon: Icons.edit_rounded,
                        label: 'Редакт.',
                        value: 'edit',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: scheme.outline.withValues(alpha: 0.20),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    message.isPinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                  title: Text(message.isPinned ? 'Открепить' : 'Закрепить'),
                  onTap: () => Navigator.pop(
                    context,
                    message.isPinned ? 'unpin' : 'pin',
                  ),
                ),
                if (!isMine) ...[
                  Divider(
                    height: 1,
                    color: scheme.outline.withValues(alpha: 0.20),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.flag_outlined,
                      color: scheme.onSurface.withValues(alpha: 0.85),
                    ),
                    title: const Text('Пожаловаться'),
                    onTap: () => Navigator.pop(context, 'report'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.block_rounded,
                      color: Colors.orange.shade700,
                    ),
                    title: Text(
                      'Заблокировать пользователя',
                      style: TextStyle(color: Colors.orange.shade700),
                    ),
                    onTap: () => Navigator.pop(context, 'block'),
                  ),
                ],
                if (widget.isGroup ? isMine : true) ...[
                  Divider(
                    height: 1,
                    color: scheme.outline.withValues(alpha: 0.20),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red.shade400,
                    ),
                    title: Text(
                      'Удалить',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (action == 'reply') {
      _setReplyAndScrollToInput(message);
    } else if (action == 'forward') {
      _showForwardDialog(message);
    } else if (action == 'edit') {
      _showEditMessageDialog(message);
    } else if (action == 'pin') {
      _pinMessage(message);
    } else if (action == 'unpin') {
      _unpinMessage(message);
    } else if (action == 'reaction') {
      _showReactionPicker(message);
    } else if (action == 'delete') {
      _showDeleteMessageDialog(message);
    } else if (action == 'report') {
      _reportMessage(message);
    } else if (action == 'block') {
      _blockSender(message);
    }
  }

  Future<void> _reportMessage(Message message) async {
    try {
      await _moderationService.reportMessage(message.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text(
              'Жалоба отправлена. Модерация рассмотрит в течение 24 часов.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _blockSender(Message message) async {
    if (message.userId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заблокировать пользователя?'),
        content: Text(
          'Сообщения от ${message.senderEmail} будут скрыты. Вы сможете разблокировать через настройки.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _moderationService.blockUser(message.userId);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.userId == message.userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Пользователь заблокирован. Его сообщения скрыты.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  // Диалог пересылки сообщения.
  Future<void> _showForwardDialog(Message message) async {
    if (!mounted) return;

    // Загружаем список чатов пользователя
    final chats = await _chatsService.fetchChats(widget.userId);
    if (!mounted) return;
    final availableChats = chats
        .where((chat) => chat.id != widget.chatId)
        .toList();

    if (availableChats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Нет других чатов для пересылки'),
        ),
      );
      return;
    }

    // Состояние выбранных чатов
    final selectedChatIds = <String>{};

    final selectedChats = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Переслать сообщение'),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableChats.length,
                  itemBuilder: (context, index) {
                    final chat = availableChats[index];
                    final isSelected = selectedChatIds.contains(chat.id);
                    return CheckboxListTile(
                      title: Text(chat.name),
                      value: isSelected,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selectedChatIds.add(chat.id);
                          } else {
                            selectedChatIds.remove(chat.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: selectedChatIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context, selectedChatIds.toList());
                        },
                  child: const Text('Переслать'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedChats != null && selectedChats.isNotEmpty) {
      try {
        await _messagesService.forwardMessage(
          message,
          widget.chatId.toString(),
          selectedChats,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text(
                'Сообщение переслано в ${selectedChats.length} чат(ов)',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Ошибка пересылки: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _pinMessage(Message message) async {
    try {
      await _messagesService.pinMessage(message.id);
      if (!mounted) return;
      await _loadPinnedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Сообщение закреплено'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка закрепления: $e'),
          ),
        );
      }
    }
  }

  Future<void> _unpinMessage(Message message) async {
    try {
      await _messagesService.unpinMessage(message.id);
      if (!mounted) return;
      await _loadPinnedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Сообщение откреплено'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка открепления: $e'),
          ),
        );
      }
    }
  }

  Future<void> _showReactionPicker(Message message) async {
    if (!mounted) return;

    final reaction = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _buildReactionButton('👍', context),
              _buildReactionButton('❤️', context),
              _buildReactionButton('😂', context),
              _buildReactionButton('😮', context),
              _buildReactionButton('😢', context),
              _buildReactionButton('🙏', context),
              _buildReactionButton('🔥', context),
              _buildReactionButton('⭐', context),
            ],
          ),
        ),
      ),
    );

    if (reaction != null) {
      try {
        // Проверяем, есть ли уже такая реакция
        final hasReaction =
            message.reactions?.any((r) => r.reaction == reaction) ?? false;
        if (hasReaction) {
          await _messagesService.removeReaction(message.id, reaction);
        } else {
          await _messagesService.addReaction(message.id, reaction);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Ошибка: $e'),
            ),
          );
        }
      }
    }
  }

  Widget _buildReactionButton(String emoji, BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, emoji),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
      ),
    );
  }

  Future<void> _showEditMessageDialog(Message message) async {
    if (!mounted) return;

    final textController = TextEditingController(text: message.content);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать сообщение'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Введите текст сообщения',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final newContent = textController.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context, {'content': newContent});
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result != null && result['content'] != null) {
      try {
        await _messagesService.editMessage(
          message.id,
          content: result['content']!,
          chatId: widget.chatId.toString(),
        );
        if (mounted) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              final prev = _messages[index];
              _messages[index] = Message(
                id: prev.id,
                chatId: prev.chatId,
                userId: prev.userId,
                content: result['content']!,
                imageUrl: prev.imageUrl,
                originalImageUrl: prev.originalImageUrl,
                fileUrl: prev.fileUrl,
                fileName: prev.fileName,
                fileSize: prev.fileSize,
                fileMime: prev.fileMime,
                messageType: prev.messageType,
                senderEmail: prev.senderEmail,
                senderAvatarUrl: prev.senderAvatarUrl,
                createdAt: prev.createdAt,
                deliveredAt: prev.deliveredAt,
                editedAt: DateTime.now().toIso8601String(),
                isRead: prev.isRead,
                readAt: prev.readAt,
                replyToMessageId: prev.replyToMessageId,
                replyToMessage: prev.replyToMessage,
                isPinned: prev.isPinned,
                reactions: prev.reactions,
                isForwarded: prev.isForwarded,
                originalChatName: prev.originalChatName,
                keyVersion: prev.keyVersion,
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Ошибка редактирования сообщения: $e'),
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteMessageDialog(Message message) async {
    if (!mounted) return;

    final isMine =
        message.userId.toString() == widget.userId.toString();

    final String? scope;
    if (!widget.isGroup) {
      scope = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: Text(
            isMine
                ? 'Удалить только у вас или у обоих собеседников?'
                : 'Сообщение исчезнет только в вашей переписке.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'for_me'),
              child: const Text('Удалить у меня'),
            ),
            if (isMine)
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'for_everyone'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Удалить у всех'),
              ),
          ],
        ),
      );
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text(
            'Вы уверены, что хотите удалить это сообщение у всех участников?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      scope = confirmed == true ? 'for_everyone' : null;
    }

    if (scope == null || !mounted) return;

    try {
      await _messagesService.deleteMessage(
        message.id.toString(),
        widget.userId,
        scope: scope,
      );
      await LocalMessagesService.removeMessage(widget.chatId, message.id);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
          _pinnedMessages.removeWhere((m) => m.id == message.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              scope == 'for_me'
                  ? 'Сообщение удалено у вас'
                  : 'Сообщение удалено у всех',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка удаления сообщения: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка при удалении сообщения: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    if (!mounted) return;

    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить чат?'),
        content: const Text(
          'Вы уверены, что хотите удалить все сообщения из этого чата? Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _messagesService.clearChat(widget.chatId, widget.userId);
      await LocalMessagesService.clearChat(widget.chatId);
      if (mounted) {
        setState(() {
          _messages.clear();
          _pinnedMessages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Чат успешно очищен'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка очистки чата: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка при очистке чата: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
