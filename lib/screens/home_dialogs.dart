import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../services/chats_service.dart';
import '../theme/app_colors.dart';
import '../utils/network_error_helper.dart';

/// Диалог создания чата (1-на-1 или группа).
class CreateChatDialog extends StatefulWidget {
  final String userId;
  final ChatsService chatsService;

  const CreateChatDialog({
    super.key,
    required this.userId,
    required this.chatsService,
  });

  @override
  State<CreateChatDialog> createState() => _CreateChatDialogState();
}

class _CreateChatDialogState extends State<CreateChatDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _searchController;
  bool _isCreating = false;
  bool _isGroup = false;
  bool _loadingUsers = false;
  List<Map<String, dynamic>> _users = [];
  final Set<String> _selectedUserIds = {};
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (!mounted) return;
    setState(() {
      _searchQuery = q;
      if (q.length < 2) {
        _users = [];
        _loadingUsers = false;
      }
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 260),
      () => _searchUsers(q),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> u) {
    final id = (u['id'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final displayName = (u['display_name'] ?? '').toString().trim();
    final selected = _selectedUserIds.contains(id);
    return ListTile(
      key: ValueKey('search-user-$id'),
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          selected ? Icons.check_rounded : Icons.person_rounded,
          size: 18,
          color: selected
              ? AppColors.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty ? email : 'Пользователь $id'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: (displayName.isNotEmpty && email.isNotEmpty)
          ? Text(email, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: _isGroup
          ? Checkbox(
              value: selected,
              onChanged: _isCreating
                  ? null
                  : (v) {
                      setState(() {
                        if (v == true) {
                          _selectedUserIds.add(id);
                        } else {
                          _selectedUserIds.remove(id);
                        }
                      });
                    },
            )
          : (selected
                ? Icon(Icons.check_circle, color: AppColors.primary)
                : null),
      onTap: _isCreating
          ? null
          : () {
              setState(() {
                if (_isGroup) {
                  if (selected) {
                    _selectedUserIds.remove(id);
                  } else {
                    _selectedUserIds.add(id);
                  }
                } else {
                  _selectedUserIds
                    ..clear()
                    ..add(id);
                }
              });
            },
    );
  }

  Future<void> _searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _users = [];
        _loadingUsers = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _loadingUsers = true);
    try {
      final users = await widget.chatsService.getAllUsers(
        widget.userId,
        query: q,
        limit: 20,
      );
      if (!mounted) return;
      if (_searchController.text.trim() != q) return;
      setState(() {
        _users = users;
        _loadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createChat() async {
    final name = _nameController.text.trim();
    if (_selectedUserIds.isEmpty) return;
    if (_isGroup && name.isEmpty) return;
    if (!_isGroup && _selectedUserIds.length != 1) return;
    if (_isGroup && _selectedUserIds.isEmpty) return;

    setState(() {
      _isCreating = true;
    });

    try {
      final selected = _selectedUserIds.toList();
      final finalName = name.isNotEmpty ? name : 'Чат 1-на-1';
      await widget.chatsService.createChat(
        finalName,
        selected,
        isGroup: _isGroup,
      );
      final warning = widget.chatsService.consumeLastCreateChatWarning();
      if (mounted && warning != null && warning.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(warning),
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
            content: Text(networkErrorMessage(e)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryGlow],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: AppColors.neonGlowSoft,
            ),
            child: const Icon(
              Icons.chat_bubble_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    key: const ValueKey('chat-mode-direct'),
                    label: const Text('1-на-1'),
                    selected: !_isGroup,
                    onSelected: _isCreating
                        ? null
                        : (_) {
                            setState(() {
                              _isGroup = false;
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
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    key: const ValueKey('chat-mode-group'),
                    label: const Text('Групповой'),
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
            const SizedBox(height: 12),
            if (_isGroup)
              TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 16),
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
            if (_isGroup) const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isGroup ? 'Участники' : 'Выберите человека',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              enabled: !_isCreating,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Поиск по email или имени...',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _isCreating
                            ? null
                            : () => _searchController.clear(),
                      ),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingUsers) const LinearProgressIndicator(minHeight: 2),
            if (_loadingUsers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_searchQuery.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Введите минимум 2 символа,\nчтобы найти пользователя',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else if (_users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Никого не найдено',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              )
            else
              SizedBox(
                height: 260,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (int i = 0; i < _users.length; i++) ...[
                        _buildUserTile(_users[i]),
                        if (i < _users.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ),
            if (_selectedUserIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedUserIds.map((id) {
                    final matched = _users
                        .where((u) => (u['id'] ?? '').toString() == id)
                        .toList();
                    final u = matched.isNotEmpty ? matched.first : null;
                    final email = (u?['email'] ?? 'id: $id').toString();
                    final displayName = (u?['display_name'] ?? '')
                        .toString()
                        .trim();
                    final label = displayName.isNotEmpty ? displayName : email;
                    return InputChip(
                      key: ValueKey('selected-user-$id'),
                      label: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: _isCreating
                          ? null
                          : () {
                              setState(() => _selectedUserIds.remove(id));
                            },
                    );
                  }).toList(),
                ),
              ),
            ],
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            'Отмена',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryGlow],
            ),
            boxShadow: AppColors.neonGlowStrong,
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
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

/// Диалог подтверждения удаления аккаунта (возвращает пароль или null).
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
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
      title: const Text('Удалить аккаунт?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Это действие необратимо! Все ваши данные будут удалены:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Все ваши сообщения'),
            const Text('• Все чаты, где вы создатель'),
            const Text('• Ваше участие во всех чатах'),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
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
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            final password = _passwordController.text.trim();
            if (password.isNotEmpty) {
              Navigator.pop(context, password);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Удалить аккаунт'),
        ),
      ],
    );
  }
}

/// Диалог смены пароля (возвращает map с oldPassword/newPassword или null).
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
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

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Новый пароль должен содержать минимум 6 символов'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_outline, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Изменить пароль'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Введите текущий пароль и новый пароль',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _oldPasswordController,
              decoration: InputDecoration(
                labelText: 'Текущий пароль',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOldPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
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
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              decoration: InputDecoration(
                labelText: 'Новый пароль',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureNewPassword = !_obscureNewPassword;
                    });
                  },
                ),
                helperText: 'Минимум 6 символов',
              ),
              obscureText: _obscureNewPassword,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              decoration: InputDecoration(
                labelText: 'Подтвердите новый пароль',
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
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
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_oldPasswordController.text.trim().isEmpty ||
                _newPasswordController.text.trim().isEmpty ||
                _confirmPasswordController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Заполните все поля'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            if (!_validatePasswords()) {
              return;
            }

            Navigator.pop(context, {
              'oldPassword': _oldPasswordController.text.trim(),
              'newPassword': _newPasswordController.text.trim(),
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
          child: const Text('Изменить'),
        ),
      ],
    );
  }
}
