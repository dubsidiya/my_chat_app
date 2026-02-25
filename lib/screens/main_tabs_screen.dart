import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
import 'home_screen.dart';

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
      PushNotificationService.sendTokenToBackendIfNeeded();
    });
    // Проверка версии приложения отключена, пока приложение не в App Store / Play Market.
    // Когда будете публиковать — см. docs/VERSION_CHECK.md и раскомментируйте вызов ниже.
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   final info = await VersionCheckService.check();
    //   if (!mounted) return;
    //   await VersionCheckService.showDialogIfNeeded(context, info);
    // });
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
      ),
    );
  }
}
