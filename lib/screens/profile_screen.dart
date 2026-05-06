import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_variant.dart';
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
          const SnackBar(duration: Duration(seconds: 3), content: Text('Аватар обновлён'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAvatar = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
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
          const SnackBar(duration: Duration(seconds: 3), content: Text('Имя сохранено'), behavior: SnackBarBehavior.floating),
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
                          color: scheme.surface.withValues(alpha: 0.75),
                          child: Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
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
            _sectionTitle(context, 'Внешний вид'),
            _themeTile(context),
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
              titleColor: scheme.error,
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
      decoration: BoxDecoration(
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

  /// Карточка переключения темы. Показывает текущую тему и при тапе открывает
  /// bottom-sheet с выбором всех доступных вариантов.
  Widget _themeTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final variant = ThemeController.instance.variant;
    final iconColor = scheme.primary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            variant.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: iconColor,
            size: 22,
          ),
        ),
        title: Text(
          'Тема оформления',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: scheme.onSurface,
          ),
        ),
        subtitle: Text(
          variant.displayName,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openThemePicker(context),
      ),
    );
  }

  Future<void> _openThemePicker(BuildContext context) async {
    final selected = ThemeController.instance.variant;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showModalBottomSheet<AppThemeVariant>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    'Выберите тему',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                  child: Text(
                    'Цветовая палитра применяется ко всему приложению — кнопкам, фонам, '
                    'диалогам и пузырям сообщений.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                for (final v in AppThemeVariant.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _ThemeOptionCard(
                      variant: v,
                      selected: v == selected,
                      onTap: () => Navigator.of(ctx).pop(v),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || picked == null || picked == selected) return;
    await ThemeController.instance.setVariant(picked);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text('Тема обновлена: ${picked.displayName}'),
        behavior: SnackBarBehavior.floating,
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

/// Превью одного варианта темы в bottom-sheet.
///
/// Отрисовывает ту же градиентную «pill»-карточку независимо от текущей темы:
/// цвета берутся из жёстко заданных пар, а не из глобального [AppColors],
/// чтобы пользователь мог сравнивать темы рядом, до фактического переключения.
class _ThemeOptionCard extends StatelessWidget {
  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  /// Превью: тёмная тема — фиолетовое неоновое свечение,
  /// светлая — мягкие пастельные сиреневые тона.
  List<Color> get _previewColors {
    switch (variant) {
      case AppThemeVariant.ultravioletDark:
        return const [
          Color(0xFF1a0a2e),
          Color(0xFF7B2CBF),
          Color(0xFFC77DFF),
        ];
      case AppThemeVariant.auroraLight:
        return const [
          Color(0xFFFBFAFD),
          Color(0xFFE2D6F8),
          Color(0xFF7B4FCB),
        ];
    }
  }

  Color get _accentColor {
    switch (variant) {
      case AppThemeVariant.ultravioletDark:
        return const Color(0xFFC77DFF);
      case AppThemeVariant.auroraLight:
        return const Color(0xFF7B4FCB);
    }
  }

  Color get _onAccentColor {
    switch (variant) {
      case AppThemeVariant.ultravioletDark:
        return Colors.white;
      case AppThemeVariant.auroraLight:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? _accentColor
        : scheme.outline.withValues(alpha: 0.3);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
          child: Row(
            children: [
              // Превью-«плитка» с градиентом темы
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _previewColors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    variant.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: _onAccentColor,
                    size: 28,
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
                      variant.displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      variant.description,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? Container(
                        key: const ValueKey('selected'),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('unselected'),
                        width: 30,
                        height: 30,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
