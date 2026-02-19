import 'package:flutter/material.dart';
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Условия использования',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
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
              const SizedBox(height: 24),
              FilledButton(
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
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Принимаю'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
