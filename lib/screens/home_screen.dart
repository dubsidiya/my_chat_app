import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/chat.dart';
import '../services/chats_service.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../services/storage_service.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'students_screen.dart';
import 'reports_chat_screen.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final bool isSuperuser;
  final Function(bool)? onThemeChanged;

  HomeScreen({required this.userId, required this.userEmail, this.isSuperuser = false, this.onThemeChanged});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatsService _chatsService = ChatsService();
  final AuthService _authService = AuthService();
  List<Chat> _chats = [];
  List<String> _chatOrder = []; // порядок чатов (id), для перетаскивания
  bool _isLoading = false;
  String? _loadError; // ошибка загрузки чатов для показа кнопки «Повторить»
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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
              try {
                await _chatsService.joinByInviteCode(code);
                if (!mounted) return;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Готово: вы вступили в чат')),
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
              title: Text('Вступить по коду'),
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
                  child: Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : doJoin,
                  child: isLoading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Вступить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
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
      final chats = await _chatsService.fetchChats(widget.userId);
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
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при загрузке чатов'),
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
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Icon(Icons.delete, color: Colors.white, size: 28),
      ),
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Удалить чат?'),
            content: Text(
                'Вы уверены, что хотите удалить чат "${chat.name}"? Это действие нельзя отменить.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Отмена')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text('Удалить'),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (direction) async {
        if (!mounted) return;
        try {
          await _chatsService.deleteChat(chat.id, widget.userId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Чат "${chat.name}" удален'), duration: const Duration(seconds: 2)),
            );
            _loadChats();
          }
        } catch (e) {
          if (kDebugMode) print('Ошибка удаления чата: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка при удалении чата: ${e.toString().replaceFirst('Exception: ', '')}'),
                duration: const Duration(seconds: 3),
              ),
            );
            _loadChats();
          }
        }
      },
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openChat(chat),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: chat.isGroup
                          ? const [Color(0xFFa855f7), Color(0xFF7c3aed)]
                          : const [Color(0xFF667eea), Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    chat.isGroup ? Icons.group_rounded : Icons.person_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                SizedBox(width: 12),
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
                      SizedBox(height: 4),
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
                SizedBox(width: 10),
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
                    SizedBox(height: 8),
                    if (unread > 0)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(999),
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
                      SizedBox(height: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: widget.userId,
          userEmail: widget.userEmail,
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
        title: Text('Выйти из аккаунта?'),
        content: Text('Вы уверены, что хотите выйти?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Закрываем диалог
              // Очищаем сохраненные данные
              await StorageService.clearUserData();
              // Возвращаемся на экран входа
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                  (route) => false, // Удаляем все предыдущие маршруты
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Выйти'),
          ),
        ],
      ),
    );
  }

  // ✅ Переключение темы
  Future<void> _toggleTheme() async {
    final currentTheme = await StorageService.getThemeMode();
    final newTheme = !currentTheme;
    await StorageService.saveThemeMode(newTheme);
    
    // Обновляем тему через callback
    if (widget.onThemeChanged != null) {
      widget.onThemeChanged!(newTheme);
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newTheme ? 'Темная тема включена' : 'Светлая тема включена'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showSettingsSheet() async {
    bool soundOn = await StorageService.getSoundOnNewMessage();
    bool vibrationOn = await StorageService.getVibrationOnNewMessage();
    final scheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Настройки',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 20),
                  SwitchListTile(
                    title: Text('Звук при новом сообщении'),
                    subtitle: Text('Воспроизводить звук, когда приходит новое сообщение'),
                    value: soundOn,
                    onChanged: (v) async {
                      await StorageService.setSoundOnNewMessage(v);
                      setModalState(() => soundOn = v);
                    },
                  ),
                  SwitchListTile(
                    title: Text('Вибрация при новом сообщении'),
                    subtitle: Text('Вибрация при получении нового сообщения'),
                    value: vibrationOn,
                    onChanged: (v) async {
                      await StorageService.setVibrationOnNewMessage(v);
                      setModalState(() => vibrationOn = v);
                    },
                  ),
                  SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _changePassword() async {
    // Показываем диалог смены пароля
    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _ChangePasswordDialog();
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
        builder: (context) => Center(
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
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Пароль успешно изменен'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
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
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
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
          title: Text('Сбросить пароль пользователя'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Введите логин пользователя и новый пароль. Только администратор может сбросить пароль.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: 'Логин пользователя',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  autofocus: true,
                ),
                SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Новый пароль',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  decoration: InputDecoration(
                    labelText: 'Повторите пароль',
                    prefixIcon: Icon(Icons.lock_outline),
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
              child: Text('Отмена'),
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
              child: Text('Сбросить пароль'),
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
        SnackBar(
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
        return _DeleteAccountDialog();
      },
    );

    if (password == null || password.isEmpty || !mounted) {
      return;
    }

    // Показываем финальное подтверждение
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Последнее предупреждение!'),
        content: Text(
          'Вы действительно хотите удалить аккаунт? Это действие нельзя отменить!',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Да, удалить'),
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
        builder: (context) => Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      await _authService.deleteAccount(widget.userId, password);
      
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.pop(context);
      }

      // Очищаем локальные данные
      await StorageService.clearUserData();

      if (mounted) {
        // Показываем сообщение об успехе
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Аккаунт успешно удален'),
            duration: const Duration(seconds: 2),
          ),
        );

        // Возвращаемся на экран входа
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
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

  static const Color _privateAccent1 = Color(0xFF667eea);
  static const Color _privateAccent2 = Color(0xFF764ba2);

  /// Запрос кода доступа для разделов Учет занятий / Отчеты. Возвращает true, если разблокировано.
  Future<bool> _promptPrivateCode() async {
    final controller = TextEditingController();
    bool wrong = false;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_privateAccent1, _privateAccent2]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Приватный доступ', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Введите код, чтобы открыть “Учет занятий” и “Отчеты”.',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.70)),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Код доступа',
                      errorText: wrong ? 'Неверный код' : null,
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: scheme.outline.withValues(alpha: isDark ? 0.22 : 0.14), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: _privateAccent1, width: 2),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (controller.text.trim().isEmpty) {
                        setLocal(() => wrong = true);
                        return;
                      }
                      Navigator.pop(ctx, controller.text.trim());
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text('Отмена')),
                ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isEmpty) {
                      setLocal(() => wrong = true);
                      return;
                    }
                    Navigator.pop(ctx, controller.text.trim());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _privateAccent1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Открыть'),
                ),
              ],
            );
          },
        );
      },
    );

    if (code == null || code.isEmpty || !mounted) return false;
    try {
      await _authService.unlockPrivateAccess(code);
      await StorageService.setPrivateFeaturesUnlocked(widget.userId, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Приватные разделы открыты'), duration: Duration(seconds: 2), backgroundColor: Colors.green.shade600),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), duration: Duration(seconds: 3), backgroundColor: Colors.red.shade600),
        );
      }
      return false;
    }
  }

  Future<void> _openAccounting() async {
    final unlocked = await StorageService.isPrivateFeaturesUnlocked(widget.userId);
    if (!unlocked) {
      final ok = await _promptPrivateCode();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentsScreen(userId: widget.userId, userEmail: widget.userEmail)),
    );
  }

  Future<void> _openReports() async {
    final unlocked = await StorageService.isPrivateFeaturesUnlocked(widget.userId);
    if (!unlocked) {
      final ok = await _promptPrivateCode();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportsChatScreen(userId: widget.userId, userEmail: widget.userEmail)),
    );
  }

  Future<void> _showCreateChatDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _CreateChatDialog(
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
    final isDark = theme.brightness == Brightness.dark;

    final q = _query.trim().toLowerCase();
    final sortedChats = _sortedChats;
    final filteredChats = sortedChats.where((c) {
      if (q.isEmpty) return true;
      final name = c.name.toLowerCase();
      final preview = _buildLastMessagePreview(c).toLowerCase();
      return name.contains(q) || preview.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: scheme.surface,
        title: Text(
          widget.userEmail.isNotEmpty ? widget.userEmail : 'Мои чаты',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Color(0xFF667eea).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: Color(0xFF667eea)),
              onPressed: _loadChats,
              tooltip: 'Обновить',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.vpn_key_rounded, color: Colors.green.shade700),
              onPressed: _joinByInviteDialog,
              tooltip: 'Вступить по коду',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea),
                  Color(0xFF764ba2),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF667eea).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.add_rounded, color: Colors.white),
              onPressed: _showCreateChatDialog,
              tooltip: 'Создать чат',
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: scheme.onSurface.withValues(alpha: 0.75)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 8,
            onSelected: (value) async {
              if (value == 'accounting') {
                await _openAccounting();
              } else if (value == 'reports') {
                await _openReports();
              } else if (value == 'settings') {
                await _showSettingsSheet();
              } else if (value == 'theme') {
                _toggleTheme();
              } else if (value == 'logout') {
                _logout();
              } else if (value == 'change_password') {
                await _changePassword();
              } else if (value == 'admin_reset_password') {
                await _adminResetPassword();
              } else if (value == 'delete_account') {
                await _deleteAccount();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'accounting',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFF667eea).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.school_rounded, color: Color(0xFF667eea), size: 20),
                    ),
                    SizedBox(width: 12),
                    Text('Учет занятий', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'reports',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFF764ba2).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.description_rounded, color: Color(0xFF764ba2), size: 20),
                    ),
                    SizedBox(width: 12),
                    Text('Отчеты', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.settings_rounded, color: Colors.amber.shade700, size: 20),
                    ),
                    SizedBox(width: 12),
                    Text('Настройки', style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'theme',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        color: scheme.primary,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      isDark ? 'Тёмная тема ✓' : 'Светлая тема ✓',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.logout_rounded,
                          color: Colors.blue, size: 20),
                    ),
                    SizedBox(width: 12),
                    Text('Выйти',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'change_password',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.lock_outline_rounded,
                          color: Colors.orange, size: 20),
                    ),
                    SizedBox(width: 12),
                    Text('Изменить пароль',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              if (widget.isSuperuser)
                PopupMenuItem<String>(
                  value: 'admin_reset_password',
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.admin_panel_settings_rounded, color: Colors.teal, size: 20),
                      ),
                      SizedBox(width: 12),
                      Text('Сбросить пароль пользователя',
                          style: TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              PopupMenuItem<String>(
                value: 'delete_account',
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.delete_forever_rounded,
                          color: Colors.red, size: 20),
                    ),
                    SizedBox(width: 12),
                    Text('Удалить аккаунт',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF667eea),
                    ),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Загрузка чатов...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
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
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 64, color: Colors.orange.shade400),
                        SizedBox(height: 24),
                        Text(
                          'Не удалось загрузить чаты',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          _loadError!,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loadChats,
                          icon: Icon(Icons.refresh_rounded, size: 20),
                          label: Text('Повторить'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
          : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: isDark ? 0.18 : 0.12),
                            width: 1.2,
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'Поиск по чатам',
                            hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
                            prefixIcon: Icon(Icons.search_rounded, color: scheme.primary),
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
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredChats.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _loadChats,
                              color: Color(0xFF667eea),
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
                                              color: Color(0xFF667eea).withValues(alpha: 0.5),
                                            ),
                                          if (_chats.isEmpty) const SizedBox(height: 16),
                                          Text(
                                            _chats.isEmpty
                                                ? 'Нет чатов'
                                                : 'По запросу ничего не найдено',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey.shade600,
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
                                                color: Colors.grey.shade500,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 20),
                                            OutlinedButton.icon(
                                              onPressed: _showCreateChatDialog,
                                              icon: const Icon(Icons.add_rounded, size: 20),
                                              label: const Text('Создать чат'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Color(0xFF667eea),
                                              ),
                                            ),
                                          ] else ...[
                                            const SizedBox(height: 12),
                                            Text(
                                              'Очистите поиск, чтобы увидеть все чаты',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey.shade500,
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
                                                foregroundColor: Color(0xFF667eea),
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
                              color: Color(0xFF667eea),
                              child: _query.isEmpty
                                  ? ReorderableListView.builder(
                                      padding: EdgeInsets.symmetric(vertical: 8),
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
                                      padding: EdgeInsets.symmetric(vertical: 8),
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
    );
  }
}

