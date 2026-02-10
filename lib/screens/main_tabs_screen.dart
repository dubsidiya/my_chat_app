import 'package:flutter/material.dart';

import 'home_screen.dart';

class MainTabsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final Function(bool)? onThemeChanged; // ✅ Callback для переключения темы

  MainTabsScreen({required this.userId, required this.userEmail, this.onThemeChanged});

  @override
  _MainTabsScreenState createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HomeScreen(
        userId: widget.userId,
        userEmail: widget.userEmail,
        onThemeChanged: widget.onThemeChanged,
      ),
    );
  }
}
