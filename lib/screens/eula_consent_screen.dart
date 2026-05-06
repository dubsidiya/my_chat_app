import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/storage_service.dart';
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

  static const String _eulaText = '''
Условия использования Reollity

Используя приложение, вы соглашаетесь с тем, что:

• В сервисе действует нулевая толерантность к оскорбительному контенту и к пользователям, нарушающим правила. Запрещены угрозы, оскорбления, спам, контент, нарушающий законы или права других пользователей.

• Вы можете пожаловаться на сообщение (кнопка «Пожаловаться») и заблокировать пользователя. Заблокированный пользователь не сможет писать вам, а его сообщения будут скрыты.

• Разработчик обязуется рассматривать жалобы и удалять нарушающий контент, а также применять меры к нарушителям (включая блокировку аккаунта) в разумные сроки.

• Администрация вправе удалять контент и приостанавливать или удалять аккаунты при нарушении правил без предварительного уведомления.

Нажимая «Принимаю», вы подтверждаете, что прочитали и согласны с этими условиями.
''';

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
                  'Условия использования',
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
                        _eulaText,
                        style: TextStyle(
                          color: scheme.onSurface,
                          height: 1.5,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
