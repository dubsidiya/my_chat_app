import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'students_screen.dart';
import 'reports_chat_screen.dart';

class MainTabsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final Function(bool)? onThemeChanged; // ✅ Callback для переключения темы

  MainTabsScreen({required this.userId, required this.userEmail, this.onThemeChanged});

  @override
  _MainTabsScreenState createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens.addAll([
      HomeScreen(userId: widget.userId, userEmail: widget.userEmail, onThemeChanged: widget.onThemeChanged),
      StudentsScreen(userId: widget.userId, userEmail: widget.userEmail),
      ReportsChatScreen(userId: widget.userId, userEmail: widget.userEmail),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Чаты',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'Учет занятий',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description),
            label: 'Отчеты',
          ),
        ],
      ),
    );
  }
}

