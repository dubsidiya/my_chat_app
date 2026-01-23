import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/admin_service.dart';
import '../utils/download_text_file.dart';

class AccountingExportScreen extends StatefulWidget {
  const AccountingExportScreen({super.key});

  @override
  State<AccountingExportScreen> createState() => _AccountingExportScreenState();
}

class _AccountingExportScreenState extends State<AccountingExportScreen> {
  final AdminService _adminService = AdminService();

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _data;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtHuman(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _to = picked;
      if (_to.isBefore(_from)) _from = _to;
    });
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _data = null;
    });
    try {
      final res = await _adminService.exportAccountingJson(from: _fmt(_from), to: _fmt(_to));
      if (!mounted) return;
      setState(() => _data = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyCsv() async {
    try {
      final csv = await _adminService.exportAccountingCsv(from: _fmt(_from), to: _fmt(_to));
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV скопирован в буфер обмена'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка CSV: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadCsvFile() async {
    try {
      final csv = await _adminService.exportAccountingCsv(from: _fmt(_from), to: _fmt(_to));
      final filename = 'accounting_${_fmt(_from)}_${_fmt(_to)}.csv';

      // Web: нормальная загрузка файлом
      final okWeb = await downloadTextFile(
        filename: filename,
        content: csv,
        mimeType: 'text/csv; charset=utf-8',
      );
      if (okWeb) return;

      // Mobile/Desktop: сохраняем в documents и открываем
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);

      if (!mounted) return;
      final uri = Uri.file(file.path);
      final can = await canLaunchUrl(uri);
      if (!mounted) return;
      if (can) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV сохранен: ${file.path}'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка скачивания: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final totals = _data?['totals'] as Map<String, dynamic>?;
    final teachers = (_data?['teachers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выгрузка (бухгалтерия)'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Период', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _pickFrom,
                          icon: const Icon(Icons.date_range),
                          label: Text('С: ${_fmtHuman(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _pickTo,
                          icon: const Icon(Icons.date_range),
                          label: Text('По: ${_fmtHuman(_to)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _load,
                          icon: const Icon(Icons.playlist_add_check_rounded),
                          label: const Text('Сформировать'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _copyCsv,
                          icon: const Icon(Icons.copy),
                          label: const Text('CSV копия'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _downloadCsvFile,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('CSV файл'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Доступно только суперпользователю (нужен приватный доступ).',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          if (!_isLoading && _error != null)
            Card(
              color: Colors.red.withAlpha(20),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
              ),
            ),
          if (!_isLoading && totals != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Итого', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Занятий: ${totals['lessonsCount'] ?? 0}'),
                    Text('Сумма занятий: ${(totals['lessonsAmount'] ?? 0).toString()}'),
                    Text('Оплачено: ${(totals['paidAmount'] ?? 0).toString()}'),
                    Text('Долг: ${(totals['unpaidAmount'] ?? 0).toString()}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (!_isLoading && teachers.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('По преподавателям', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...teachers.map((t) {
                      final username = (t['teacherUsername'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(username.isEmpty ? '—' : username)),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('занятий: ${t['lessonsCount'] ?? 0}'),
                                Text('сумма: ${t['amount'] ?? 0}'),
                                Text('опл: ${t['paidAmount'] ?? 0}'),
                                Text('долг: ${t['unpaidAmount'] ?? 0}'),
                              ],
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
}

