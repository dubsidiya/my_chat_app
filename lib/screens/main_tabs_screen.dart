import 'dart:async';

import 'package:flutter/material.dart';
import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import '../widgets/voice_call_host.dart';

class MainTabsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? avatarUrl;
  final bool isSuperuser;

  const MainTabsScreen({super.key, required this.userId, required this.userEmail, this.displayName, this.avatarUrl, this.isSuperuser = false});

  @override
  // ignore: library_private_types_in_public_api
  _MainTabsScreenState createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PushNotificationService.requestPermissionIfNeeded());
      PushNotificationService.sendTokenToBackendIfNeeded();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: VoiceCallHost(
        userId: widget.userId,
        child: HomeScreen(
          userId: widget.userId,
          userEmail: widget.userEmail,
          displayName: widget.displayName,
          avatarUrl: widget.avatarUrl,
          isSuperuser: widget.isSuperuser,
        ),
      ),
    );
  }
}
