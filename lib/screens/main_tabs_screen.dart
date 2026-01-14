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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
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
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: Color(0xFF667eea),
            unselectedItemColor: Colors.grey.shade400,
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
                        ? Color(0xFF667eea).withOpacity(0.15)
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
                        Color(0xFF667eea).withOpacity(0.2),
                        Color(0xFF764ba2).withOpacity(0.2),
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
                        ? Color(0xFF667eea).withOpacity(0.15)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 24,
                  ),
                ),
                activeIcon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.2),
                        Color(0xFF764ba2).withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 24,
                  ),
                ),
                label: 'Учет занятий',
              ),
              BottomNavigationBarItem(
                icon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _currentIndex == 2
                        ? Color(0xFF667eea).withOpacity(0.15)
                        : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.description_rounded,
                    size: 24,
                  ),
                ),
                activeIcon: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF667eea).withOpacity(0.2),
                        Color(0xFF764ba2).withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.description_rounded,
                    size: 24,
                  ),
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

