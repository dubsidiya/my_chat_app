import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/report.dart';
import 'report_audit_screen.dart';

/// Просмотр сгенерированного текста отчёта для копирования в параллельный учёт (тестирование).
/// Правка занятий — только через конструктор отчёта.
class ReportTextViewScreen extends StatelessWidget {
  final Report report;

  const ReportTextViewScreen({super.key, required this.report});

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: report.content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Текст скопирован в буфер'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Текст отчёта'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Журнал изменений',
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReportAuditScreen(reportId: report.id),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Копировать весь текст',
            onPressed: () => _copyAll(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            DateFormat('dd.MM.yyyy').format(report.reportDate),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'Пока приложение на тестировании, можно копировать этот текст в ваш текущий учёт. '
            'Изменить занятия и суммы можно только через «Редактировать (конструктор)».',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 20),
          SelectableText(
            report.content,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
