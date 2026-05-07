part of 'chat_screen.dart';

extension _ChatScreenMembersPart on _ChatScreenState {
  Future<void> _showMembersDialog() async {
    if (!mounted) return;

    try {
      // Получаем участников чата
      final members = await _chatsService.getChatMembers(widget.chatId);

      if (!mounted) return;

      // Показываем диалог со списком участников
      await showDialog(
        context: context,
        builder: (context) => ChatMembersDialog(
          members: members,
          currentUserId: widget.userId,
          chatId: widget.chatId,
          chatsService: _chatsService,
        ),
      );
    } catch (e) {
      if (kDebugMode) print('Ошибка загрузки участников: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка при загрузке участников: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Выход из чата.
  Future<void> _leaveChat() async {
    if (!mounted) return;

    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из чата?'),
        content: Text(
          'Вы уверены, что хотите выйти из чата "${widget.chatName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _chatsService.leaveChat(widget.chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вы вышли из чата'),
            duration: Duration(seconds: 2),
          ),
        );
        // Возвращаемся на предыдущий экран
        Navigator.pop(context);
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка выхода из чата: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка при выходе из чата: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _showAddMembersDialog() async {
    if (!mounted) return;

    try {
      // Получаем список всех пользователей
      final allUsers = await _chatsService.getAllUsers(widget.userId);

      // Получаем текущих участников чата
      final currentMembers = await _chatsService.getChatMembers(widget.chatId);
      final currentMemberIds = currentMembers.map((m) => m['id']).toSet();

      // Фильтруем пользователей, которые еще не в чате
      final availableUsers = allUsers
          .where((user) => !currentMemberIds.contains(user['id']))
          .toList();

      if (availableUsers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 3),
              content: Text('Нет доступных пользователей для добавления'),
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      // Показываем диалог выбора пользователей
      final selectedUsers = await showDialog<Set<String>>(
        context: context,
        builder: (context) => AddMembersDialog(availableUsers: availableUsers),
      );

      if (selectedUsers != null && selectedUsers.isNotEmpty && mounted) {
        try {
          await _chatsService.addMembersToChat(
            widget.chatId,
            selectedUsers.toList(),
          );
          // E2EE: отправить ключ чата новым участникам (как при входе по инвайту)
          E2eeService.shareChatKeyWithNewMembers(widget.chatId.toString());
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Участники успешно добавлены'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (kDebugMode) print('Ошибка добавления участников: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Ошибка при добавлении участников: ${e.toString().replaceFirst('Exception: ', '')}',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка загрузки пользователей: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ошибка при загрузке списка пользователей: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _openUserProfile(Message msg) {
    final otherId = msg.userId.toString().trim();
    if (otherId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            UserProfileScreen(userId: otherId, fallbackLabel: msg.senderEmail),
      ),
    );
  }

  void _openImageViewer(Message msg) {
    final url = (msg.imageUrl ?? '').trim();
    if (url.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ChatFullscreenImageViewer(
          imageUrl: url,
          chatId: widget.chatId.toString(),
          originalImageUrl: (msg.originalImageUrl ?? url),
          fileName: url.split('/').last.isNotEmpty
              ? url.split('/').last
              : 'image.jpg',
          onDownload: () => _downloadImage(
            (msg.originalImageUrl ?? url),
            url.split('/').last.isNotEmpty ? url.split('/').last : 'image.jpg',
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}
