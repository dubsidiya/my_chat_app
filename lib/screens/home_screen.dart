import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/chat.dart';
import '../models/chat_folder.dart';
import '../services/chats_service.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import '../services/e2ee_service.dart';
import '../services/local_messages_service.dart';
import '../theme/app_colors.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'students_screen.dart';
import 'reports_chat_screen.dart';
import 'profile_screen.dart';
import 'user_profile_screen.dart';
import 'home_dialogs.dart';
import '../utils/page_routes.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? avatarUrl;
  final bool isSuperuser;

  const HomeScreen({super.key, required this.userId, required this.userEmail, this.displayName, this.avatarUrl, this.isSuperuser = false});

  @override
  // ignore: library_private_types_in_public_api
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatsService _chatsService = ChatsService();
  final AuthService _authService = AuthService();
  List<Chat> _chats = [];
  List<ChatFolder> _folders = [];
  String? _folderFilterId; // null = all
  String? _displayName;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
    _avatarUrl = widget.avatarUrl;
    unawaited(_ensureE2eeIdentity());
    _loadChats();
    _loadFolders();
    _subscribeToNewMessages();
  }

  Future<void> _ensureE2eeIdentity() async {
    try {
      await E2eeService.ensureKeyPair();
    } catch (_) {
      // Не блокируем загрузку домашнего экрана, если E2EE сервер временно недоступен.
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayName != widget.displayName) _displayName = widget.displayName;
    if (oldWidget.avatarUrl != widget.avatarUrl) _avatarUrl = widget.avatarUrl;
  }
  List<String> _chatOrder = []; // порядок чатов (id), для перетаскивания
  bool _isLoading = false;
  String? _loadError; // ошибка загрузки чатов для показа кнопки «Повторить»
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  StreamSubscription<dynamic>? _wsSubscription;
  DateTime? _lastWsReconnectHandledAt;

  Widget _avatarInitial(String initial) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDeep],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _chatAvatarPlaceholder(String chatName) {
    final letter = chatName.trim().isNotEmpty ? chatName.trim()[0].toUpperCase() : '?';
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDeep],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  String _formatLastMessageTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      if (sameDay) {
        return DateFormat('HH:mm').format(dt);
      }
      return DateFormat('dd.MM').format(dt);
    } catch (_) {
      return '';
    }
  }

  String _buildLastMessagePreview(Chat chat) {
    if ((chat.lastMessageId ?? '').isEmpty) return 'Нет сообщений';
    final type = chat.lastMessageType ?? 'text';
    final hasImage = (chat.lastMessageImageUrl ?? '').isNotEmpty;
    final hasFile = (chat.lastMessageFileUrl ?? '').isNotEmpty;
    final text = (chat.lastMessageText ?? '').trim();
    if (type == 'image' || (hasImage && text.isEmpty)) return 'Фото';
    if (type == 'file' || (hasFile && text.isEmpty)) return 'Файл';
    if (type == 'text_file' && hasFile) {
      return text.isNotEmpty ? 'Файл · $text' : 'Файл';
    }
    if (type == 'text_image' && hasImage) {
      return text.isNotEmpty ? 'Фото · $text' : 'Фото';
    }
    return text.isNotEmpty ? text : 'Сообщение';
  }

  Future<void> _joinByInviteDialog() async {
    final controller = TextEditingController();
    bool isLoading = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> doJoin() async {
              final code = controller.text.trim();
              if (code.isEmpty) {
                setLocal(() => error = 'Введите код');
                return;
              }
              setLocal(() {
                isLoading = true;
                error = null;
              });
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              try {
                await _chatsService.joinByInviteCode(code);
                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Готово: вы вступили в чат')),
                );
                _loadChats();
              } catch (e) {
                setLocal(() {
                  isLoading = false;
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Вступить по коду'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Код инвайта',
                      errorText: error,
                    ),
                    onSubmitted: (_) => doJoin(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : doJoin,
                  child: isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Вступить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openProfile() async {
    await Navigator.push<void>(
      context,
      slideAndFadeRoute<void>(
        page: ProfileScreen(
          userId: widget.userId,
          userEmail: widget.userEmail,
          displayName: _displayName,
          avatarUrl: _avatarUrl,
          isSuperuser: widget.isSuperuser,
          onProfileUpdated: () async {
            final me = await _authService.fetchMe();
            if (me != null && mounted) {
              setState(() {
                _displayName = me['displayName']?.toString();
                _avatarUrl = me['avatarUrl'] ?? me['avatar_url']?.toString();
              });
            }
          },
          onChangePassword: _changePassword,
          onAdminResetPassword: _adminResetPassword,
          onDeleteAccount: _deleteAccount,
          onLogout: _logout,
        ),
      ),
    );
    if (mounted) {
      final userData = await StorageService.getUserData();
      if (!mounted) return;
      if (userData != null) {
        setState(() {
          _displayName = userData['displayName']?.toString();
          _avatarUrl = userData['avatarUrl']?.toString();
        });
      }
    }
  }

  void _subscribeToNewMessages() {
    WebSocketService.instance.connectIfNeeded();
    _wsSubscription?.cancel();
    _wsSubscription = WebSocketService.instance.stream.listen((event) {
      if (!mounted) return;
      if (event is Map && event['type'] == '_ws_reconnected') {
        final now = DateTime.now();
        if (_lastWsReconnectHandledAt != null &&
            now.difference(_lastWsReconnectHandledAt!).inSeconds < 10) {
          return;
        }
        _lastWsReconnectHandledAt = now;
        // Единая точка мягкого восстановления после реконнекта:
        // обновляем список чатов и пробуем закрыть отложенные E2EE key-requests.
        _loadChats();
        final chatIds = _chats.map((c) => c.id).where((id) => id.isNotEmpty).toSet();
        for (final chatId in chatIds) {
          unawaited(E2eeService.processPendingKeyRequests(chatId));
        }
        return;
      }
      if (event is Map && event['type'] == 'e2ee_request_key') {
        final chatId = event['chatId']?.toString();
        final requesterUserId = event['userId']?.toString();
        final keyVersion = event['keyVersion'] is int
            ? event['keyVersion'] as int
            : int.tryParse((event['keyVersion'] ?? '').toString());
        if (chatId != null) {
          if (requesterUserId != null && requesterUserId.isNotEmpty) {
            unawaited(E2eeService.shareChatKeyWithUsers(chatId, [requesterUserId], keyVersion: keyVersion));
          } else {
            unawaited(E2eeService.shareChatKeyWithNewMembers(chatId));
          }
        }
        return;
      }
      if (event is Map && event['type'] == 'e2ee_key_rotated') {
        final chatId = event['chatId']?.toString();
        final keyVersion = event['keyVersion'] is int
            ? event['keyVersion'] as int
            : int.tryParse((event['keyVersion'] ?? '').toString());
        final leaderUserId = event['leaderUserId']?.toString();
        if (chatId != null && keyVersion != null && keyVersion > 0) {
          unawaited(_handleE2eeKeyRotationEvent(chatId, keyVersion, leaderUserId));
        }
        return;
      }
      // Новое сообщение в любой чат: обновляем список чатов
      if (event is Map && event['chat_id'] != null && event['id'] != null) {
        final type = event['type']?.toString();
        if (type == null || type.isEmpty || type == 'message') {
          _loadChats();
        }
      }
    });
  }

  Future<void> _handleE2eeKeyRotationEvent(String chatId, int keyVersion, String? leaderUserId) async {
    final myId = widget.userId.toString();
    if (leaderUserId != null && leaderUserId == myId) {
      try {
        await E2eeService.ensureKeyPair();
        final members = await _chatsService.getChatMembers(chatId);
        final memberIds = members.map((m) => m['id']?.toString() ?? '').where((x) => x.isNotEmpty).toList();
        final pubKeys = await E2eeService.fetchPublicKeys(memberIds);
        final keysMembers = memberIds
            .map((id) => <String, dynamic>{'id': id, 'publicKey': pubKeys[id] ?? ''})
            .toList();
        await E2eeService.createChatKey(chatId, keysMembers, keyVersion: keyVersion);
        return;
      } catch (_) {
        // fall back to request path
      }
    }
    try {
      await E2eeService.requestChatKey(chatId, keyVersion: keyVersion);
      await E2eeService.waitForChatKeyFromServer(chatId, keyVersion: keyVersion);
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      var chats = await _chatsService.fetchChats(widget.userId);
      final List<Chat> decryptedChats = [];
      for (final c in chats) {
        if (c.lastMessageText != null && E2eeService.isEncrypted(c.lastMessageText!)) {
          final plain = await E2eeService.decryptMessage(c.id, c.lastMessageText!);
          decryptedChats.add(Chat(
            id: c.id, name: c.name, isGroup: c.isGroup,
            folderId: c.folderId, folderName: c.folderName,
            otherUserId: c.otherUserId, otherUserAvatarUrl: c.otherUserAvatarUrl,
            lastMessageId: c.lastMessageId, lastMessageText: plain,
            lastMessageType: c.lastMessageType, lastMessageImageUrl: c.lastMessageImageUrl,
            lastMessageFileUrl: c.lastMessageFileUrl, lastMessageFileName: c.lastMessageFileName,
            lastMessageFileSize: c.lastMessageFileSize, lastMessageFileMime: c.lastMessageFileMime,
            lastMessageAt: c.lastMessageAt, lastSenderEmail: c.lastSenderEmail,
            unreadCount: c.unreadCount,
          ));
        } else {
          decryptedChats.add(c);
        }
      }
      chats = decryptedChats;
      final order = await StorageService.getChatOrder(widget.userId);
      if (mounted) {
        setState(() {
          _chats = chats;
          _chatOrder = order;
          _loadError = null;
          if (_chatOrder.isEmpty && _chats.isNotEmpty) {
            _chatOrder = _chats.map((c) => c.id).toList();
          }
        });
      }
      unawaited(_processPendingE2eeRequestsForChats(chats));
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ошибка при загрузке чатов'),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: _loadChats,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _processPendingE2eeRequestsForChats(List<Chat> chats) async {
    for (final chat in chats) {
      if (chat.id.isEmpty) continue;
      try {
        await E2eeService.processPendingKeyRequests(chat.id);
      } catch (_) {}
    }
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await _chatsService.fetchFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        // если фильтр указывает на несуществующую папку — сбрасываем
        if (_folderFilterId != null && !_folders.any((f) => f.id == _folderFilterId)) {
          _folderFilterId = null;
        }
      });
    } catch (e) {
      // не блокируем UI — просто нет папок
      if (kDebugMode) print('Ошибка загрузки папок: $e');
    }
  }

  /// Чаты в сохранённом порядке (сначала по _chatOrder, затем остальные по дате последнего сообщения).
  List<Chat> get _sortedChats {
    if (_chats.isEmpty) return [];
    final orderIds = _chatOrder.where((id) => _chats.any((c) => c.id == id)).toList();
    final rest = _chats.where((c) => !_chatOrder.contains(c.id)).toList();
    rest.sort((a, b) {
      final at = a.lastMessageAt ?? '';
      final bt = b.lastMessageAt ?? '';
      return bt.compareTo(at);
    });
    final List<Chat> out = [];
    for (final id in orderIds) {
      final found = _chats.where((c) => c.id == id).toList();
      if (found.isNotEmpty) out.add(found.first);
    }
    out.addAll(rest);
    return out;
  }

  void _onReorderChats(int oldIndex, int newIndex) {
    if (oldIndex < 0 || newIndex < 0 || oldIndex >= _sortedChats.length || newIndex >= _sortedChats.length) return;
    final sorted = List<Chat>.from(_sortedChats);
    final item = sorted.removeAt(oldIndex);
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    sorted.insert(insertIndex, item);
    setState(() {
      _chatOrder = sorted.map((c) => c.id).toList();
    });
    StorageService.saveChatOrder(widget.userId, _chatOrder);
  }

  Widget _buildChatTile(BuildContext context, Chat chat) {
    final scheme = Theme.of(context).colorScheme;
    final lastTime = _formatLastMessageTime(chat.lastMessageAt);
    final preview = _buildLastMessagePreview(chat);
    final unread = chat.unreadCount;
    return Dismissible(
      key: Key('chat_${chat.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: const Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      confirmDismiss: (direction) async {
        final messenger = ScaffoldMessenger.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Удалить чат?'),
            content: Text(
                'Вы уверены, что хотите удалить чат "${chat.name}"? Это действие нельзя отменить.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;
        try {
          await _chatsService.deleteChat(chat.id, widget.userId);
          return true;
        } catch (e) {
          if (kDebugMode) print('Ошибка удаления чата: $e');
          messenger.showSnackBar(
            SnackBar(
              content: Text('Ошибка при удалении чата: ${e.toString().replaceFirst('Exception: ', '')}'),
              duration: const Duration(seconds: 3),
            ),
          );
          return false;
        }
      },
      onDismissed: (direction) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        setState(() {
          _chats = _chats.where((c) => c.id != chat.id).toList();
          _chatOrder = _chatOrder.where((id) => id != chat.id).toList();
        });
        StorageService.saveChatOrder(widget.userId, _chatOrder);
        messenger.showSnackBar(
          SnackBar(content: Text('Чат "${chat.name}" удален'), duration: const Duration(seconds: 2)),
        );
        // Фоново синхронизируем список с сервером.
        Future.microtask(_loadChats);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: unread > 0
                ? scheme.primary.withValues(alpha: 0.38)
                : scheme.outline.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        color: scheme.surfaceContainerHighest.withValues(alpha: unread > 0 ? 0.58 : 0.42),
        clipBehavior: Clip.antiAlias,
        shadowColor: AppColors.primary.withValues(alpha: 0.07),
        child: InkWell(
          onTap: () => _openChat(chat),
          onLongPress: () => _showChatFolderPicker(chat),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _openChatUserProfile(chat),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: (chat.isGroup || chat.otherUserAvatarUrl == null || chat.otherUserAvatarUrl!.trim().isEmpty)
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.primary, AppColors.primaryDeep],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: chat.isGroup
                          ? const Icon(Icons.group_rounded, color: Colors.white, size: 22)
                          : (chat.otherUserAvatarUrl != null && chat.otherUserAvatarUrl!.trim().isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: chat.otherUserAvatarUrl!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => _chatAvatarPlaceholder(chat.name),
                                  errorWidget: (_, __, ___) => _chatAvatarPlaceholder(chat.name),
                                )
                              : _chatAvatarPlaceholder(chat.name),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chat.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                          color: scheme.onSurface,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((chat.folderName ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          chat.folderName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.primary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lastTime,
                      style: TextStyle(
                        fontSize: 12,
                        color: unread > 0 ? scheme.primary : scheme.onSurface.withValues(alpha: 0.50),
                        fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : unread.toString(),
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showChatFolderPicker(Chat chat) async {
    final scheme = Theme.of(context).colorScheme;
    final selectedId = (chat.folderId ?? '').trim();
    final maxH = MediaQuery.of(context).size.height * 0.6;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Переместить в папку'),
              ),
              const Divider(height: 1),
              _folderTile(ctx, scheme, 'Без папки', '__none__', selectedId.isEmpty),
              for (final f in _folders)
                _folderTile(ctx, scheme, f.name, f.id, f.id == selectedId),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.create_new_folder_rounded, color: _folders.length >= 5 ? scheme.onSurface.withValues(alpha: 0.35) : scheme.primary),
                title: Text(_folders.length >= 5 ? 'Создать папку (лимит 5)' : 'Создать папку'),
                onTap: _folders.length >= 5
                    ? null
                    : () async {
                        Navigator.pop(ctx, '__create__');
                      },
              ),
              ListTile(
                leading: Icon(Icons.settings_rounded, color: scheme.onSurface.withValues(alpha: 0.7)),
                title: const Text('Управление папками'),
                onTap: () async {
                  Navigator.pop(ctx, '__manage__');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (result == null) return;

    if (result == '__create__') {
      await _createFolderFlow();
      return;
    }
    if (result == '__manage__') {
      await _manageFoldersFlow();
      return;
    }

    final folderId = result == '__none__' ? null : result;
    final folderName = folderId == null ? null : _folders.firstWhere((f) => f.id == folderId, orElse: () => ChatFolder(id: folderId, name: '')).name;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _chatsService.setChatFolderId(chat.id, folderId: folderId);
      if (!mounted) return;
      setState(() {
        _chats = _chats
            .map((c) => c.id == chat.id
                ? Chat(
                    id: c.id,
                    name: c.name,
                    isGroup: c.isGroup,
                    folderId: folderId,
                    folderName: folderName,
                    otherUserId: c.otherUserId,
                    otherUserAvatarUrl: c.otherUserAvatarUrl,
                    lastMessageId: c.lastMessageId,
                    lastMessageText: c.lastMessageText,
                    lastMessageType: c.lastMessageType,
                    lastMessageImageUrl: c.lastMessageImageUrl,
                    lastMessageFileUrl: c.lastMessageFileUrl,
                    lastMessageFileName: c.lastMessageFileName,
                    lastMessageFileSize: c.lastMessageFileSize,
                    lastMessageFileMime: c.lastMessageFileMime,
                    lastMessageAt: c.lastMessageAt,
                    lastSenderEmail: c.lastSenderEmail,
                    unreadCount: c.unreadCount,
                  )
                : c)
            .toList();
      });
      messenger.showSnackBar(const SnackBar(content: Text('Папка обновлена')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _folderTile(BuildContext ctx, ColorScheme scheme, String label, String? value, bool selected) {
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.folder_rounded,
        color: selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.7),
      ),
      title: Text(label),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _createFolderFlow() async {
    if (!mounted) return;
    if (_folders.length >= 5) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая папка'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название папки'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _chatsService.createFolder(trimmed);
      await _loadFolders();
      messenger.showSnackBar(const SnackBar(content: Text('Папка создана')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _manageFoldersFlow() async {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.75;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              const ListTile(
                title: Text('Папки'),
                subtitle: Text('Можно создать максимум 5'),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _folders.length,
                  itemBuilder: (context, index) {
                    final f = _folders[index];
                    return ListTile(
                      leading: const Icon(Icons.folder_rounded),
                      title: Text(f.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Переименовать',
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(ctx);
                              final c = TextEditingController(text: f.name);
                              final newName = await showDialog<String>(
                                context: ctx,
                                builder: (dctx) => AlertDialog(
                                  title: const Text('Переименовать папку'),
                                  content: TextField(controller: c, autofocus: true),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Отмена')),
                                    FilledButton(onPressed: () => Navigator.pop(dctx, c.text), child: const Text('Сохранить')),
                                  ],
                                ),
                              );
                              final t = (newName ?? '').trim();
                              if (t.isEmpty) return;
                              try {
                                await _chatsService.renameFolder(f.id, t);
                                await _loadFolders();
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                                );
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            icon: Icon(Icons.delete_rounded, color: scheme.error),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(ctx);
                              final ok = await showDialog<bool>(
                                context: ctx,
                                builder: (dctx) => AlertDialog(
                                  title: const Text('Удалить папку?'),
                                  content: Text('Папка "${f.name}" будет удалена. Чаты останутся, просто без папки.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Отмена')),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(dctx, true),
                                      style: FilledButton.styleFrom(backgroundColor: scheme.error),
                                      child: const Text('Удалить'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              try {
                                await _chatsService.deleteFolder(f.id);
                                await _loadFolders();
                                if (_folderFilterId == f.id && mounted) setState(() => _folderFilterId = null);
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _folders.length >= 5 ? null : () async {
                    Navigator.pop(ctx);
                    await _createFolderFlow();
                  },
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: Text(_folders.length >= 5 ? 'Лимит 5' : 'Создать папку'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openChatUserProfile(Chat chat) {
    if (chat.isGroup) return;
    final otherId = (chat.otherUserId ?? '').trim();
    if (otherId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: otherId,
          fallbackLabel: chat.name,
        ),
      ),
    );
  }

  void _openChat(Chat chat) {
    Navigator.push(
      context,
      slideAndFadeRoute<void>(
        page: ChatScreen(
          userId: widget.userId,
          userEmail: widget.userEmail,
          displayName: _displayName,
          myAvatarUrl: _avatarUrl,
          chatId: chat.id,
          chatName: chat.name,
          isGroup: chat.isGroup,
        ),
      ),
    ).then((_) {
      // После возврата обновим список (на случай переименования/изменений)
      if (mounted) _loadChats();
    });
  }

  void _logout() {
    // Показываем диалог подтверждения
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              Navigator.pop(context); // Закрываем диалог
              await _authService.logout();
              WebSocketService.instance.disconnect();
              await PushNotificationService.clearTokenOnBackend();
              await E2eeService.clearAll();
              await LocalMessagesService.clearAll();
              await StorageService.clearUserData();
              // Возвращаемся на экран входа
              if (mounted) {
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false, // Удаляем все предыдущие маршруты
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }

  void _showMainMenu(BuildContext context, ColorScheme scheme) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menuTile(ctx, scheme, Icons.person_rounded, AppColors.primaryGlow, 'Профиль', () async {
                    Navigator.pop(ctx);
                    await _openProfile();
                  }),
                  _menuTile(ctx, scheme, Icons.school_rounded, AppColors.primary, 'Учет занятий', () async {
                    Navigator.pop(ctx);
                    await _openAccounting();
                  }),
                  _menuTile(ctx, scheme, Icons.description_rounded, AppColors.primaryGlow, 'Отчеты', () async {
                    Navigator.pop(ctx);
                    await _openReports();
                  }),
                  const Divider(height: 24),
                  _menuTile(ctx, scheme, Icons.logout_rounded, AppColors.primaryGlow, 'Выйти', () {
                    Navigator.pop(ctx);
                    _logout();
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuTile(BuildContext context, ColorScheme scheme, IconData icon, Color color, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: scheme.onSurface)),
      onTap: onTap,
    );
  }

  Future<void> _changePassword() async {
    // Показываем диалог смены пароля
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const ChangePasswordDialog();
      },
    );

    if (result == null || !mounted) {
      return;
    }

    final oldPassword = result['oldPassword'];
    final newPassword = result['newPassword'];

    if (oldPassword == null || newPassword == null || oldPassword.isEmpty || newPassword.isEmpty) {
      return;
    }

    // Показываем индикатор загрузки
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      await _authService.changePassword(widget.userId, oldPassword, newPassword);
      
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        // Показываем сообщение об успехе
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Пароль успешно изменен'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.pop(context);
      }

      if (kDebugMode) print('Ошибка смены пароля: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ошибка при смене пароля: ${e.toString().replaceFirst('Exception: ', '')}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _adminResetPassword() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Сбросить пароль пользователя'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Введите логин пользователя и новый пароль. Только администратор может сбросить пароль.',
                  style: TextStyle(fontSize: 14, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: 'Логин пользователя',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Новый пароль',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    labelText: 'Повторите пароль',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final username = usernameController.text.trim();
                final password = passwordController.text;
                final confirm = confirmController.text;
                if (username.isEmpty) return;
                if (password.length < 6) return;
                if (password != confirm) return;
                Navigator.pop(ctx, {'username': username, 'newPassword': password});
              },
              child: const Text('Сбросить пароль'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await AdminService().resetUserPassword(result['username']!, result['newPassword']!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Пароль успешно изменён'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    // Показываем диалог с вводом пароля для подтверждения
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const DeleteAccountDialog();
      },
    );

    if (password == null || password.isEmpty || !mounted) {
      return;
    }

    // Показываем финальное подтверждение
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Последнее предупреждение!'),
        content: const Text(
          'Вы действительно хотите удалить аккаунт? Это действие нельзя отменить!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Да, удалить'),
          ),
        ],
      ),
    );

    if (finalConfirmed != true || !mounted) return;

    // Показываем индикатор загрузки
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      await _authService.deleteAccount(widget.userId, password);

      WebSocketService.instance.disconnect();
      await PushNotificationService.clearTokenOnBackend();
      await E2eeService.clearAll();
      await LocalMessagesService.clearAll();
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.pop(context);
      }

      // Очищаем локальные данные
      await StorageService.clearUserData();

      if (mounted) {
        // Показываем сообщение об успехе
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аккаунт успешно удален'),
            duration: Duration(seconds: 2),
          ),
        );

        // Возвращаемся на экран входа
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.pop(context);
      }

      if (kDebugMode) print('Ошибка удаления аккаунта: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении аккаунта: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Доступ к «Учет занятий» и «Отчеты» только по списку в env на сервере (Yandex Cloud, Render и т.д.). Без имени в списке не пропускаем.
  Future<bool> _ensurePrivateAccess() async {
    final me = await _authService.fetchMe();
    final allowed = me != null && me['privateAccess'] == true;
    if (allowed) {
      await StorageService.setPrivateFeaturesUnlocked(widget.userId, true);
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Доступ к разделам «Учет занятий» и «Отчеты» только по списку. Обратитесь к администратору.',
          ),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
    return false;
  }

  Future<void> _openAccounting() async {
    if (!await _ensurePrivateAccess() || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentsScreen(userId: widget.userId, userEmail: widget.userEmail)),
    );
  }

  Future<void> _openReports() async {
    if (!await _ensurePrivateAccess() || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportsChatScreen(userId: widget.userId, userEmail: widget.userEmail, isSuperuser: widget.isSuperuser)),
    );
  }

  Future<void> _showCreateChatDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return CreateChatDialog(
          userId: widget.userId,
          chatsService: _chatsService,
        );
      },
    );

    // Обновляем список чатов только если диалог закрыт успешно (result == true)
    if (result == true && mounted) {
      // Используем SchedulerBinding для обновления после полного закрытия диалога
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadChats();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final q = _query.trim().toLowerCase();
    final sortedChats = _sortedChats;
    final folderId = (_folderFilterId ?? '').trim();
    final filteredChats = sortedChats.where((c) {
      if (folderId.isNotEmpty) {
        final cf = (c.folderId ?? '').trim();
        if (cf != folderId) return false;
      }
      if (q.isEmpty) return true;
      final name = c.name.toLowerCase();
      final preview = _buildLastMessagePreview(c).toLowerCase();
      return name.contains(q) || preview.contains(q);
    }).toList();

    final displayLabel = (_displayName ?? widget.userEmail).trim().isEmpty ? widget.userEmail : (_displayName ?? widget.userEmail);
    final initial = displayLabel.isNotEmpty ? displayLabel[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.backgroundDark,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: GestureDetector(
            onTap: _openProfile,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.35), width: 1),
                ),
                child: ClipOval(
                  child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _avatarUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _avatarInitial(initial),
                          errorWidget: (_, __, ___) => _avatarInitial(initial),
                        )
                      : _avatarInitial(initial),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          displayLabel,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: scheme.onSurface.withValues(alpha: 0.8)),
            onPressed: _loadChats,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: Icon(Icons.vpn_key_rounded, color: scheme.onSurface.withValues(alpha: 0.8)),
            onPressed: _joinByInviteDialog,
            tooltip: 'Вступить по коду',
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: scheme.primary, size: 26),
            onPressed: _showCreateChatDialog,
            tooltip: 'Создать чат',
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: scheme.onSurface.withValues(alpha: 0.8)),
            onPressed: () => _showMainMenu(context, scheme),
            tooltip: 'Меню',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.homeBodyGradient,
        ),
        child: SafeArea(
          child: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryGlow,
                    ),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Загрузка чатов...',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            )
          : _loadError != null && _chats.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.warningDark),
                        const SizedBox(height: 24),
                        Text(
                          'Не удалось загрузить чаты',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _loadError!,
                          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadChats,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('Повторить'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
          : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.glassOverlay(scheme),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.14),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.06),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            hintText: 'Поиск по чатам',
                            hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.48)),
                            prefixIcon: Icon(Icons.search_rounded, color: scheme.primary.withValues(alpha: 0.75), size: 22),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(Icons.close_rounded, color: scheme.onSurface.withValues(alpha: 0.70)),
                                    onPressed: () {
                                      setState(() {
                                        _query = '';
                                        _searchController.clear();
                                      });
                                    },
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _folderChip(scheme, 'Все', null, Icons.all_inbox_rounded),
                            for (final f in _folders) ...[
                              const SizedBox(width: 8),
                              _folderChip(scheme, f.name, f.id, Icons.folder_rounded),
                            ],
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _folders.length >= 5 ? null : _createFolderFlow,
                              icon: const Icon(Icons.add_circle_rounded),
                              tooltip: _folders.length >= 5 ? 'Лимит 5 папок' : 'Создать папку',
                            ),
                            IconButton(
                              onPressed: _manageFoldersFlow,
                              icon: const Icon(Icons.tune_rounded),
                              tooltip: 'Управление папками',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredChats.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _loadChats,
                              color: AppColors.primary,
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_chats.isEmpty)
                                            Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              size: 56,
                                              color: scheme.primary.withValues(alpha: 0.5),
                                            ),
                                          if (_chats.isEmpty) const SizedBox(height: 16),
                                          Text(
                                            _chats.isEmpty
                                                ? 'Нет чатов'
                                                : 'По запросу ничего не найдено',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          if (_chats.isEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              'Создайте чат кнопкой + или обновите список',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 20),
                                            OutlinedButton.icon(
                                              onPressed: _showCreateChatDialog,
                                              icon: const Icon(Icons.add_rounded, size: 20),
                                              label: const Text('Создать чат'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.primary,
                                              ),
                                            ),
                                          ] else ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              'Очистите поиск, чтобы увидеть все чаты',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 16),
                                            OutlinedButton.icon(
                                              onPressed: () {
                                                setState(() {
                                                  _query = '';
                                                  _searchController.clear();
                                                });
                                              },
                                              icon: const Icon(Icons.clear_all_rounded, size: 20),
                                              label: const Text('Показать все чаты'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.primary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadChats,
                              color: AppColors.primary,
                              child: _query.isEmpty
                                  ? ReorderableListView.builder(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      buildDefaultDragHandles: true,
                                      onReorder: _onReorderChats,
                                      itemCount: filteredChats.length,
                                      cacheExtent: 500,
                                      itemBuilder: (context, index) {
                                        final chat = filteredChats[index];
                                        // ReorderableListView требует key на ВЕРХНЕМ уровне элемента
                                        return RepaintBoundary(
                                          key: ValueKey('chat_tile_${chat.id}'),
                                          child: _buildChatTile(context, chat),
                                        );
                                      },
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      itemCount: filteredChats.length,
                                      cacheExtent: 500,
                                      itemBuilder: (context, index) {
                                        final chat = filteredChats[index];
                                        return RepaintBoundary(
                                          key: ValueKey('chat_tile_${chat.id}'),
                                          child: _buildChatTile(context, chat),
                                        );
                                      },
                                    ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _folderChip(ColorScheme scheme, String label, String? value, IconData icon) {
    final selected = (_folderFilterId == value) || (_folderFilterId == null && value == null);
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(icon, size: 18, color: selected ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.75)),
      selectedColor: scheme.primary,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.9),
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      onSelected: (_) => setState(() => _folderFilterId = value),
    );
  }
}
