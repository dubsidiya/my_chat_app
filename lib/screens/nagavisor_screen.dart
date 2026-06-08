import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report.dart';
import '../models/report_audit_event.dart';
import '../models/teacher_balance.dart';
import '../models/teacher_schedule_heatmap.dart';
import '../services/admin_service.dart';
import '../services/reports_service.dart';
import '../services/teacher_balance_service.dart';
import '../theme/app_colors.dart';
import '../utils/network_error_helper.dart';
import '../widgets/teacher_balance_transaction_tile.dart';
import 'report_audit_screen.dart';
import 'report_text_view_screen.dart';

/// nagavisor1.0 — сводка по преподавателю (только суперпользователь).
class NagavisorScreen extends StatefulWidget {
  final int teacherId;
  final String teacherLabel;

  const NagavisorScreen({
    super.key,
    required this.teacherId,
    required this.teacherLabel,
  });

  @override
  State<NagavisorScreen> createState() => _NagavisorScreenState();
}

class _NagavisorScreenState extends State<NagavisorScreen> {
  final AdminService _admin = AdminService();
  final TeacherBalanceService _balanceService = TeacherBalanceService();
  final ReportsService _reportsService = ReportsService();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  bool _loading = false;
  String? _error;

  Map<String, dynamic>? _insights;
  TeacherScheduleHeatmap? _heatmap;
  TeacherBalanceSummary? _balanceSummary;
  List<TeacherBalanceTransaction> _transactions = [];
  List<Report> _reports = [];
  List<_AuditRow> _auditRows = [];

