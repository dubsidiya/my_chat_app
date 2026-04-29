import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../models/lesson.dart';
import '../models/transaction.dart';
import '../services/students_service.dart';
import '../services/reports_service.dart';
import '../services/storage_service.dart';
import 'edit_student_screen.dart';
import 'report_text_view_screen.dart';

class StudentDetailScreen extends StatefulWidget {
  final Student student;

  const StudentDetailScreen({super.key, required this.student});

  @override
  // ignore: library_private_types_in_public_api
  _StudentDetailScreenState createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> with SingleTickerProviderStateMixin {
  final StudentsService _studentsService = StudentsService();
  final ReportsService _reportsService = ReportsService();
  late Student _student;
  List<Lesson> _lessons = [];
  List<Transaction> _transactions = [];
  double _balance = 0;
  bool _isLoading = false;
  bool _showAllAccountingData = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    _balance = _student.balance;
    _tabController = TabController(length: 2, vsync: this);
    _initViewerModeAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initViewerModeAndLoad() async {
    final userData = await StorageService.getUserData();
    _showAllAccountingData = userData?['isSuperuser'] == 'true';
    await _loadData();
  }

  Future<List<Lesson>> _loadLessons() {
    return _showAllAccountingData
        ? _studentsService.getStudentLessons(_student.id)
        : _studentsService.getStudentLessonsMine(_student.id);
  }

  Future<List<Transaction>> _loadTransactions() {
    return _showAllAccountingData
        ? _studentsService.getStudentTransactions(_student.id)
        : _studentsService.getStudentTransactionsMine(_student.id);
  }

  Future<double> _loadBalance() {
    return _showAllAccountingData
        ? _studentsService.getStudentBalance(_student.id)
        : _studentsService.getStudentBalanceMine(_student.id);
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final lessons = await _loadLessons();
      final transactions = await _loadTransactions();
      await _updateBalance();
      if (mounted) {
        setState(() {
          _lessons = lessons;
          _transactions = transactions;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка загрузки данных: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Обновление данных без показа индикатора загрузки
  Future<void> _refreshData() async {
    if (!mounted) return;
    try {
      final lessons = await _loadLessons();
      final transactions = await _loadTransactions();
      await _updateBalance();
      if (mounted) {
        setState(() {
          _lessons = lessons;
          _transactions = transactions;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка обновления данных: $e');
    }
  }

  void _editStudent() async {
    final updated = await Navigator.push<Student>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStudentScreen(student: _student),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _student = updated;
      });
      _updateBalance();
    }
  }

  Future<void> _updateBalance() async {
    try {
      final updatedBalance = await _loadBalance();
      if (mounted) {
        setState(() {
          _balance = updatedBalance;
        });
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка обновления баланса: $e');
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'missed':
        return 'Пропуск';
      case 'makeup':
        return 'Отработка';
      case 'cancel_same_day':
        return 'Отмена в день';
      default:
        return 'Проведено';
    }
  }

  Future<void> _cancelDeposit(Transaction tx) async {
    if (!_showAllAccountingData) return; // только суперпользователь
    if (tx.type != 'deposit') return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить пополнение?'),
        content: Text(
          'Отменить пополнение на ${tx.amount.toStringAsFixed(0)} ₽?\n\n'
          'Это удалит транзакцию пополнения из учёта.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _studentsService.deleteTransaction(tx.id);
      await _refreshData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Пополнение отменено'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Не удалось отменить: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteStudent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить связь с учеником?'),
        content: Text(
          'Вы уверены, что хотите удалить "${_student.name}"?\n\n'
          'Это действие удалит вашу связь с учеником.\n'
          'Данные ученика останутся в системе.\n\n'
          'Это действие можно выполнить только для вашей учетной записи.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить связь'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _studentsService.deleteStudent(_student.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ученик "${_student.name}" удален'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Возвращаемся назад с результатом
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteStudentFully() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить ученика полностью?'),
        content: Text(
          'Ученик "${_student.name}" будет удален полностью из базы.\n\n'
          'Будут удалены все занятия и транзакции по этому ученику.\n'
          'Действие необратимо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить полностью', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _studentsService.deleteStudentFull(_student.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ученик "${_student.name}" удален полностью'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка полного удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteLesson(Lesson lesson) async {
    final fromReport = lesson.isFromDailyReport;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить занятие?'),
        content: Text(
          fromReport
              ? 'Занятие привязано к дневному отчёту №${lesson.linkedReportId}. '
                  'Удаление уберёт его из учёта. Суммы в отчёте лучше править через «Отчёты» → конструктор.\n\n'
                  'Продолжить удаление?'
              : 'Это действие нельзя отменить',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          if (fromReport && lesson.linkedReportId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
                _openReportView(lesson.linkedReportId!);
              },
              child: const Text('Открыть отчёт'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _studentsService.deleteLesson(lesson.id);
      // Быстрое обновление данных после удаления занятия
      await _refreshData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openReportView(int reportId) async {
    try {
      final report = await _reportsService.getReport(reportId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReportTextViewScreen(report: report),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Не удалось открыть отчёт: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebtor = _balance < 0;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final makeupPending = _lessons
            .where((l) => l.status == 'missed' || l.status == 'cancel_same_day')
            .length -
        _lessons.where((l) => l.status == 'makeup').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_student.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editStudent,
            tooltip: 'Редактировать',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              if (_showAllAccountingData) {
                final action = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.link_off_rounded),
                          title: const Text('Удалить связь'),
                          subtitle: const Text('Только отвязать от текущего пользователя'),
                          onTap: () => Navigator.pop(context, 'unlink'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                          title: const Text('Удалить полностью', style: TextStyle(color: Colors.red)),
                          subtitle: const Text('Только суперпользователь'),
                          onTap: () => Navigator.pop(context, 'full'),
                        ),
                      ],
                    ),
                  ),
                );
                if (action == 'full') {
                  await _deleteStudentFully();
                } else if (action == 'unlink') {
                  await _deleteStudent();
                }
              } else {
                await _deleteStudent();
              }
            },
            tooltip: 'Удаление ученика',
          ),
        ],
      ),
      body: Column(
        children: [
          // Карточка с балансом
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDebtor
                  ? Colors.red.withValues(alpha:isDark ? 0.14 : 0.10)
                  : Colors.green.withValues(alpha:isDark ? 0.14 : 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDebtor ? Colors.red : Colors.green).withValues(alpha:isDark ? 0.55 : 0.65),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Баланс',
                  style: TextStyle(
                    fontSize: 16,
                    color: scheme.onSurface.withValues(alpha:0.70),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_balance.toStringAsFixed(0)} ₽',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDebtor
                        ? Colors.red.shade400
                        : _balance > 0
                            ? Colors.green.shade500
                            : scheme.onSurface.withValues(alpha: 0.70),
                  ),
                ),
                if (isDebtor)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Долг',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red.shade400,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Информация о студенте
          if (_student.parentName != null ||
              _student.phone != null ||
              _student.email != null ||
              true)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_student.parentName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline, size: 16),
                          const SizedBox(width: 8),
                          Text('Родитель: ${_student.parentName}'),
                        ],
                      ),
                    ),
                  if (_student.phone != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.phone, size: 16),
                          const SizedBox(width: 8),
                          Text(_student.phone!),
                        ],
                      ),
                    ),
                  if (_student.email != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.email, size: 16),
                          const SizedBox(width: 8),
                          Text(_student.email!),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          _student.payByBankTransfer ? Icons.account_balance : Icons.payments,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _student.payByBankTransfer ? 'Платит на расчётный счёт' : 'Платит наличными',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface.withValues(alpha:0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Табы для занятий и транзакций
          Expanded(
            child: Column(
              children: [
                if (_lessons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Chip(
                          label: Text('К отработке: ${makeupPending < 0 ? 0 : makeupPending}'),
                          avatar: const Icon(Icons.replay_rounded, size: 16),
                        ),
                      ],
                    ),
                  ),
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: 'Занятия (${_lessons.length})'),
                    Tab(text: 'Транзакции (${_transactions.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Вкладка занятий
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Material(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Занятия из дневного отчёта помечены и правятся через «Отчёты» → конструктор. '
                                        'Точечные занятия здесь — вне отчёта.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.35,
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _lessons.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_busy, size: 56, color: scheme.onSurface.withValues(alpha: 0.35)),
                              const SizedBox(height: 12),
                              Text('Нет занятий', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.70))),
                            ],
                          ),
                        ),
                      )
                              : RefreshIndicator(
                                  onRefresh: _refreshData,
                                  child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _lessons.length,
                        itemBuilder: (context, index) {
                          final lesson = _lessons[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              isThreeLine: lesson.isFromDailyReport,
                              leading: const Icon(Icons.event),
                              onTap: lesson.linkedReportId != null
                                  ? () {
                                      _openReportView(lesson.linkedReportId!);
                                    }
                                  : null,
                              title: Text(
                                DateFormat('dd.MM.yyyy')
                                    .format(lesson.lessonDate),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Преподаватель: ${((lesson.teacherUsername ?? '').trim().isNotEmpty) ? lesson.teacherUsername!.trim() : 'ID ${lesson.createdBy ?? '—'}'}',
                                  ),
                                  Text(
                                    [
                                      if (lesson.lessonTime != null) 'Время: ${lesson.lessonTime}',
                                      _statusLabel(lesson.status),
                                    ].join(' · '),
                                  ),
                                  if (lesson.isFromDailyReport && lesson.linkedReportId != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Отчёт №${lesson.linkedReportId}'
                                        '${lesson.linkedReportDate != null ? ' · ${DateFormat('dd.MM.yyyy').format(lesson.linkedReportDate!)}' : ''} · нажмите, чтобы открыть',
                                        style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${lesson.price.toStringAsFixed(0)} ₽',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteLesson(lesson),
                                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                    padding: EdgeInsets.zero,
                                    tooltip: 'Удалить',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                                  ),
                                ),
                          ),
                        ],
                      ),
                      // Вкладка транзакций
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _transactions.isEmpty
                              ? RefreshIndicator(
                                  onRefresh: _refreshData,
                                  child: SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    child: SizedBox(
                                      height: MediaQuery.of(context).size.height * 0.5,
                                      child: Center(
                                        child: Text(
                                          'Нет транзакций',
                                          style: TextStyle(color: scheme.onSurface.withValues(alpha:0.55)),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _refreshData,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: _transactions.length,
                                    itemBuilder: (context, index) {
                                    final transaction = _transactions[index];
                                    final isDeposit = transaction.type == 'deposit';
                                    final isLesson = transaction.type == 'lesson';
                                    
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        isThreeLine: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: Icon(
                                          isDeposit 
                                              ? Icons.add_circle 
                                              : isLesson 
                                                  ? Icons.event 
                                                  : Icons.undo,
                                          color: isDeposit 
                                              ? Colors.green 
                                              : isLesson 
                                                  ? Colors.blue 
                                                  : Colors.orange,
                                        ),
                                        title: Text(
                                          isDeposit 
                                              ? 'Пополнение баланса'
                                              : isLesson 
                                                  ? 'Занятие'
                                                  : 'Возврат',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (isDeposit && transaction.depositTypeLabel.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4, bottom: 2),
                                                child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: transaction.isBankDeposit
                                                      ? (isDark ? Colors.blue.withValues(alpha: 0.14) : Colors.blue.shade50)
                                                      : (isDark ? Colors.orange.withValues(alpha: 0.14) : Colors.orange.shade50),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: transaction.isBankDeposit 
                                                        ? (isDark ? Colors.blue.withValues(alpha: 0.35) : Colors.blue.shade200)
                                                        : (isDark ? Colors.orange.withValues(alpha: 0.35) : Colors.orange.shade200),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      transaction.isBankDeposit 
                                                          ? Icons.account_balance 
                                                          : Icons.money,
                                                      size: 14,
                                                      color: transaction.isBankDeposit 
                                                          ? Colors.blue.shade700 
                                                          : Colors.orange.shade700,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      transaction.depositTypeLabel,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: transaction.isBankDeposit 
                                                            ? Colors.blue.shade700 
                                                            : Colors.orange.shade700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (transaction.description != null)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 2),
                                                child: Text(
                                                  transaction.description!,
                                                  style: const TextStyle(fontSize: 12),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            Text(
                                              '${isLesson ? 'Преподаватель' : 'Автор'}: ${((transaction.teacherUsername ?? '').trim().isNotEmpty) ? transaction.teacherUsername!.trim() : 'ID ${transaction.createdBy}'}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.onSurface.withValues(alpha: 0.72),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              DateFormat('dd.MM.yyyy HH:mm')
                                                  .format(transaction.createdAt),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.onSurface.withValues(alpha:0.60),
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${isDeposit ? '+' : '-'}${transaction.amount.toStringAsFixed(0)} ₽',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: isDeposit ? Colors.green : Colors.red,
                                              ),
                                            ),
                                            if (_showAllAccountingData && isDeposit) ...[
                                              const SizedBox(width: 8),
                                              IconButton(
                                                onPressed: () => _cancelDeposit(transaction),
                                                icon: const Icon(Icons.undo_rounded),
                                                tooltip: 'Отменить пополнение',
                                                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                                padding: EdgeInsets.zero,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  ),
                                ),
                    ],
                  ),
                ),
              ],
                      ),
          ),
        ],
      ),
    );
  }
}

