import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chats_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  HomeScreen({required this.userId, required this.userEmail});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatsService _chatsService = ChatsService();
  final AuthService _authService = AuthService();
  List<Chat> _chats = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    print('HomeScreen initialized with userId: ${widget.userId}, userEmail: ${widget.userEmail}');
    _loadChats();
  }

  Future<void> _loadChats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final chats = await _chatsService.fetchChats(widget.userId);
      print('Loaded ${chats.length} chats');
      if (mounted) {
        setState(() {
          _chats = chats;
        });
      }
    } catch (e) {
      print('Error loading chats: $e');
      if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при загрузке чатов: $e')),
      );
      }
    } finally {
      if (mounted) {
      setState(() => _isLoading = false);
      }
    }
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
        ),
      ),
    );
  }

  Future<void> _deleteChat(Chat chat) async {
    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить чат?'),
        content: Text('Вы уверены, что хотите удалить чат "${chat.name}"? Это действие нельзя отменить.'),
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
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _chatsService.deleteChat(chat.id, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чат "${chat.name}" удален'),
            duration: const Duration(seconds: 2),
          ),
        );
        // Обновляем список чатов
                  _loadChats();
      }
    } catch (e) {
      print('Ошибка удаления чата: $e');
      if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении чата: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
                  );
                }
    }
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

      print('Ошибка удаления аккаунта: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.userEmail.isNotEmpty ? widget.userEmail : 'Мои чаты',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadChats,
            tooltip: 'Обновить',
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showCreateChatDialog,
            tooltip: 'Создать чат',
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                _logout();
              } else if (value == 'delete_account') {
                await _deleteAccount();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Выйти'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete_account',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Удалить аккаунт', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Загрузка чатов...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: Colors.grey.shade300,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Нет доступных чатов',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Создайте новый чат, нажав на кнопку +',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
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
              // Показываем диалог подтверждения
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Удалить чат?'),
                  content: Text('Вы уверены, что хотите удалить чат "${chat.name}"? Это действие нельзя отменить.'),
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
                      child: Text('Удалить'),
                    ),
                  ],
                ),
              );
              return confirmed ?? false;
            },
            onDismissed: (direction) async {
              // Удаляем чат после подтверждения
              if (!mounted) return;
              try {
                await _chatsService.deleteChat(chat.id, widget.userId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Чат "${chat.name}" удален'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  // Обновляем список чатов
                  _loadChats();
                }
              } catch (e) {
                print('Ошибка удаления чата: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка при удалении чата: ${e.toString().replaceFirst('Exception: ', '')}'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  // Восстанавливаем список, так как удаление не удалось
                  _loadChats();
                }
              }
            },
                      child: Card(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _openChat(chat),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Аватар
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: chat.isGroup
                                          ? [Colors.purple.shade400, Colors.purple.shade600]
                                          : [Colors.blue.shade400, Colors.blue.shade600],
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (chat.isGroup ? Colors.purple : Colors.blue)
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    chat.isGroup ? Icons.group : Icons.person,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                SizedBox(width: 16),
                                // Название чата
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        chat.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade900,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            chat.isGroup ? Icons.group : Icons.person,
                                            size: 14,
                                            color: Colors.grey.shade500,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            chat.isGroup ? 'Групповой чат' : 'Личный чат',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Кнопка удаления
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.grey.shade400),
                                  onPressed: () => _deleteChat(chat),
                                  tooltip: 'Удалить чат',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
        },
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
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createChat() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isCreating = true;
    });

    try {
      await widget.chatsService.createChat(name, [widget.userId]);
      
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Ошибка создания чата: $e');
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
      title: Text('Создать чат'),
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(labelText: 'Имя чата'),
        autofocus: true,
        enabled: !_isCreating,
      ),
      actions: [
        TextButton(
          onPressed: _isCreating
              ? null
              : () {
                  Navigator.pop(context, false);
                },
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createChat,
          child: _isCreating
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Создать'),
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