// Отдельный виджет для диалога создания чата
class _CreateChatDialog extends StatefulWidget {
  final String userId;
  final ChatsService chatsService;

  const _CreateChatDialog({
    required this.userId,
    required this.chatsService,
  });

  @override
  State<_CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<_CreateChatDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _searchController;
  bool _isCreating = false;
  bool _isGroup = false;
  bool _loadingUsers = true;
  List<Map<String, dynamic>> _users = [];
  final Set<String> _selectedUserIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _searchController = TextEditingController();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await widget.chatsService.getAllUsers(widget.userId);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _users.where((u) {
      final email = (u['email'] ?? '').toString().toLowerCase();
      final id = (u['id'] ?? '').toString().toLowerCase();
      return email.contains(q) || id.contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createChat() async {
    final name = _nameController.text.trim();
    if (_selectedUserIds.isEmpty) return;
    if (_isGroup && name.isEmpty) return;
    if (!_isGroup && _selectedUserIds.length != 1) return;
    if (_isGroup && _selectedUserIds.length < 1) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final selected = _selectedUserIds.toList();
      final finalName = name.isNotEmpty ? name : 'Чат 1-на-1';
      await widget.chatsService.createChat(finalName, selected, isGroup: _isGroup);
      
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка создания чата: $e');
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при создании чата: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF667eea),
                  Color(0xFF764ba2),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 24),
          ),
          SizedBox(width: 12),
          Text(
            'Создать чат',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      content: Container(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Text('1-на-1'),
                    selected: !_isGroup,
                    onSelected: _isCreating
                        ? null
                        : (_) {
                            setState(() {
                              _isGroup = false;
                              // оставляем только одного выбранного
                              if (_selectedUserIds.length > 1) {
                                final first = _selectedUserIds.first;
                                _selectedUserIds
                                  ..clear()
                                  ..add(first);
                              }
                            });
                          },
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Text('Групповой'),
                    selected: _isGroup,
                    onSelected: _isCreating
                        ? null
                        : (_) {
                            setState(() {
                              _isGroup = true;
                            });
                          },
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (_isGroup)
              TextField(
                controller: _nameController,
                style: TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Имя группы',
                  filled: true,
                  fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                enabled: !_isCreating,
              ),
            if (_isGroup) SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isGroup ? 'Участники' : 'Выберите человека',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              enabled: !_loadingUsers && !_isCreating,
              style: TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Поиск по email или имени...',
                prefixIcon: Icon(Icons.search_rounded, size: 22, color: Color(0xFF667eea)),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            SizedBox(height: 10),
            if (_loadingUsers)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_users.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Нет пользователей для добавления'),
              )
            else if (_searchQuery.trim().isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Введите запрос в поле поиска,\nчтобы найти пользователя',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else if (_filteredUsers.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Никого не найдено',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, i) {
                    final u = _filteredUsers[i];
                    final id = (u['id'] ?? '').toString();
                    final email = (u['email'] ?? '').toString();
                    final selected = _selectedUserIds.contains(id);
                    return CheckboxListTile(
                      dense: true,
                      value: selected,
                      onChanged: _isCreating
                          ? null
                          : (v) {
                              setState(() {
                                if (_isGroup) {
                                  if (v == true) {
                                    _selectedUserIds.add(id);
                                  } else {
                                    _selectedUserIds.remove(id);
                                  }
                                } else {
                                  _selectedUserIds
                                    ..clear()
                                    ..add(id);
                                }
                              });
                            },
                      title: Text(email.isNotEmpty ? email : 'Пользователь $id'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating
              ? null
              : () {
                  Navigator.pop(context, false);
                },
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            'Отмена',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                Color(0xFF667eea),
                Color(0xFF764ba2),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF667eea).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isCreating
                ? null
                : () {
                    final name = _nameController.text.trim();
                    if (_selectedUserIds.isEmpty) return;
                    if (_isGroup && name.isEmpty) return;
                    if (!_isGroup && _selectedUserIds.length != 1) return;
                    _createChat();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isCreating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Создать',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// Диалог для удаления аккаунта
class _DeleteAccountDialog extends StatefulWidget {
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Удалить аккаунт?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Это действие необратимо! Все ваши данные будут удалены:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Все ваши сообщения'),
            Text('• Все чаты, где вы создатель'),
            Text('• Ваше участие во всех чатах'),
            SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Введите пароль для подтверждения',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context, null);
          },
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            final password = _passwordController.text.trim();
            if (password.isNotEmpty) {
              Navigator.pop(context, password);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: Text('Удалить аккаунт'),
        ),
      ],
    );
  }
}

// Диалог для смены пароля
class _ChangePasswordDialog extends StatefulWidget {
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  late final TextEditingController _oldPasswordController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _confirmPasswordController;
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _oldPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _validatePasswords() {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    
    if (newPassword.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Новый пароль должен содержать минимум 4 символа'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Пароли не совпадают'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.blue.shade700),
          SizedBox(width: 8),
          Text('Изменить пароль'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Введите текущий пароль и новый пароль',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _oldPasswordController,
              decoration: InputDecoration(
                labelText: 'Текущий пароль',
                prefixIcon: Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOldPassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureOldPassword = !_obscureOldPassword;
                    });
                  },
                ),
              ),
              obscureText: _obscureOldPassword,
              autofocus: true,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              decoration: InputDecoration(
                labelText: 'Новый пароль',
                prefixIcon: Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureNewPassword = !_obscureNewPassword;
                    });
                  },
                ),
                helperText: 'Минимум 4 символа',
              ),
              obscureText: _obscureNewPassword,
            ),
            SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              decoration: InputDecoration(
                labelText: 'Подтвердите новый пароль',
                prefixIcon: Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
              obscureText: _obscureConfirmPassword,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context, null);
          },
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_oldPasswordController.text.trim().isEmpty ||
                _newPasswordController.text.trim().isEmpty ||
                _confirmPasswordController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Заполните все поля'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            
            if (!_validatePasswords()) {
              return;
            }
            
            Navigator.pop(
              context,
              {
                'oldPassword': _oldPasswordController.text.trim(),
                'newPassword': _newPasswordController.text.trim(),
              },
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
          ),
          child: Text('Изменить'),
        ),
      ],
    );
  }
}
