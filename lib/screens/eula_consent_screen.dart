import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';
import '../legal/app_legal.dart';
import 'legal_document_screen.dart';
import 'login_screen.dart';
import 'main_tabs_screen.dart';

/// Экран согласия с условиями использования (Guideline 1.2 — user-generated content).
/// Пользователь должен принять условия перед доступом к чатам.
class EulaConsentScreen extends StatelessWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? avatarUrl;
  final bool isSuperuser;

  const EulaConsentScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    this.displayName,
    this.avatarUrl,
    required this.isSuperuser,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundDark,
              AppColors.surfaceDark,
              AppColors.primaryDeep,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  AppLegal.termsTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primaryGlow.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        AppLegal.termsText.trim(),
                        style: TextStyle(
                          color: scheme.onSurface,
                          height: 1.5,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).push(LegalDocumentScreen.privacy()),
                  child: const Text('Политика конфиденциальности'),
                ),
                TextButton(
                  onPressed: () async {
                    await StorageService.clearUserData();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  child: const Text('Выйти'),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDeep],
                    ),
                    boxShadow: AppColors.neonGlow,
                  ),
                  child: FilledButton(
                    onPressed: () async {
                      await StorageService.setEulaAccepted(userId);
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => MainTabsScreen(
                            userId: userId,
                            userEmail: userEmail,
                            displayName: displayName,
                            avatarUrl: avatarUrl,
                            isSuperuser: isSuperuser,
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Принимаю'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
