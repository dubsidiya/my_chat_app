import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import 'photo_viewer_screen.dart';

/// Просмотр профиля другого пользователя (read-only).
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String? fallbackLabel; // например senderEmail, если сервер ещё грузится

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.fallbackLabel,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final AuthService _authService = AuthService();
  bool _loading = true;
  String? _error;

  String? _username;
  String? _displayName;
  String? _avatarUrl;

  String get _label {
    final a = (_displayName ?? '').trim();
    if (a.isNotEmpty) return a;
    final b = (_username ?? '').trim();
    if (b.isNotEmpty) return b;
    final c = (widget.fallbackLabel ?? '').trim();
    if (c.isNotEmpty) return c;
    return 'Профиль';
  }

  String get _initial {
    final s = _label.trim();
    return s.isNotEmpty ? s[0].toUpperCase() : '?';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _authService.fetchUserById(widget.userId);
      if (!mounted) return;
      setState(() {
        _username = (data['username'] ?? data['email'])?.toString();
        _displayName = data['displayName']?.toString();
        _avatarUrl = (data['avatarUrl'] ?? data['avatar_url'])?.toString();
        if (_avatarUrl != null && _avatarUrl!.trim().isEmpty) _avatarUrl = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(_label, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGlow),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, color: scheme.error, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.85)),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: (_avatarUrl != null && _avatarUrl!.trim().isNotEmpty)
                            ? () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PhotoViewerScreen(
                                      imageUrl: _avatarUrl!,
                                      title: _label,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: AppColors.neonGlowSoft,
                            border: Border.all(
                              color: AppColors.primaryGlow.withValues(alpha: 0.6),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: _avatarUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => _avatarPlaceholder(),
                                    errorWidget: (_, __, ___) => _avatarPlaceholder(),
                                  )
                                : _avatarPlaceholder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      if ((_username ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _username!,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.person_rounded, color: scheme.primary),
                            ),
                            title: const Text('Профиль'),
                            subtitle: Text(
                              'Просмотр профиля пользователя',
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.75)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(
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
            fontSize: 46,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

