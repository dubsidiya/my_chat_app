import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legal/app_legal.dart';
import '../theme/app_colors.dart';

/// Полноэкранный текст политики / условий / поддержки (Guideline 5.1.1).
class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String body;
  final String url;

  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.body,
    required this.url,
  });

  static Route<void> privacy() {
    return MaterialPageRoute(
      builder: (_) => const LegalDocumentScreen(
        title: AppLegal.privacyTitle,
        body: AppLegal.privacyText,
        url: AppLegal.privacyUrl,
      ),
    );
  }

  static Route<void> terms() {
    return MaterialPageRoute(
      builder: (_) => const LegalDocumentScreen(
        title: AppLegal.termsTitle,
        body: AppLegal.termsText,
        url: AppLegal.termsUrl,
      ),
    );
  }

  static Route<void> support() {
    return MaterialPageRoute(
      builder: (_) => const LegalDocumentScreen(
        title: AppLegal.supportTitle,
        body: AppLegal.supportText,
        url: AppLegal.supportUrl,
      ),
    );
  }

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Открыть в браузере',
            onPressed: _openUrl,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Text(
          body.trim(),
          style: TextStyle(
            color: scheme.onSurface,
            height: 1.5,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

/// Компактные ссылки на юридические документы (логин / регистрация).
class LegalLinks extends StatelessWidget {
  final bool includeSupport;

  const LegalLinks({super.key, this.includeSupport = false});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.onSurfaceVariantDark;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        _link(context, 'Политика конфиденциальности', LegalDocumentScreen.privacy),
        Text('·', style: TextStyle(color: color)),
        _link(context, 'Условия', LegalDocumentScreen.terms),
        if (includeSupport) ...[
          Text('·', style: TextStyle(color: color)),
          _link(context, 'Поддержка', LegalDocumentScreen.support),
        ],
      ],
    );
  }

  Widget _link(BuildContext context, String label, Route<void> Function() route) {
    return TextButton(
      onPressed: () => Navigator.of(context).push(route()),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.onSurfaceVariantDark,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}
