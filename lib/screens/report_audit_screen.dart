import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_audit_event.dart';
import '../services/reports_service.dart';
import '../utils/date_parse.dart';

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
  String? _serverMessage;
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
      final result = await _reportsService.getReportAudit(widget.reportId);
      if (mounted) {
        setState(() {
          _events = result.events;
          _serverMessage = result.serverMessage;
        });
      }
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

  /// Русские подписи известных ключей payload аудита (см. reportsController.js).
  static const Map<String, String> _payloadLabels = {
    'reportDate': 'Дата отчёта',
    'report_date': 'Дата отчёта',
    'lessonsCreated': 'Создано занятий',
    'lessonsDeleted': 'Удалено занятий',
    'timezone': 'Часовой пояс',
    'has_slots': 'Структурный формат',
    'code': 'Код ошибки БД',
    'constraint': 'Ограничение БД',
    'detail': 'Детали',
    'where': 'Контекст',
  };

  static String _formatPayloadValue(String key, dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'Да' : 'Нет';
    final lower = key.toLowerCase();
    if (lower.contains('date')) {
      try {
        return DateFormat('dd.MM.yyyy').format(parseCalendarDate(value));
      } catch (_) {
        return value.toString();
      }
    }
    if (lower.contains('amount') ||
        lower.contains('price') ||
        lower.contains('sum') ||
        lower.contains('balance')) {
      final n = value is num ? value.toDouble() : double.tryParse(value.toString());
      if (n != null) {
        final s = n == n.roundToDouble()
            ? n.toStringAsFixed(0)
            : n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
        return '$s ₽';
      }
    }
    return value.toString();
  }

  Widget _payloadRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.75)),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildPayload(BuildContext context, Map<String, dynamic> payload) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    final unknown = <String, dynamic>{};
    payload.forEach((key, value) {
      final label = _payloadLabels[key];
      if (label == null) {
        unknown[key] = value;
        return;
      }
      rows.add(_payloadRow(context, label, _formatPayloadValue(key, value)));
    });
    // Неизвестные ключи оставляем сырым дампом, чтобы ничего не потерять.
    if (unknown.isNotEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          unknown.toString(),
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: scheme.onSurface.withValues(alpha: 0.55)),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
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
                        _serverMessage?.isNotEmpty == true
                            ? _serverMessage!
                            : 'Записей нет (или таблица аудита не развёрнута на сервере).',
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
                        final when = e.hasCreatedAt
                            ? DateFormat('dd.MM.yyyy HH:mm')
                                .format(serverInstantToLocal(e.createdAt))
                            : 'время неизвестно';
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
                                  _buildPayload(context, e.payload!),
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
