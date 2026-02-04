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
  bool _privateUnlocked = false;
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
      _privateUnlocked = unlocked;
      _isCheckingAccess = false;

      _screens
        ..clear()
        ..addAll([
          HomeScreen(
            userId: widget.userId,
            userEmail: widget.userEmail,
            onThemeChanged: widget.onThemeChanged,
          ),
          unlocked
              ? StudentsScreen(userId: widget.userId, userEmail: widget.userEmail)
              : _LockedTab(
                  title: 'Учет занятий',
                  subtitle: 'Раздел доступен только по коду',
                  icon: Icons.school_rounded,
                  onUnlock: _promptPrivateCode,
                ),
          unlocked
              ? ReportsChatScreen(userId: widget.userId, userEmail: widget.userEmail)
              : _LockedTab(
                  title: 'Отчеты',
                  subtitle: 'Раздел доступен только по коду',
                  icon: Icons.description_rounded,
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
            return AlertDialog(
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
                    style: TextStyle(color: Colors.grey.shade700),
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
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
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
                      color: Colors.grey.shade600,
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

    controller.dispose();

    if (code == null || code.isEmpty || !mounted) return;

    try {
      await AuthService().unlockPrivateAccess(code);
      await StorageService.setPrivateFeaturesUnlocked(widget.userId, true);
      if (!mounted) return;
      setState(() {
        _privateUnlocked = true;
      });
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
              // Чаты доступны всем. Две другие вкладки — только после кода.
              if ((index == 1 || index == 2) && !_privateUnlocked) {
                _promptPrivateCode();
                return;
              }
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
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _currentIndex == 1
                            ? _accent1.withOpacity(0.15)
                            : Colors.transparent,
                      ),
                      child: Icon(
                        Icons.school_rounded,
                        size: 24,
                      ),
                    ),
                    if (!_privateUnlocked)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
                activeIcon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
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
                        Icons.school_rounded,
                        size: 24,
                      ),
                    ),
                    if (!_privateUnlocked)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
                label: 'Учет занятий',
              ),
              BottomNavigationBarItem(
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: _currentIndex == 2
                            ? _accent1.withOpacity(0.15)
                            : Colors.transparent,
                      ),
                      child: Icon(
                        Icons.description_rounded,
                        size: 24,
                      ),
                    ),
                    if (!_privateUnlocked)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
                activeIcon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
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
                        Icons.description_rounded,
                        size: 24,
                      ),
                    ),
                    if (!_privateUnlocked)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
                label: 'Отчеты',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedTab extends StatelessWidget {
  static const Color _accent1 = Color(0xFF667eea);
  static const Color _accent2 = Color(0xFF764ba2);
  static const Color _accent3 = Color(0xFFf093fb);

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onUnlock;

  const _LockedTab({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _accent1.withOpacity(0.18),
                    _accent3.withOpacity(0.18),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 60, color: _accent1.withOpacity(0.75)),
            ),
            SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 26),
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
              child: ElevatedButton.icon(
                onPressed: onUnlock,
                icon: Icon(Icons.lock_open_rounded),
                label: Text(
                  'Ввести код доступа',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
