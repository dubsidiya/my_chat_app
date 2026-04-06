import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_audit_event.dart';
import '../services/reports_service.dart';

/// Журнал событий аудита по отчёту (создание, обновление, ошибки и т.д.).
class ReportAuditScreen extends StatefulWidget {
  final int reportId;

  const ReportAuditScreen({super.key, required this.reportId});

  @override
  State<ReportAuditScreen> createState() => _ReportAuditScreenState();
}

class _ReportAuditScreenState extends State<ReportAuditScreen> {
  final ReportsService _reportsService = ReportsService();
  List<ReportAuditEvent>? _events;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _reportsService.getReportAudit(widget.reportId);
      if (mounted) setState(() => _events = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _eventLabel(String type) {
    switch (type) {
      case 'report_created':
        return 'Отчёт создан';
      case 'report_updated':
        return 'Отчёт обновлён';
      case 'report_deleted':
        return 'Отчёт удалён';
      case 'report_set_not_late':
        return 'Снята пометка «поздний»';
      case 'report_create_error':
        return 'Ошибка создания';
      case 'report_update_error':
        return 'Ошибка обновления';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Журнал отчёта #${widget.reportId}'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Повторить')),
                      ],
                    ),
                  ),
                )
              : (_events == null || _events!.isEmpty)
                  ? Center(
                      child: Text(
                        'Записей нет (или таблица аудита не развёрнута на сервере).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _events!.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final e = _events![i];
                        final when = DateFormat('dd.MM.yyyy HH:mm').format(e.createdAt.toLocal());
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _eventLabel(e.eventType),
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Text(when, style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6))),
                                  ],
                                ),
                                if (e.userEmail != null && e.userEmail!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('Пользователь: ${e.userEmail}', style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.75))),
                                ],
                                if (e.payload != null && e.payload!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    e.payload.toString(),
                                    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: scheme.onSurface.withValues(alpha: 0.65)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
