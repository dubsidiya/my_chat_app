import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../services/admin_service.dart';
import '../services/students_service.dart';
import '../models/student.dart';
import '../models/transaction.dart';
import '../utils/download_text_file.dart';
import 'bank_statement_screen.dart';
import 'deposit_screen.dart';

class AccountingExportScreen extends StatefulWidget {
  const AccountingExportScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  State<AccountingExportScreen> createState() => _AccountingExportScreenState();
}

class _AccountingExportScreenState extends State<AccountingExportScreen> {
  final AdminService _adminService = AdminService();
  final StudentsService _studentsService = StudentsService();

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _data;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  String _query = '';
  bool _onlyDebts = false;

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtHuman(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  String _norm(String s) => s.toLowerCase().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _money0(dynamic v) => _asDouble(v).toStringAsFixed(0);

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _teacherHeader({
    required String teacherName,
    required int studentsCount,
    required int lessonsCount,
    required int unpaidCount,
    required double unpaidSum,
  }) {
    const accent1 = AppColors.primary;
    const accent2 = AppColors.primaryGlow;
    final debtColor = Colors.red.shade700;
    final okColor = Colors.green.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent1.withAlpha(36), accent2.withAlpha(36)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent1.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryGlow]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: accent1.withAlpha(50),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _initials(teacherName.isEmpty ? '—' : teacherName),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacherName.isEmpty ? '—' : teacherName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(icon: Icons.group_rounded, label: 'детей: $studentsCount', color: accent2),
                    _chip(icon: Icons.event_note_rounded, label: 'занятий: $lessonsCount', color: accent1),
                    _chip(
                      icon: unpaidCount > 0 ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                      label: unpaidCount > 0 ? 'долг: $unpaidCount • ₽${unpaidSum.toStringAsFixed(0)}' : 'всё оплачено',
                      color: unpaidCount > 0 ? debtColor : okColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lessonTile(Map<String, dynamic> l) {
    final scheme = Theme.of(context).colorScheme;
    final date = (l['lessonDate'] ?? '').toString();
    final time = (l['lessonTime'] ?? '').toString();
    final price = _money0(l['price']);
    final paid = _money0(l['paidAmount']);
    final unpaid = _money0(l['unpaidAmount']);
    final isPaid = l['isPaid'] == true;
    final color = isPaid ? Colors.green.shade700 : Colors.red.shade700;
    final bg = isPaid ? Colors.green.withAlpha(16) : Colors.red.withAlpha(16);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [date, if (time.isNotEmpty) time].join(' '),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'цена: ₽$price • опл: ₽$paid • долг: ₽$unpaid',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha:0.75)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isPaid ? 'Оплачено' : 'Долг',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }

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

  Future<void> _copyCsvBankTransfer() async {
    try {
      final csv = await _adminService.exportAccountingCsv(
        from: _fmt(_from),
        to: _fmt(_to),
        bankTransferOnly: true,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выписка по расчётному счёту скопирована в буфер'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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

  Future<void> _downloadCsvFileBankTransfer() async {
    try {
      final csv = await _adminService.exportAccountingCsv(
        from: _fmt(_from),
        to: _fmt(_to),
        bankTransferOnly: true,
      );
      final filename = 'accounting_${_fmt(_from)}_${_fmt(_to)}_raschetnyi_schet.csv';

      final okWeb = await downloadTextFile(
        filename: filename,
        content: csv,
        mimeType: 'text/csv; charset=utf-8',
      );
      if (okWeb) return;

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
        SnackBar(
          content: Text('Выписка по расчётному счёту сохранена: ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _copyTransactionsCsv() async {
    try {
      final csv = await _adminService.exportTransactionsCsv(from: _fmt(_from), to: _fmt(_to));
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV транзакций скопирован в буфер'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка CSV транзакций: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _copyTransactionsCsvBankTransfer() async {
    try {
      final csv = await _adminService.exportTransactionsCsv(
        from: _fmt(_from),
        to: _fmt(_to),
        bankTransferOnly: true,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV транзакций (расч. счёт) скопирован в буфер'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadTransactionsCsvFile({required bool bankTransferOnly}) async {
    try {
      final csv = await _adminService.exportTransactionsCsv(
        from: _fmt(_from),
        to: _fmt(_to),
        bankTransferOnly: bankTransferOnly,
      );
      final suffix = bankTransferOnly ? '_raschetnyi_schet' : '';
      final filename = 'transactions_${_fmt(_from)}_${_fmt(_to)}$suffix.csv';

      final okWeb = await downloadTextFile(
        filename: filename,
        content: csv,
        mimeType: 'text/csv; charset=utf-8',
      );
      if (okWeb) return;

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

  Future<Student?> _pickStudentForDeposit() async {
    try {
      final students = await _studentsService.getAllStudents();
      if (!mounted) return null;

      if (students.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет учеников для пополнения'), backgroundColor: Colors.orange),
        );
        return null;
      }

      return await showModalBottomSheet<Student>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final searchController = TextEditingController();
          String query = '';

          return StatefulBuilder(
            builder: (context, setLocal) {
              final q = _norm(query);
              final filtered = students.where((s) {
                if (q.isEmpty) return true;
                return _norm(s.name).contains(q) ||
                    (s.phone != null && _norm(s.phone!).contains(q)) ||
                    (s.email != null && _norm(s.email!).contains(q));
              }).toList();

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Выберите ученика',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          onChanged: (v) => setLocal(() => query = v),
                          decoration: InputDecoration(
                            hintText: 'Поиск по имени / телефону / email',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () => setLocal(() {
                                      query = '';
                                      searchController.clear();
                                    }),
                                  ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'Ничего не найдено',
                                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final s = filtered[i];
                                  return ListTile(
                                    leading: const Icon(Icons.person_rounded),
                                    title: Text(s.name),
                                    subtitle: Text(
                                      [
                                        if (s.phone != null && s.phone!.isNotEmpty) s.phone!,
                                        if (s.email != null && s.email!.isNotEmpty) s.email!,
                                      ].join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => Navigator.pop(ctx, s),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки учеников: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _openDepositFromAccounting() async {
    final student = await _pickStudentForDeposit();
    if (student == null || !mounted) return;

    final tx = await Navigator.push<Transaction?>(
      context,
      MaterialPageRoute(builder: (_) => DepositScreen(studentId: student.id)),
    );

    if (tx != null && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Пополнение выполнено: ${student.name}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 15),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () async {
              try {
                await _studentsService.deleteTransaction(tx.id);
                if (!mounted) return;
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Пополнение отменено'), backgroundColor: Colors.orange),
                );
                await _load();
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Не удалось отменить: $e'), backgroundColor: Colors.red),
                );
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _openBankStatementFromAccounting() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BankStatementScreen()),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Платежи применены'), backgroundColor: Colors.green),
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totals = _data?['totals'] as Map<String, dynamic>?;
    final teachers = (_data?['teachers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final tree = (_data?['tree'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final debug = _data?['debug'] as Map<String, dynamic>?;

    final q = _norm(_query);

    // Фильтрация дерева: поиск по преподавателю/ребенку, и опционально только долги
    final filteredTree = tree
        .map((t) {
          final teacherName = (t['teacherUsername'] ?? '').toString();
          final studentsRaw = (t['students'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

          final studentsFiltered = studentsRaw
              .map((s) {
                final studentName = (s['studentName'] ?? '').toString();
                final lessonsRaw = (s['lessons'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

                final lessonsFiltered = lessonsRaw.where((l) {
                  final isPaid = l['isPaid'] == true;
                  if (_onlyDebts && isPaid) return false;
                  return true;
                }).toList();

                // Поиск: если есть query — оставляем либо совпало имя ученика,
                // либо совпало имя преподавателя (тогда оставляем всех его учеников),
                // либо совпало что-то в строке занятия (дата/время).
                final hayTeacher = _norm(teacherName);
                final hayStudent = _norm(studentName);
                final teacherMatches = q.isEmpty ? true : hayTeacher.contains(q);
                final studentMatches = q.isEmpty ? true : hayStudent.contains(q);
                final lessonMatches = q.isEmpty
                    ? true
                    : lessonsFiltered.any((l) {
                        final date = (l['lessonDate'] ?? '').toString();
                        final time = (l['lessonTime'] ?? '').toString();
                        return _norm('$date $time').contains(q);
                      });

                if (q.isNotEmpty && !(teacherMatches || studentMatches || lessonMatches)) {
                  return null;
                }

                if (lessonsFiltered.isEmpty) return null;

                return {
                  ...s,
                  'lessons': lessonsFiltered,
                };
              })
              .whereType<Map<String, dynamic>>()
              .toList();

          if (studentsFiltered.isEmpty) return null;

          // Если query задан и совпал только преподаватель — оставим всех его детей (уже есть)
          return {
            ...t,
            'students': studentsFiltered,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    final isSuperuserDenied = (_error ?? '').contains('Требуется доступ суперпользователя') ||
        (_error ?? '').contains('HTTP 403');

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
                  const Text('Бухгалтерия', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (isSuperuserDenied)
                    Text(
                      'Недостаточно прав. Этот раздел доступен только суперпользователю.',
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _openDepositFromAccounting,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            label: const Text('Пополнить баланс'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openBankStatementFromAccounting,
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Загрузить выписку'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Пополнение баланса и выписки доступны только здесь.',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha:0.65)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Период', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Поиск (преподаватель / ребенок / дата)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _onlyDebts,
                    onChanged: _isLoading ? null : (v) => setState(() => _onlyDebts = v),
                    title: const Text('Показывать только долги'),
                  ),
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
                  const SizedBox(height: 10),
                  const Text(
                    'Выписка только по ученикам с оплатой на расчётный счёт:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _copyCsvBankTransfer,
                          icon: const Icon(Icons.account_balance_rounded),
                          label: const Text('Копия (расч. счёт)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _downloadCsvFileBankTransfer,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Скачать выписку'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Divider(height: 20),
                  const Text(
                    'Экспорт транзакций за период (по операциям):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _copyTransactionsCsv,
                          icon: const Icon(Icons.copy),
                          label: const Text('Транзакции (копия)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _downloadTransactionsCsvFile(bankTransferOnly: false),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Транзакции (файл)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _copyTransactionsCsvBankTransfer,
                          icon: const Icon(Icons.account_balance_rounded),
                          label: const Text('Транзакции (расч. счёт)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _downloadTransactionsCsvFile(bankTransferOnly: true),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Скачать (расч. счёт)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Доступно только суперпользователю.',
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
              color: Colors.red.withValues(alpha:isDark ? 0.16 : 0.10),
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
                    if ((totals['lessonsCount'] ?? 0) == 0) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'В выбранном периоде занятий не найдено. Попробуй выбрать более широкий период.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      if (debug != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'debug: lessonsUpToTo=${debug['lessonsUpToTo']}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (!_isLoading && filteredTree.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Преподаватель → дети → занятия',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ...filteredTree.map((t) {
                      final teacherName = (t['teacherUsername'] ?? '').toString();
                      final students = (t['students'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

                      final lessonsCount = students.fold<int>(
                        0,
                        (acc, s) => acc + ((s['lessons'] as List?)?.length ?? 0),
                      );
                      int unpaidCount = 0;
                      double unpaidSum = 0;
                      for (final s in students) {
                        final lessons = (s['lessons'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                        for (final l in lessons) {
                          if (l['isPaid'] == true) continue;
                          unpaidCount += 1;
                          unpaidSum += _asDouble(l['unpaidAmount']);
                        }
                      }

                      return ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(top: 10),
                        title: _teacherHeader(
                          teacherName: teacherName,
                          studentsCount: students.length,
                          lessonsCount: lessonsCount,
                          unpaidCount: unpaidCount,
                          unpaidSum: unpaidSum,
                        ),
                        subtitle: const SizedBox.shrink(),
                        children: [
                          ...students.map((s) {
                            final studentName = (s['studentName'] ?? '').toString();
                            final lessons = (s['lessons'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                            final unpaidCount = lessons.where((x) => x['isPaid'] != true).length;
                            final unpaidSum = lessons.fold<double>(
                              0,
                              (acc, x) => acc + _asDouble(x['unpaidAmount']),
                            );
                            final overallDebt = _asDouble(s['overallDebtAsOfTo']);
                            final overallPrepaid = _asDouble(s['overallPrepaidAsOfTo']);
                            return ExpansionTile(
                              tilePadding: const EdgeInsets.only(left: 4, right: 4),
                              childrenPadding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: (unpaidCount > 0 ? Colors.red : Colors.green).withAlpha(18),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: (unpaidCount > 0 ? Colors.red : Colors.green).withAlpha(40),
                                  ),
                                ),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: unpaidCount > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                ),
                              ),
                              title: Text(
                                studentName.isEmpty ? '—' : studentName,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _chip(
                                      icon: Icons.event_note_rounded,
                                      label: 'занятий: ${lessons.length}',
                                      color: AppColors.primary,
                                    ),
                                    _chip(
                                      icon: unpaidCount > 0 ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                                      label: unpaidCount > 0 ? 'долг: $unpaidCount • ₽${unpaidSum.toStringAsFixed(0)}' : 'всё оплачено',
                                      color: unpaidCount > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                    ),
                                    if (overallDebt > 0)
                                      _chip(
                                        icon: Icons.account_balance_wallet_rounded,
                                        label: 'общий долг: ₽${overallDebt.toStringAsFixed(0)}',
                                        color: Colors.red.shade700,
                                      )
                                    else if (overallPrepaid > 0)
                                      _chip(
                                        icon: Icons.account_balance_wallet_rounded,
                                        label: 'предоплата: ₽${overallPrepaid.toStringAsFixed(0)}',
                                        color: Colors.green.shade700,
                                      ),
                                  ],
                                ),
                              ),
                              children: [
                                ...lessons.map(_lessonTile),
                              ],
                            );
                          }),
                        ],
                      );
                    }),
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

