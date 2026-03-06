import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/monthly_salary_report.dart';
import '../services/reports_service.dart';

class MonthlySalaryScreen extends StatefulWidget {
  const MonthlySalaryScreen({super.key});

  @override
  State<MonthlySalaryScreen> createState() => _MonthlySalaryScreenState();
}

class _MonthlySalaryScreenState extends State<MonthlySalaryScreen> {
  final ReportsService _reportsService = ReportsService();
  MonthlySalaryReport? _report;
  bool _isLoading = false;
  DateTime _selected = DateTime.now();
  static const Color _accent1 = AppColors.primary;
  static const Color _accent2 = AppColors.primaryGlow;

  String get _monthYearLabel =>
      '${_getMonthName(_selected.month)} ${_selected.year}';

  static String _getMonthName(int month) {
    const names = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    return names[month - 1];
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && mounted) {
      setState(() {
        _selected = DateTime(picked.year, picked.month);
        _report = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final r = await _reportsService.getMonthlySalaryReport(
        _selected.year,
        _selected.month,
      );
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatMoney(num value) {
    return NumberFormat('#,##0', 'ru_RU').format(value.round()) + ' ₽';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Зарплата за месяц',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _load,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          // Выбор месяца
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_accent1, _accent2],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Месяц',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.65),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _monthYearLabel,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurface.withValues(alpha: isDark ? 0.38 : 0.32),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading && _report == null
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                      strokeWidth: 3,
                    ),
                  )
                : _report == null
                    ? const SizedBox.shrink()
                    : _buildReportBody(context, _report!, scheme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildReportBody(
    BuildContext context,
    MonthlySalaryReport r,
    ColorScheme scheme,
    bool isDark,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Итог (зарплата за месяц)
          Card(
            elevation: 3,
            shadowColor: _accent1.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    _accent1.withValues(alpha: 0.15),
                    _accent2.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Итог:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatMoney(r.salary),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _accent1,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Доход и вычеты
          _rowCard(
            scheme,
            'Учтённый доход за месяц',
            _formatMoney(r.incomeCounted),
            subtitle: 'Поздние отчёты не входят в расчёт',
          ),
          const SizedBox(height: 10),
          _rowCard(
            scheme,
            'Сумма по поздним отчётам',
            _formatMoney(r.lateReportsAmount),
            isLate: true,
          ),
          if (r.lessonsWithoutReportAmount > 0) ...[
            const SizedBox(height: 10),
            _rowCard(
              scheme,
              'Занятия без отчёта (учтены в доходе)',
              _formatMoney(r.lessonsWithoutReportAmount),
            ),
          ],
          const SizedBox(height: 10),
          _rowCard(
            scheme,
            'Всего выручка за месяц',
            _formatMoney(r.totalAll),
          ),
          const SizedBox(height: 24),

          // Разбивка по дням
          Text(
            'По дням',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  if (r.reportBreakdown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Нет отчётов за выбранный месяц',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  else
                    ...r.reportBreakdown.map((row) {
                      final date = DateTime.tryParse(row.reportDate);
                      final dateStr = date != null
                          ? DateFormat('dd.MM.yyyy').format(date)
                          : row.reportDate;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: scheme.outline.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    dateStr,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  if (row.isLate) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'поздний',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              _formatMoney(row.amount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: row.isLate
                                    ? scheme.onSurface.withValues(alpha: 0.5)
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard(
    ColorScheme scheme,
    String title,
    String value, {
    String? subtitle,
    bool isLate = false,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface.withValues(
                        alpha: isLate ? 0.65 : 0.85,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isLate
                    ? scheme.onSurface.withValues(alpha: 0.55)
                    : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
