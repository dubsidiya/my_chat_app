import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'accounting_export_screen.dart';
import 'teacher_payroll_screen.dart';
import 'teacher_schedule_heatmap_screen.dart';
import 'teacher_schedule_overview_screen.dart';
import 'nagavisor_picker_screen.dart';

/// Раздел бухгалтерии (только суперпользователь): выплаты, график, выгрузки.
class AccountingHubScreen extends StatelessWidget {
  const AccountingHubScreen({super.key});

  static Color get _accent => AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Бухгалтерия'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Инструменты для учёта занятий и выплат преподавателям',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 16),
          _HubTile(
            icon: Icons.person_search_rounded,
            color: Colors.teal.shade700,
            title: 'Сводка по преподавателю',
            subtitle: 'Качество, график, выплаты, отчёты и ученики в одной карточке',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const NagavisorPickerScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.payments_rounded,
            color: Colors.green.shade700,
            title: 'Выплаты преподавателям',
            subtitle: 'Балансы, зарплата, аванс, премия, корректировки',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const TeacherPayrollScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.grid_on_rounded,
            color: Colors.indigo,
            title: 'График работы преподавателя',
            subtitle: 'Теплокарта занятий по дням и времени',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const TeacherScheduleHeatmapScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.compare_arrows_rounded,
            color: Colors.orange.shade800,
            title: 'Планировщик загрузки',
            subtitle: 'Куда поставить ребёнка: дни и время по каждому преподавателю',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const TeacherScheduleOverviewScreen()),
            ),
          ),
          _HubTile(
            icon: Icons.receipt_long_rounded,
            color: Colors.deepPurple,
            title: 'Выгрузка для бухгалтерии',
            subtitle: 'Сводка, долги, зарплаты за период',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const AccountingExportScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right_rounded, color: AccountingHubScreen._accent),
        onTap: onTap,
      ),
    );
  }
}
