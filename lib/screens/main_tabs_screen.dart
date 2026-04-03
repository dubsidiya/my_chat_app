import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/push_notification_service.dart';
import '../services/version_check_service.dart';
import '../theme/app_colors.dart';
import '../utils/reload_util.dart';
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
  VersionCheckInfo? _versionCheckInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.sendTokenToBackendIfNeeded();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = await VersionCheckService.check();
      if (!mounted) return;
      setState(() => _versionCheckInfo = info);
      await VersionCheckService.showDialogIfNeeded(context, info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final showUpdateBanner = kIsWeb &&
        _versionCheckInfo != null &&
        _versionCheckInfo!.result != VersionCheckResult.upToDate;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          if (showUpdateBanner) _buildUpdateBanner(context),
          Expanded(
            child: HomeScreen(
              userId: widget.userId,
              userEmail: widget.userEmail,
              displayName: widget.displayName,
              avatarUrl: widget.avatarUrl,
              isSuperuser: widget.isSuperuser,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateBanner(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.95),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  VersionCheckService.webUpdateBannerText,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => reloadPage(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Обновить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
