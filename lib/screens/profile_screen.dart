import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../utils/read_file_bytes.dart';

/// Экран профиля в стиле Telegram: аватар, имя, настройки.
class ProfileScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? avatarUrl;
  final bool isSuperuser;
  final Function(bool)? onThemeChanged;
  final VoidCallback? onProfileUpdated;
  final VoidCallback? onChangePassword;
  final VoidCallback? onAdminResetPassword;
  final VoidCallback? onDeleteAccount;
  final VoidCallback? onLogout;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    this.displayName,
    this.avatarUrl,
    this.isSuperuser = false,
    this.onThemeChanged,
    this.onProfileUpdated,
    this.onChangePassword,
    this.onAdminResetPassword,
    this.onDeleteAccount,
    this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  late String? _displayName;
  late String? _avatarUrl;
  bool _isLoadingAvatar = false;
  bool _isSavingName = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
    _avatarUrl = widget.avatarUrl;
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayName != widget.displayName) _displayName = widget.displayName;
    if (oldWidget.avatarUrl != widget.avatarUrl) _avatarUrl = widget.avatarUrl;
  }

  String get _displayLabel => (_displayName ?? widget.userEmail).trim().isEmpty ? widget.userEmail : (_displayName ?? widget.userEmail);
  String get _initial => _displayLabel.isNotEmpty ? _displayLabel[0].toUpperCase() : '?';

  Future<void> _pickAndUploadAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      List<int> bytes;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        bytes = file.bytes!;
      } else if (file.path != null && file.path!.isNotEmpty) {
        bytes = await readFileBytesFromPath(file.path!);
      } else {
        return;
      }
      final name = file.name.isEmpty ? 'avatar.jpg' : file.name;
      if (!mounted) return;
      setState(() => _isLoadingAvatar = true);
      final url = await _authService.uploadAvatarBytes(bytes, name);
      if (mounted) {
        setState(() {
          _avatarUrl = url;
          _isLoadingAvatar = false;
        });
        widget.onProfileUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватар обновлён'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString().replaceFirst('Exception: ', '')}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя профиля'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Как к вам обращаться',
          ),
          maxLength: 255,
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _isSavingName = true);
    try {
      await _authService.updateProfile(result);
      if (mounted) {
        setState(() {
          _displayName = result.isEmpty ? null : result;
          _isSavingName = false;
        });
        widget.onProfileUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Имя сохранено'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingName = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: ${e.toString().replaceFirst('Exception: ', '')}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _refreshFromServer() async {
    final me = await _authService.fetchMe();
    if (me == null || !mounted) return;
    setState(() {
      _displayName = me['displayName']?.toString();
      _avatarUrl = me['avatarUrl'] ?? me['avatar_url']?.toString();
    });
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
      await StorageService.setAvatarUrl(_avatarUrl);
    }
    widget.onProfileUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoadingAvatar ? null : _refreshFromServer,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Аватар
            GestureDetector(
              onTap: _isLoadingAvatar ? null : _pickAndUploadAvatar,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: AppColors.neonGlowSoft,
                      border: Border.all(
                        color: AppColors.primaryGlow.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _avatarUrl!,
                              fit: BoxFit.cover,
                              width: 120,
                              height: 120,
                              placeholder: (_, __) => _avatarPlaceholder(),
                              errorWidget: (_, __, ___) => _avatarPlaceholder(),
                            )
                          : _avatarPlaceholder(),
                    ),
                  ),
                  if (_isLoadingAvatar)
                    Positioned.fill(
                      child: ClipOval(
                        child: Container(
                          color: Colors.black54,
                          child: const Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: AppColors.neonGlowSoft,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите, чтобы сменить фото',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            // Имя
            InkWell(
              onTap: _isSavingName ? null : _editDisplayName,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _displayLabel,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!_isSavingName) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.edit_rounded, size: 20, color: scheme.primary),
                    ],
                  ],
                ),
              ),
            ),
            Text(
              widget.userEmail,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            // Блоки настроек
            _sectionTitle(context, 'Настройки'),
            _listTile(
              context,
              icon: Icons.notifications_active_rounded,
              title: 'Звук при новом сообщении',
              trailing: FutureBuilder<bool>(
                future: StorageService.getSoundOnNewMessage(),
                builder: (_, snap) {
                  final on = snap.data ?? true;
                  return Switch(
                    value: on,
                    onChanged: (v) async {
                      await StorageService.setSoundOnNewMessage(v);
                      if (mounted) setState(() {});
                    },
                  );
                },
              ),
            ),
            _listTile(
              context,
              icon: Icons.vibration_rounded,
              title: 'Вибрация при новом сообщении',
              trailing: FutureBuilder<bool>(
                future: StorageService.getVibrationOnNewMessage(),
                builder: (_, snap) {
                  final on = snap.data ?? true;
                  return Switch(
                    value: on,
                    onChanged: (v) async {
                      await StorageService.setVibrationOnNewMessage(v);
                      if (mounted) setState(() {});
                    },
                  );
                },
              ),
            ),
            _sectionTitle(context, 'Внешний вид'),
            _listTile(
              context,
              icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              title: isDark ? 'Тёмная тема ✓' : 'Светлая тема ✓',
              onTap: () async {
                final current = await StorageService.getThemeMode();
                final next = !current;
                await StorageService.saveThemeMode(next);
                widget.onThemeChanged?.call(next);
                if (mounted) setState(() {});
              },
            ),
            _sectionTitle(context, 'Аккаунт'),
            _listTile(
              context,
              icon: Icons.lock_reset_rounded,
              title: 'Изменить пароль',
              onTap: () => _openChangePassword(context),
            ),
            if (widget.isSuperuser)
              _listTile(
                context,
                icon: Icons.admin_panel_settings_rounded,
                title: 'Сбросить пароль пользователя',
                onTap: () => _openAdminResetPassword(context),
              ),
            _listTile(
              context,
              icon: Icons.delete_forever_rounded,
              title: 'Удалить аккаунт',
              titleColor: Colors.red,
              onTap: () => _openDeleteAccount(context),
            ),
            _listTile(
              context,
              icon: Icons.logout_rounded,
              title: 'Выйти',
              onTap: () => _logout(context),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
      width: 120,
      height: 120,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDeep],
        ),
      ),
      child: Center(
        child: Text(
          _initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _listTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (titleColor ?? scheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: titleColor ?? scheme.primary, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: titleColor ?? scheme.onSurface,
          ),
        ),
        trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
        onTap: onTap,
      ),
    );
  }

  void _openChangePassword(BuildContext context) {
    Navigator.pop(context);
    widget.onChangePassword?.call();
  }

  void _openAdminResetPassword(BuildContext context) {
    Navigator.pop(context);
    widget.onAdminResetPassword?.call();
  }

  void _openDeleteAccount(BuildContext context) {
    Navigator.pop(context);
    widget.onDeleteAccount?.call();
  }

  void _logout(BuildContext context) {
    Navigator.pop(context);
    widget.onLogout?.call();
  }
}
