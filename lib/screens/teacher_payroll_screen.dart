import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/report.dart';
import '../models/teacher_balance.dart';
import '../services/reports_service.dart';
import '../services/storage_service.dart';
import '../services/teacher_balance_service.dart';
import '../theme/app_colors.dart';
import '../utils/network_error_helper.dart';
import '../widgets/teacher_balance_transaction_tile.dart';
import 'report_builder_screen.dart';
import 'nagavisor_screen.dart';

/// Управление выплатами преподавателям (только суперпользователь).
class TeacherPayrollScreen extends StatefulWidget {
  const TeacherPayrollScreen({super.key});

  @override
  State<TeacherPayrollScreen> createState() => _TeacherPayrollScreenState();
}

class _TeacherPayrollScreenState extends State<TeacherPayrollScreen> {
  final TeacherBalanceService _service = TeacherBalanceService();
  final TextEditingController _searchController = TextEditingController();

  List<TeacherBalanceListItem> _teachers = [];
  bool _loading = false;
  String? _error;
  String _query = '';
  String? _userId;
  Set<int> _hiddenTeacherIds = {};
  bool _showHidden = false;

  static final DateTime _syncFrom = DateTime(2026, 6, 1);

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final userData = await StorageService.getUserData();
    final userId = userData?['id'];
    final hidden = userId != null
        ? await StorageService.getHiddenPayrollTeacherIds(userId)
        : <int>{};
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _hiddenTeacherIds = hidden;
    });
    await _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.listTeachers();
      if (!mounted) return;
      setState(() => _teachers = list);
    } catch (e) {
      if (mounted) setState(() => _error = networkErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(num v) => '${NumberFormat('#,##0', 'ru_RU').format(v.round())} ₽';

  List<TeacherBalanceListItem> get _filtered {
    final q = _query.trim().toLowerCase();
    return _teachers.where((t) {
      final isHidden = _hiddenTeacherIds.contains(t.teacherId);
      if (_showHidden) {
        if (!isHidden) return false;
      } else if (isHidden) {
        return false;
      }
      if (q.isNotEmpty && !t.label.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  int get _hiddenCount =>
      _teachers.where((t) => _hiddenTeacherIds.contains(t.teacherId)).length;

  Future<void> _hideTeacher(TeacherBalanceListItem teacher) async {
    final uid = _userId;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось сохранить: войдите в аккаунт заново'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await StorageService.hidePayrollTeacher(uid, teacher.teacherId);
    if (!mounted) return;
    setState(() => _hiddenTeacherIds = {..._hiddenTeacherIds, teacher.teacherId});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«${teacher.label}» скрыт из списка'),
        action: SnackBarAction(
          label: 'Отмена',
          onPressed: () => _unhideTeacher(teacher, silent: true),
        ),
      ),
    );
  }

  Future<void> _unhideTeacher(TeacherBalanceListItem teacher, {bool silent = false}) async {
    final uid = _userId;
    if (uid == null) return;
    await StorageService.unhidePayrollTeacher(uid, teacher.teacherId);
    if (!mounted) return;
    setState(() => _hiddenTeacherIds = {..._hiddenTeacherIds}..remove(teacher.teacherId));
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('«${teacher.label}» снова в списке')),
      );
    }
  }

  Future<void> _syncBalances() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.syncBalances();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Начисления с отчётов синхронизированы')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openTeacher(TeacherBalanceListItem item) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _TeacherPayrollDetailScreen(
          teacherId: item.teacherId,
          teacherLabel: item.label,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выплаты преподавателям'),
        actions: [
          if (_hiddenCount > 0)
            IconButton(
              icon: Icon(_showHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              tooltip: _showHidden ? 'Скрыть скрытых преподавателей' : 'Показать скрытых ($_hiddenCount)',
              onPressed: () => setState(() => _showHidden = !_showHidden),
            ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Синхронизировать начисления',
            onPressed: _showSyncDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск преподавателя',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: _loading && _teachers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          _showHidden ? 'Скрытых преподавателей нет' : 'Преподаватели не найдены',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final t = filtered[i];
                          final color = t.balance >= 0 ? Colors.green.shade700 : Colors.red.shade700;
                          final isHidden = _hiddenTeacherIds.contains(t.teacherId);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(isHidden ? 'Скрыт · рабочий баланс' : 'Рабочий баланс'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _money(t.balance),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                      fontSize: 16,
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    icon: Icon(Icons.person_search_rounded, size: 22, color: AppColors.primary),
                                    tooltip: 'Сводка по преподавателю',
                                    onPressed: () {
                                      Navigator.push<void>(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => NagavisorScreen(
                                            teacherId: t.teacherId,
                                            teacherLabel: t.label,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    icon: Icon(
                                      isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                      size: 22,
                                    ),
                                    tooltip: isHidden ? 'Показать в списке' : 'Скрыть',
                                    onPressed: () {
                                      if (isHidden) {
                                        _unhideTeacher(t);
                                      } else {
                                        _hideTeacher(t);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => _openTeacher(t),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSyncDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Синхронизация начислений'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Пересчитать начисления 50% с отчётов и занятий без отчёта за период.',
            ),
            const SizedBox(height: 12),
            Text('С: ${DateFormat('dd.MM.yyyy').format(_syncFrom)}'),
            Text('По: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _syncBalances();
            },
            child: const Text('Синхронизировать'),
          ),
        ],
      ),
    );
  }
}

class _TeacherPayrollDetailScreen extends StatefulWidget {
  final int teacherId;
  final String teacherLabel;

  const _TeacherPayrollDetailScreen({
    required this.teacherId,
    required this.teacherLabel,
  });

  @override
  State<_TeacherPayrollDetailScreen> createState() => _TeacherPayrollDetailScreenState();
}

class _TeacherPayrollDetailScreenState extends State<_TeacherPayrollDetailScreen> {
  final TeacherBalanceService _service = TeacherBalanceService();
  final ReportsService _reportsService = ReportsService();
  double _balance = 0;
  List<TeacherBalanceTransaction> _transactions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getTeacherDetail(widget.teacherId);
      if (!mounted) return;
      setState(() {
        _balance = data.summary.balance;
        _transactions = data.transactions;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(num v) => '${NumberFormat('#,##0', 'ru_RU').format(v.round())} ₽';

  Future<void> _openReport(int reportId) async {
    try {
      final Report report = await _reportsService.getReport(reportId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReportBuilderScreen(reportId: report.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
    }
  }

  static double? _parseAmount(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _addTransaction(String type, String title) async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    type == 'adjustment' ? RegExp(r'[\d.,\-]') : RegExp(r'[\d.,]'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: type == 'adjustment' ? 'Сумма (+ или −)' : 'Сумма',
                  hintText: type == 'adjustment' ? '-5000' : '10000',
                ),
                validator: (v) {
                  final n = _parseAmount(v ?? '');
                  if (n == null || n == 0) {
                    return type == 'adjustment'
                        ? 'Укажите сумму, например -5000'
                        : 'Укажите сумму';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Комментарий'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Укажите комментарий' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final amount = _parseAmount(amountCtrl.text)!;
    final desc = descCtrl.text.trim();
    amountCtrl.dispose();
    descCtrl.dispose();

    try {
      await _service.postTransaction(
        teacherId: widget.teacherId,
        type: type,
        amount: amount,
        description: desc,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Операция сохранена')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balanceColor = _balance >= 0 ? Colors.green.shade700 : Colors.red.shade700;

    return Scaffold(
      appBar: AppBar(title: Text(widget.teacherLabel)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showActionSheet(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Операция'),
      ),
      body: _loading && _transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Баланс', style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 6),
                        Text(
                          _money(_balance),
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: balanceColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('История', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('Операций нет', style: TextStyle(color: scheme.onSurfaceVariant))),
                    )
                  else
                    ..._transactions.map(
                      (tx) => TeacherBalanceTransactionTile(
                        transaction: tx,
                        formatMoney: _money,
                        onOpenReport: (reportId) => _openReport(reportId),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _showActionSheet() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded),
              title: const Text('Выплатить зарплату'),
              onTap: () => Navigator.pop(ctx, 'salary'),
            ),
            ListTile(
              leading: const Icon(Icons.savings_rounded),
              title: const Text('Выдать аванс'),
              onTap: () => Navigator.pop(ctx, 'advance'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_events_rounded),
              title: const Text('Начислить премию'),
              onTap: () => Navigator.pop(ctx, 'premium'),
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Корректировка баланса'),
              onTap: () => Navigator.pop(ctx, 'adjustment'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final titles = {
      'salary': 'Выплата зарплаты',
      'advance': 'Выдача аванса',
      'premium': 'Премия',
      'adjustment': 'Корректировка',
    };
    await _addTransaction(type, titles[type] ?? 'Операция');
  }
}