  static const List<String> _weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  String _fmtHuman(DateTime d) => DateFormat('dd.MM.yyyy').format(d);
  String _money(num v) => '${NumberFormat('#,##0', 'ru_RU').format(v.round())} ₽';

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _admin.getNagavisor(teacherId: widget.teacherId, from: _from, to: _to),
        _admin.getTeacherScheduleHeatmap(from: _from, to: _to, teacherId: widget.teacherId),
        _balanceService.getTeacherDetail(widget.teacherId, limit: 30),
        _reportsService.getAllReportsList(
          dateFrom: _from,
          dateTo: _to,
          createdBy: widget.teacherId,
        ),
      ]);

      final insights = results[0] as Map<String, dynamic>;
      final heatmap = results[1] as TeacherScheduleHeatmap;
      final balanceDetail = results[2] as ({TeacherBalanceSummary summary, List<TeacherBalanceTransaction> transactions});
      final reports = results[3] as List<Report>;

      final auditRows = await _loadRecentAudit(reports);

      if (!mounted) return;
      setState(() {
        _insights = insights;
        _heatmap = heatmap;
        _balanceSummary = balanceDetail.summary;
        _transactions = balanceDetail.transactions;
        _reports = reports;
        _auditRows = auditRows;
      });
    } catch (e) {
      if (mounted) setState(() => _error = networkErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_AuditRow>> _loadRecentAudit(List<Report> reports) async {
    final candidates = reports
        .where((r) => r.isEdited || r.isLate)
        .toList()
      ..sort((a, b) {
        final aTs = a.updatedAt ?? a.createdAt;
        final bTs = b.updatedAt ?? b.createdAt;
        return bTs.compareTo(aTs);
      });

    final top = candidates.take(6).toList();
    if (top.isEmpty && reports.isNotEmpty) {
      top.addAll(reports.take(4));
    }

    final rows = <_AuditRow>[];
    for (final report in top) {
      try {
        final events = await _reportsService.getReportAudit(report.id);
        for (final ev in events) {
          if (ev.eventType == 'report_updated' || ev.eventType == 'report_created') {
            rows.add(_AuditRow(report: report, event: ev));
          }
        }
      } catch (_) {
        /* skip broken audit fetch */
      }
    }

    rows.sort((a, b) => b.event.createdAt.compareTo(a.event.createdAt));
    return rows.take(12).toList();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = d;
      } else {
        _to = d;
      }
    });
    await _loadAll();
  }

  Color _qualityColor(int? index) {
    if (index == null) return Colors.grey;
    if (index >= 80) return Colors.green.shade700;
    if (index >= 60) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  Color _cellColor(BuildContext context, int count, int max) {
    final scheme = Theme.of(context).colorScheme;
    if (count <= 0) return scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final t = max > 0 ? (count / max).clamp(0.0, 1.0) : 1.0;
    return Color.lerp(AppColors.primary.withValues(alpha: 0.15), AppColors.primary, t)!;
  }

  Map<String, dynamic>? get _stats => _insights?['stats'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _salary => _insights?['salary'] as Map<String, dynamic>?;

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = (_insights?['teacherLabel']?.toString().trim().isNotEmpty == true)
        ? _insights!['teacherLabel'].toString()
        : widget.teacherLabel;
    final stats = _stats;
    final qualityIndex = _asInt(stats?['qualityIndex']);
    final factors = (stats?['qualityFactors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final students =
        (_insights?['students'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final lateReports = _reports.where((r) => r.isLate).length;
    final editedReports = _reports.where((r) => r.isEdited).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _insights == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Период', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _loading ? null : () => _pickDate(isFrom: true),
                                  child: Text('С ${_fmtHuman(_from)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: _loading ? null : () => _pickDate(isFrom: false),
                                  child: Text('По ${_fmtHuman(_to)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 12),
                  _SectionHeader(
                    icon: Icons.insights_rounded,
                    title: 'Индекс качества',
                    subtitle: 'Только для руководства · не виден преподавателю',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _qualityColor(qualityIndex).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _qualityColor(qualityIndex).withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  qualityIndex == null ? '—' : '$qualityIndex',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: _qualityColor(qualityIndex),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (stats?['kpiPercent'] != null)
                                      Text('КПД: ${stats!['kpiPercent']}%'),
                                    if (_asInt(stats?['openMakeupDebtCount']) != null)
                                      Text('К отработке: ${stats!['openMakeupDebtCount']}'),
                                    if (_salary != null)
                                      Text('Поздние отчёты: ${_money(_asDouble(_salary!['lateAmount']))}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (qualityIndex == null && stats?['qualityReason'] != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Недостаточно истории для оценки',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                          if (factors.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Факторы', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            ...factors.map((f) {
                              final delta = _asInt(f['delta']) ?? 0;
                              final color = delta < 0 ? Colors.red.shade700 : Colors.green.shade700;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      delta < 0 ? Icons.remove_circle_outline : Icons.add_circle_outline,
                                      size: 16,
                                      color: color,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(f['label']?.toString() ?? '')),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    icon: Icons.grid_on_rounded,
                    title: 'График работы',
                    subtitle: _heatmap != null ? '${_heatmap!.totalLessons} занятий за период' : null,
                  ),
                  if (_heatmap == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Нет данных графика'),
                      ),
                    )
                  else if (_heatmap!.timeSlots.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Нет занятий с указанным временем в периоде.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    _HeatmapGrid(
                      heatmap: _heatmap!,
                      weekdayLabels: _weekdayLabels,
                      cellColor: _cellColor,
                    ),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    icon: Icons.payments_rounded,
                    title: 'Баланс и выплаты',
                    subtitle: _balanceSummary != null ? 'Текущий баланс: ${_money(_balanceSummary!.balance)}' : null,
                  ),
                  if (_transactions.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Нет операций', style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    ..._transactions.take(8).map(
                          (tx) => TeacherBalanceTransactionTile(
                            transaction: tx,
                            formatMoney: _money,
                            onOpenReport: tx.reportId != null
                                ? (id) async {
                                    try {
                                      final report = await _reportsService.getReport(id);
                                      if (!context.mounted) return;
                                      await Navigator.push<void>(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ReportTextViewScreen(report: report),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(networkErrorMessage(e))),
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    icon: Icons.description_rounded,
                    title: 'Отчёты за период',
                    subtitle: 'Всего ${_reports.length} · поздних $lateReports · правок $editedReports',
                  ),
                  if (_reports.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Отчётов нет', style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    ..._reports.take(10).map((r) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            DateFormat('dd.MM.yyyy').format(r.reportDate.toLocal()),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              if (r.isLate) 'Поздний',
                              if (r.isEdited) 'Редактировался',
                              if (r.lessonsCount != null) '${r.lessonsCount} занятий',
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ReportTextViewScreen(report: r),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    icon: Icons.school_rounded,
                    title: 'Ученики',
                    subtitle: 'Долги и отработки',
                  ),
                  if (students.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Нет привязанных учеников', style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    ...students.take(15).map((s) {
                      final debt = _asDouble(s['debtAsOfTo']);
                      final makeup = _asInt(s['openMakeupCount']) ?? 0;
                      final unpaid = _asDouble(s['unpaidInPeriod']);
                      final debtColor = debt > 0 ? Colors.red.shade700 : Colors.green.shade700;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            s['studentName']?.toString() ?? 'Ученик',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              if (makeup > 0) 'К отработке: $makeup',
                              if (unpaid > 0) 'Неоплачено в периоде: ${_money(unpaid)}',
                            ].join(' · '),
                          ),
                          trailing: Text(
                            debt > 0 ? _money(debt) : '0 ₽',
                            style: TextStyle(fontWeight: FontWeight.bold, color: debtColor),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    icon: Icons.history_rounded,
                    title: 'Журнал правок отчётов',
                    subtitle: 'Последние события аудита',
                  ),
                  if (_auditRows.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Событий аудита нет', style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                    )
                  else
                    ..._auditRows.map((row) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            _auditEventLabel(row.event.eventType),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Отчёт #${row.report.id} · ${DateFormat('dd.MM.yyyy HH:mm').format(row.event.createdAt.toLocal())}'
                            '${row.event.userEmail != null ? '\n${row.event.userEmail}' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ReportAuditScreen(reportId: row.report.id),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  String _auditEventLabel(String type) {
    switch (type) {
      case 'report_created':
        return 'Отчёт создан';
      case 'report_updated':
        return 'Отчёт обновлён';
      default:
        return type;
    }
  }
}

class _AuditRow {
  final Report report;
  final ReportAuditEvent event;

  const _AuditRow({required this.report, required this.event});
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  final TeacherScheduleHeatmap heatmap;
  final List<String> weekdayLabels;
  final Color Function(BuildContext context, int count, int max) cellColor;

  const _HeatmapGrid({
    required this.heatmap,
    required this.weekdayLabels,
    required this.cellColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = heatmap.maxCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(7, (i) {
            final weekday = i + 1;
            final slots = heatmap.slotsForWeekday(weekday);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      weekdayLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (slots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '—',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.35)),
                        ),
                      )
                    else
                      ...slots.map((slot) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Tooltip(
                            message: '${weekdayLabels[i]} ${slot.timeSlot} — ${slot.count} занятий',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              decoration: BoxDecoration(
                                color: cellColor(context, slot.count, max),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: scheme.outline.withValues(alpha: 0.15)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    slot.timeSlot,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: slot.count >= max * 0.55
                                          ? Colors.white.withValues(alpha: 0.95)
                                          : scheme.onSurface.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${slot.count}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: slot.count >= max * 0.55 ? Colors.white : scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
