import 'package:flutter/material.dart';

import 'home_screen.dart';

class MainTabsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final bool isSuperuser;
  final Function(bool)? onThemeChanged;

  MainTabsScreen({required this.userId, required this.userEmail, this.isSuperuser = false, this.onThemeChanged});

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
        isSuperuser: widget.isSuperuser,
        onThemeChanged: widget.onThemeChanged,
      ),
    );
  }
}
