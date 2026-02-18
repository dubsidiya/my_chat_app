import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
import 'home_screen.dart';

class MainTabsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? avatarUrl;
  final bool isSuperuser;
  final Function(bool)? onThemeChanged;

  const MainTabsScreen({super.key, required this.userId, required this.userEmail, this.displayName, this.avatarUrl, this.isSuperuser = false, this.onThemeChanged});

  @override
  // ignore: library_private_types_in_public_api
  _MainTabsScreenState createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.sendTokenToBackendIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HomeScreen(
        userId: widget.userId,
        userEmail: widget.userEmail,
        displayName: widget.displayName,
        avatarUrl: widget.avatarUrl,
        isSuperuser: widget.isSuperuser,
        onThemeChanged: widget.onThemeChanged,
      ),
    );
  }
}
