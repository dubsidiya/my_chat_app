import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../services/admin_service.dart';
import '../services/students_service.dart';
import '../utils/download_text_file.dart';
import '../utils/download_binary_file.dart';
import '../utils/save_download_file.dart';
import '../utils/network_error_helper.dart';
import 'bank_statement_screen.dart';
import 'deposit_pick_student_screen.dart';
import 'deposit_screen.dart';
import '../models/transaction.dart';

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
  int? _errorStatus;
  AccountingExport? _data;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  // Период/фильтры, с которыми реально загружены данные (для экспорта «как на экране»).
  DateTime? _loadedFrom;
  DateTime? _loadedTo;
  bool _loadedBankTransferOnly = false;

  String _committedQuery = '';
  Timer? _queryDebounce;
  bool _onlyDebts = false;
  bool _bankTransferOnly = false;

  // Мемоизированное отфильтрованное дерево (не пересобираем в build).
  List<AccountingTreeTeacher> _filteredTree = const [];

  String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _fmtHuman(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  String _norm(String s) => s.toLowerCase().trim();

  /// Единый денежный форматтер экрана: ₽ + фиксированные знаки (M44/M45).
  String _money(num v) => '₽${v.toStringAsFixed(0)}';

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Данные на экране не соответствуют текущему выбору периода/фильтра —
  /// экспорт заблокирован до нажатия «Сформировать» (M43).
  bool get _isDirty {
    if (_data == null || _loadedFrom == null || _loadedTo == null) return true;
    return !_sameDate(_loadedFrom!, _from) ||
        !_sameDate(_loadedTo!, _to) ||
        _loadedBankTransferOnly != _bankTransferOnly;
  }

  bool get _isSuperuserDenied => _errorStatus == 403;

  /// Короткое сообщение об ошибке: по HTTP-коду (401/403), иначе через общий helper (M58/M59).
  String _errorText(Object e) {
    if (e is AdminApiException) {
      if (e.statusCode == 401) return 'Сессия истекла. Войдите в приложение заново.';
      if (e.statusCode == 403) {
        return 'Недостаточно прав. Этот раздел доступен только суперпользователю.';
      }
    }
    return networkErrorMessage(e);
  }

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
    final accent1 = AppColors.primary;
    final accent2 = AppColors.primaryGlow;
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
              gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryGlow]),
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
                      label: unpaidCount > 0
                          ? 'долг по фильтру: $unpaidCount • ${_money(unpaidSum)}'
                          : 'всё оплачено',
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

  double _periodDebtSum(Iterable<AccountingLesson> lessons) {
    var sum = 0.0;
    for (final l in lessons) {
      if (!l.countsAsPeriodDebt) continue;
      sum += l.unpaidAmount;
    }
    return sum;
  }

  int _periodDebtCount(Iterable<AccountingLesson> lessons) {
    return lessons.where((l) => l.countsAsPeriodDebt).length;
  }

  Widget _lessonTile(AccountingLesson l) {
    final scheme = Theme.of(context).colorScheme;
    final date = l.lessonDate;
    final time = l.lessonTime;
    final isPaid = l.isPaid;
    final isNonBillable = l.isNonBillable;
    final Color color;
    final Color bg;
    if (isNonBillable) {
      color = Colors.grey.shade600;
      bg = Colors.grey.withAlpha(16);
    } else {
      color = isPaid ? Colors.green.shade700 : Colors.red.shade700;
      bg = isPaid ? Colors.green.withAlpha(16) : Colors.red.withAlpha(16);
    }
    final status = l.status;
    final originLessonDate = l.originLessonDate;
    String statusLabel;
    switch (status) {
      case 'missed':
        statusLabel = 'Пропуск';
        break;
      case 'makeup':
        statusLabel = 'Отработка';
        break;
      case 'cancel_same_day':
        statusLabel = 'Отмена в день';
        break;
      default:
        statusLabel = 'Проведено';
    }

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
                if (!isNonBillable) ...[
                  const SizedBox(height: 6),
                  Text(
                    'цена: ${_money(l.price)} • опл: ${_money(l.paidAmount)} • долг: ${_money(l.unpaidAmount)}',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha:0.75)),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  status == 'makeup' && originLessonDate.isNotEmpty
                      ? 'статус: $statusLabel · за пропуск $originLessonDate'
                      : 'статус: $statusLabel',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
              isNonBillable ? 'Без оплаты' : (isPaid ? 'Оплачено' : 'Долг'),
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

  void _onQueryChanged(String v) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _committedQuery = v;
        _recomputeFilteredTree();
      });
    });
  }

  /// Пересобрать отфильтрованное дерево из типизированных данных (M46).
  void _recomputeFilteredTree() {
    final data = _data;
    if (data == null) {
      _filteredTree = const [];
      return;
    }
    final q = _norm(_committedQuery);
    final onlyDebts = _onlyDebts;
    final out = <AccountingTreeTeacher>[];
    for (final t in data.tree) {
      final teacherMatches = q.isEmpty || _norm(t.teacherUsername).contains(q);
      final studentsFiltered = <AccountingTreeStudent>[];
      for (final s in t.students) {
        final lessonsFiltered = s.lessons
            .where((l) => !(onlyDebts && l.isPaid))
            .toList();

        final studentMatches = q.isEmpty || _norm(s.studentName).contains(q);
        final lessonMatches = q.isEmpty
            ? true
            : lessonsFiltered
                .any((l) => _norm('${l.lessonDate} ${l.lessonTime}').contains(q));

        if (q.isNotEmpty && !(teacherMatches || studentMatches || lessonMatches)) {
          continue;
        }
        // Ученика без строк занятий оставляем, кроме режима «только долги».
        if (lessonsFiltered.isEmpty && onlyDebts) continue;

        studentsFiltered.add(AccountingTreeStudent(
          studentId: s.studentId,
          studentName: s.studentName,
          walletDebt: s.walletDebt,
          walletPrepaid: s.walletPrepaid,
          lessons: lessonsFiltered,
        ));
      }
      if (studentsFiltered.isEmpty) continue;
      out.add(AccountingTreeTeacher(
        teacherUsername: t.teacherUsername,
        students: studentsFiltered,
      ));
    }
    _filteredTree = out;
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _errorStatus = null;
      _data = null;
      _filteredTree = const [];
    });
    final from = _from;
    final to = _to;
    final bankOnly = _bankTransferOnly;
    try {
      final res = await _adminService.exportAccountingJson(
        from: _fmt(from),
        to: _fmt(to),
        bankTransferOnly: bankOnly,
      );
      if (!mounted) return;
      setState(() {
        _data = res;
        _loadedFrom = from;
        _loadedTo = to;
        _loadedBankTransferOnly = bankOnly;
        _recomputeFilteredTree();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorText(e);
        _errorStatus = e is AdminApiException ? e.statusCode : null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyCsv() async {
    try {
      final csv = await _adminService.exportAccountingCsv(
        from: _fmt(_loadedFrom ?? _from),
        to: _fmt(_loadedTo ?? _to),
        bankTransferOnly: _loadedBankTransferOnly,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('CSV скопирован в буфер обмена'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка CSV: ${_errorText(e)}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadCsvFile() async {
    try {
      final loadedFrom = _loadedFrom ?? _from;
      final loadedTo = _loadedTo ?? _to;
      final csv = await _adminService.exportAccountingCsv(
        from: _fmt(loadedFrom),
        to: _fmt(loadedTo),
        bankTransferOnly: _loadedBankTransferOnly,
      );
      final filename = 'accounting_${_fmt(loadedFrom)}_${_fmt(loadedTo)}.csv';

      // Web: нормальная загрузка файлом
      final okWeb = await downloadTextFile(
        filename: filename,
        content: csv,
        mimeType: 'text/csv; charset=utf-8',
      );
      if (okWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('CSV скачан'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // Mobile/Desktop: системный диалог «Сохранить» (Загрузки / Файлы)
      final outcome = await saveDownloadFile(
        filename: filename,
        bytes: Uint8List.fromList(utf8.encode(csv)),
        allowedExtensions: const ['csv'],
      );
      if (!mounted) return;
      if (outcome == SaveDownloadOutcome.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Сохранение CSV отменено'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('CSV сохранён'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка скачивания: ${_errorText(e)}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadXlsxFile() async {
    try {
      final loadedFrom = _loadedFrom ?? _from;
      final loadedTo = _loadedTo ?? _to;
      final bytes = await _adminService.exportAccountingXlsxBytes(
        from: _fmt(loadedFrom),
        to: _fmt(loadedTo),
        bankTransferOnly: _loadedBankTransferOnly,
      );
      final filename = 'buhgalteriya_${_fmt(loadedFrom)}_${_fmt(loadedTo)}.xlsx';
      const mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      final okWeb = await downloadBinaryFile(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (okWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Excel для бухгалтерии скачан'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // Mobile/Desktop: системный диалог — пользователь выбирает «Загрузки» и т.п.
      final outcome = await saveDownloadFile(
        filename: filename,
        bytes: bytes,
        allowedExtensions: const ['xlsx'],
      );
      if (!mounted) return;
      if (outcome == SaveDownloadOutcome.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Сохранение Excel отменено'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Excel сохранён'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Ошибка Excel-выгрузки: ${_errorText(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openDepositFromAccounting() async {
    final result = await Navigator.push<DepositPickResult?>(
      context,
      MaterialPageRoute(builder: (_) => const DepositPickStudentScreen()),
    );
    if (result == null || !mounted) return;

    final tx = result.transaction;
    if (tx.studentId != result.studentId) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Внимание: транзакция создана для другого ученика (ожидали id=${result.studentId}, получили id=${tx.studentId}).'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 20),
        ),
      );
    }

    await _load();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Пополнение выполнено: ${result.studentName}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await _studentsService.deleteTransaction(tx.id);
              if (!mounted) return;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                const SnackBar(duration: Duration(seconds: 3), content: Text('Пополнение отменено'), backgroundColor: Colors.orange),
              );
              await _load();
            } catch (e) {
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(duration: const Duration(seconds: 3), content: Text('Не удалось отменить: ${_errorText(e)}'), backgroundColor: Colors.red),
              );
            }
          },
        ),
      ),
    );
  }

  /// Открыть экран пополнения баланса для конкретного ученика из дерева бухгалтерии.
  Future<void> _openDepositForStudent(int studentId, String studentName) async {
    final tx = await Navigator.push<Transaction?>(
      context,
      MaterialPageRoute(
        builder: (_) => DepositScreen(studentId: studentId, studentName: studentName),
      ),
    );
    if (tx == null || !mounted) return;

    if (tx.studentId != studentId) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Внимание: транзакция создана для другого ученика (ожидали id=$studentId, получили id=${tx.studentId}).'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 20),
        ),
      );
    }

    await _load();
    if (!mounted) return;
    final displayName = studentName.trim().isEmpty ? 'Ученик #$studentId' : studentName;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Пополнение выполнено: $displayName'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            try {
              await _studentsService.deleteTransaction(tx.id);
              if (!mounted) return;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                const SnackBar(duration: Duration(seconds: 3), content: Text('Пополнение отменено'), backgroundColor: Colors.orange),
              );
              await _load();
            } catch (e) {
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(duration: const Duration(seconds: 3), content: Text('Не удалось отменить: ${_errorText(e)}'), backgroundColor: Colors.red),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _openBankStatementFromAccounting() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BankStatementScreen()),
    );
    if (ok == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Платежи применены'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    super.dispose();
  }

  /// Одна карточка преподавателя в дереве (строится лениво — M46).
  Widget _teacherNode(AccountingTreeTeacher t) {
    final bankTransferStudentIds =
        _data?.bankTransferStudentIds ?? const <int>{};
    final teacherName = t.teacherUsername;
    final students = t.students;

    final lessonsCount =
        students.fold<int>(0, (acc, s) => acc + s.lessons.length);
    int unpaidCount = 0;
    double unpaidSum = 0;
    for (final s in students) {
      unpaidCount += _periodDebtCount(s.lessons);
      unpaidSum += _periodDebtSum(s.lessons);
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
          final studentName = s.studentName;
          final studentId = s.studentId;
          final isBankTransferStudent =
              studentId != null && bankTransferStudentIds.contains(studentId);
          final lessons = s.lessons;
          final unpaidCount = _periodDebtCount(lessons);
          final unpaidSum = _periodDebtSum(lessons);
          final walletDebt = s.walletDebt;
          final walletPrepaid = s.walletPrepaid;
          return ExpansionTile(
            tilePadding: const EdgeInsets.only(left: 4, right: 4),
            childrenPadding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isBankTransferStudent
                    ? Colors.indigo.withAlpha(24)
                    : (unpaidCount > 0 ? Colors.red : Colors.green).withAlpha(18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isBankTransferStudent
                      ? Colors.indigo.withAlpha(70)
                      : (unpaidCount > 0 ? Colors.red : Colors.green).withAlpha(40),
                ),
              ),
              child: Icon(
                isBankTransferStudent ? Icons.account_balance_rounded : Icons.person_rounded,
                color: isBankTransferStudent
                    ? Colors.indigo.shade700
                    : (unpaidCount > 0 ? Colors.red.shade700 : Colors.green.shade700),
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
                    label: unpaidCount > 0
                        ? 'долг по фильтру: $unpaidCount • ${_money(unpaidSum)}'
                        : 'всё оплачено',
                    color: unpaidCount > 0 ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                  if (isBankTransferStudent)
                    _chip(
                      icon: Icons.account_balance_rounded,
                      label: 'расчётный счёт',
                      color: Colors.indigo.shade700,
                    ),
                  if (walletDebt > 0)
                    _chip(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'долг у этого препода: ${_money(walletDebt)}',
                      color: Colors.red.shade700,
                    )
                  else if (walletPrepaid > 0)
                    _chip(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'предоплата: ${_money(walletPrepaid)}',
                      color: Colors.green.shade700,
                    ),
                  if (studentId != null)
                    InkWell(
                      onTap: () => _openDepositForStudent(studentId, studentName),
                      borderRadius: BorderRadius.circular(999),
                      child: _chip(
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Пополнить баланс',
                        color: AppColors.primary,
                      ),
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totals = _data?.totals;
    final teachers = _data?.teachers ?? const <AccountingTeacherAgg>[];
    final exportsDisabled = _isLoading || _isDirty;

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
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Бухгалтерия', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (_isSuperuserDenied)
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
                          onChanged: _onQueryChanged,
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _onlyDebts,
                          onChanged: _isLoading
                              ? null
                              : (v) => setState(() {
                                    _onlyDebts = v;
                                    _recomputeFilteredTree();
                                  }),
                          title: const Text('Показывать только долги'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _bankTransferOnly,
                          onChanged: _isLoading
                              ? null
                              : (v) => setState(() => _bankTransferOnly = v),
                          title: const Text('Только расчётный счёт'),
                          subtitle: const Text(
                            'Учитывать только учеников, платящих на расчётный счёт',
                          ),
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
                                onPressed: exportsDisabled ? null : _copyCsv,
                                icon: const Icon(Icons.copy),
                                label: const Text('CSV копия'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: exportsDisabled ? null : _downloadCsvFile,
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('CSV файл'),
                              ),
                            ),
                          ],
                        ),
                        if (_isDirty && !_isLoading) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Период или фильтр изменены. Нажмите «Сформировать», чтобы обновить данные — тогда экспорт совпадёт с тем, что на экране.',
                            style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Text(
                          'Excel для бухгалтерии (сводка, преподаватели, ученики, занятия, транзакции):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: exportsDisabled ? null : _downloadXlsxFile,
                            icon: const Icon(Icons.table_view_rounded),
                            label: const Text('Excel для бухгалтерии'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                            ),
                          ),
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
                          Text('Занятий: ${totals.lessonsCount}'),
                          Text('Сумма занятий: ${_money(totals.lessonsAmount)}'),
                          Text('Оплачено: ${_money(totals.paidAmount)}'),
                          Text('Долг: ${_money(totals.unpaidAmount)}'),
                          const SizedBox(height: 6),
                          Text('Пропусков: ${totals.missedCount}'),
                          Text('Отработок: ${totals.makeupCount}'),
                          Text('Отмен в день: ${totals.cancelSameDayCount}'),
                          Text('Бесплатных отмен в день: ${totals.cancelSameDayFreeCount}'),
                          Text('Платных отмен в день: ${totals.cancelSameDayPaidCount}'),
                          Text('К отработке: ${totals.makeupPendingCount}'),
                          if (totals.lessonsCount == 0) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'В выбранном периоде занятий не найдено. Попробуйте выбрать более широкий период.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (!_isLoading && _filteredTree.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Преподаватель → дети → занятия',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ]),
            ),
          ),
          if (!_isLoading && _filteredTree.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: _filteredTree.length,
                itemBuilder: (context, i) => _teacherNode(_filteredTree[i]),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
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
                            final username = t.teacherUsername;
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
                                      Text('занятий: ${t.lessonsCount}'),
                                      Text('сумма: ${_money(t.amount)}'),
                                      Text('опл: ${_money(t.paidAmount)}'),
                                      Text('долг: ${_money(t.unpaidAmount)}'),
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
