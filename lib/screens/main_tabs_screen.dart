import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'home_screen.dart';
import 'reports_chat_screen.dart';
import 'students_screen.dart';

class MainTabsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final Function(bool)? onThemeChanged; // ✅ Callback для переключения темы

  MainTabsScreen({required this.userId, required this.userEmail, this.onThemeChanged});

  @override
  _MainTabsScreenState createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  static const Color _accent1 = Color(0xFF667eea);
  static const Color _accent2 = Color(0xFF764ba2);

  int _currentIndex = 0;
  bool _isCheckingAccess = true;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _initAccess();
  }

  Future<void> _initAccess() async {
    final unlocked = await StorageService.isPrivateFeaturesUnlocked(widget.userId);
    if (!mounted) return;

    setState(() {
      _isCheckingAccess = false;

      _screens
        ..clear()
        ..addAll([
          HomeScreen(
            userId: widget.userId,
            userEmail: widget.userEmail,
            onThemeChanged: widget.onThemeChanged,
          ),
          _MoreMenuScreen(
            userId: widget.userId,
            userEmail: widget.userEmail,
            onThemeChanged: widget.onThemeChanged,
            privateUnlocked: unlocked,
            onUnlock: _promptPrivateCode,
          ),
        ]);
    });
  }

  Future<void> _promptPrivateCode() async {
    final controller = TextEditingController();
    bool wrong = false;

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final isDark = theme.brightness == Brightness.dark;
            return AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_accent1, _accent2]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: _accent1.withOpacity(0.25),
                          blurRadius: 10,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Приватный доступ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Введите код, чтобы открыть “Учет занятий” и “Отчеты”.',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.70)),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: scheme.outline.withOpacity(isDark ? 0.22 : 0.14),
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: _accent1, width: 2),
                      ),
                    ),
                    onSubmitted: (_) {
                      final input = controller.text.trim();
                      if (input.isEmpty) {
                        setLocal(() => wrong = true);
                        return;
                      }
                      Navigator.pop(context, input);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    'Отмена',
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(colors: [_accent1, _accent2]),
                    boxShadow: [
                      BoxShadow(
                        color: _accent1.withOpacity(0.28),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      final input = controller.text.trim();
                      if (input.isEmpty) {
                        setLocal(() => wrong = true);
                        return;
                      }
                      Navigator.pop(context, input);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Открыть',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (code == null || code.isEmpty || !mounted) return;

    try {
      await AuthService().unlockPrivateAccess(code);
      await StorageService.setPrivateFeaturesUnlocked(widget.userId, true);
      if (!mounted) return;
      await _initAccess();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Приватные разделы открыты'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isCheckingAccess) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_accent1),
            strokeWidth: 3,
          ),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.10),
              blurRadius: 20,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: scheme.surface,
            selectedItemColor: _accent1,
            unselectedItemColor: scheme.onSurface.withOpacity(0.45),
            selectedLabelStyle: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
            elevation: 0,
            items: [
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _currentIndex == 0
                        ? _accent1.withOpacity(0.15)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.chat_bubble_rounded,
                    size: 24,
                  ),
                ),
                activeIcon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        _accent1.withOpacity(0.2),
                        _accent2.withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.chat_bubble_rounded,
                    size: 24,
                  ),
                ),
                label: 'Чаты',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _currentIndex == 1
                        ? _accent1.withOpacity(0.15)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 24,
                  ),
                ),
                activeIcon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        _accent1.withOpacity(0.2),
                        _accent2.withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 24,
                  ),
                ),
                label: 'Ещё',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Экран «Ещё»: разделы Учет занятий и Отчеты вынесены сюда, чтобы не бросаться в глаза в нижней панели.
class _MoreMenuScreen extends StatelessWidget {
  final String userId;
  final String userEmail;
  final Function(bool)? onThemeChanged;
  final bool privateUnlocked;
  final VoidCallback onUnlock;

  const _MoreMenuScreen({
    required this.userId,
    required this.userEmail,
    this.onThemeChanged,
    required this.privateUnlocked,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            SizedBox(height: 8),
            Text(
              'Дополнительно',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 12),
            _MenuItem(
              icon: Icons.school_rounded,
              title: 'Учет занятий',
              subtitle: 'Студенты, занятия, балансы',
              locked: !privateUnlocked,
              onTap: () async {
                if (!privateUnlocked) {
                  onUnlock();
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentsScreen(userId: userId, userEmail: userEmail),
                  ),
                );
              },
            ),
            SizedBox(height: 10),
            _MenuItem(
              icon: Icons.description_rounded,
              title: 'Отчеты',
              subtitle: 'Отчеты за день, создание занятий',
              locked: !privateUnlocked,
              onTap: () async {
                if (!privateUnlocked) {
                  onUnlock();
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportsChatScreen(userId: userId, userEmail: userEmail),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool locked;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent1 = Color(0xFF667eea);

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outline.withOpacity(isDark ? 0.18 : 0.12),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent1.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent1, size: 24),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (locked)
                Icon(Icons.lock_rounded, size: 20, color: Colors.grey.shade500)
              else
                Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withOpacity(0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

