import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../models/lesson.dart';
import '../models/transaction.dart';
import '../services/students_service.dart';
import '../services/reports_service.dart';
import '../services/storage_service.dart';
import '../utils/network_error_helper.dart';
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
  /// Успешно получили занятия, транзакции и баланс с сервера хотя бы раз.
  bool _accountingLoaded = false;
  String? _loadError;
  bool _showAllAccountingData = false;
  /// Были ли изменения (правка/удаление/отмена депозита) — чтобы список учеников
  /// перезагружался только когда это действительно нужно (M61).
  bool _changed = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
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

  /// Короткое сообщение об ошибке: 401 → перелогин, 403 → нет прав, иначе общий helper (M58).
  String _friendlyError(Object e) {
    final base = networkErrorMessage(e);
    if (base.contains('401') || base.toLowerCase().contains('unauthorized')) {
      return 'Сессия истекла. Войдите в приложение заново.';
    }
    if (base.contains('403') || base.contains('прав') || base.contains('доступ')) {
      return 'Недостаточно прав для просмотра этих данных.';
    }
    return base;
  }

  Future<void> _loadData({bool showSpinner = true}) async {
    if (!mounted) return;
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      // Три набора данных грузим параллельно, а не последовательно (M61).
      final results = await Future.wait([
        _loadLessons(),
        _loadTransactions(),
        _loadBalance(),
      ]);
      if (!mounted) return;
      setState(() {
        _lessons = results[0] as List<Lesson>;
        _transactions = results[1] as List<Transaction>;
        _balance = results[2] as double;
        _accountingLoaded = true;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyError(e);
      setState(() => _loadError = message);
      if (_accountingLoaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Не удалось обновить данные: $message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && showSpinner) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData() => _loadData(showSpinner: false);

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
        _changed = true;
      });
      await _refreshData();
    }
  }

  Widget _buildAccountingLoadError(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: scheme.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить данные',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.80),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : () => _loadData(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
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
      _changed = true;
      await _refreshData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Пополнение отменено'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Не удалось отменить: ${_friendlyError(e)}'), backgroundColor: Colors.red),
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
            content: Text('Ошибка удаления: ${_friendlyError(e)}'),
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
      _changed = true;
      // Быстрое обновление данных после удаления занятия
      await _refreshData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка: ${_friendlyError(e)}'),
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
          content: Text('Не удалось открыть отчёт: ${_friendlyError(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildLessonsPane(ColorScheme scheme) {
    return Builder(
      builder: (context) {
        return RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            key: const PageStorageKey<String>('student_lessons'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null && !_accountingLoaded)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildAccountingLoadError(scheme),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
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
                ),
                if (_lessons.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
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
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
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
                                DateFormat('dd.MM.yyyy').format(lesson.lessonDate),
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
                                      if (lesson.status == 'makeup' && lesson.originLessonDate != null)
                                        'за пропуск ${DateFormat('dd.MM.yyyy').format(lesson.originLessonDate!)}',
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
                                  if (lesson.isChargeable)
                                    Text(
                                      '${lesson.price.toStringAsFixed(0)} ₽',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  if (lesson.isChargeable) const SizedBox(height: 2),
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
                        childCount: _lessons.length,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionsPane(ColorScheme scheme, bool isDark) {
    return Builder(
      builder: (context) {
        return RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            key: const PageStorageKey<String>('student_transactions'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null && !_accountingLoaded)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildAccountingLoadError(scheme),
                )
              else if (_transactions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Нет транзакций',
                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final transaction = _transactions[index];
                        final isDeposit = transaction.type == 'deposit';
                        final isLesson = transaction.type == 'lesson';
                        // Знак берём из общего правила: депозит и возврат — плюс,
                        // занятие — минус (совпадает с сервером, M55).
                        final isCredit = transaction.isCredit;

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
                                if (isCredit && transaction.targetTeacherId != null)
                                  Text(
                                    'В кошелёк: ${(transaction.targetTeacherUsername ?? '').trim().isNotEmpty ? transaction.targetTeacherUsername!.trim() : 'ID ${transaction.targetTeacherId}'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurface.withValues(alpha: 0.72),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                Text(
                                  DateFormat('dd.MM.yyyy HH:mm').format(transaction.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurface.withValues(alpha: 0.60),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${isCredit ? '+' : '-'}${transaction.amount.toStringAsFixed(0)} ₽',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isCredit ? Colors.green : Colors.red,
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
                      childCount: _transactions.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Округляем баланс и от него берём признак должника (L31), чтобы −0.40 ₽
    // не показывался как «-0 ₽ / Долг».
    final balanceRounded = _balance.round();
    final isDebtor = _accountingLoaded && balanceRounded < 0;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final makeupPending = Lesson.countOpenMakeupDebts(_lessons);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
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
            onPressed: _deleteStudent,
            tooltip: 'Удалить связь',
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: !_accountingLoaded
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                      : isDebtor
                          ? Colors.red.withValues(alpha: isDark ? 0.14 : 0.10)
                          : Colors.green.withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: !_accountingLoaded
                        ? scheme.outline.withValues(alpha: 0.35)
                        : (isDebtor ? Colors.red : Colors.green).withValues(alpha: isDark ? 0.55 : 0.65),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Баланс',
                      style: TextStyle(
                        fontSize: 16,
                        color: scheme.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _accountingLoaded ? '$balanceRounded ₽' : '—',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: !_accountingLoaded
                            ? scheme.onSurface.withValues(alpha: 0.55)
                            : isDebtor
                                ? Colors.red.shade400
                                : balanceRounded > 0
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
                    if (_loadError != null && _accountingLoaded)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Не удалось обновить данные',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    if (_loadError != null && !_accountingLoaded)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Баланс не загружен',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline.withValues(alpha: isDark ? 0.18 : 0.12)),
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
                              color: scheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            if (_lessons.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
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
              ),
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                pinned: true,
                primary: false,
                automaticallyImplyLeading: false,
                toolbarHeight: 0,
                forceElevated: innerBoxIsScrolled,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                surfaceTintColor: Colors.transparent,
                bottom: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: 'Занятия (${_lessons.length})'),
                    Tab(text: 'Транзакции (${_transactions.length})'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLessonsPane(scheme),
            _buildTransactionsPane(scheme, isDark),
          ],
        ),
      ),
      ),
    );
  }
}

