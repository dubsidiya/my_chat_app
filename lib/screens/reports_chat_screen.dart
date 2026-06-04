import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/report.dart';
import '../models/report_author_option.dart';
import '../services/reports_service.dart';
import '../utils/network_error_helper.dart';
import 'report_text_view_screen.dart';
import 'report_builder_screen.dart';
import 'monthly_salary_screen.dart';

class ReportsChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final bool isSuperuser;

  const ReportsChatScreen({super.key, required this.userId, required this.userEmail, this.isSuperuser = false});

  @override
  // ignore: library_private_types_in_public_api
  _ReportsChatScreenState createState() => _ReportsChatScreenState();
}

class _ReportsChatScreenState extends State<ReportsChatScreen> {
  final ReportsService _reportsService = ReportsService();
  final TextEditingController _dateController = TextEditingController();
  List<Report> _reports = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  /// Режим «Все отчёты» для бухгалтера/суперпользователя
  bool _allReportsMode = false;
  DateTime _filterDateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _filterDateTo = DateTime.now();
  /// null = все, true = только поздние, false = только вовремя
  bool? _filterOnlyLate;
  /// null = все преподаватели
  int? _filterTeacherId;
  List<ReportAuthorOption> _teacherOptions = [];
  bool _teachersLoading = false;

  /// Напоминание: вчера не было отчёта (только свой режим, не бухгалтер).
  bool _yesterdayReminder = false;
  bool _yesterdayReminderDismissed = false;

  static Color get _accent1 => AppColors.primary;
  static Color get _accent2 => AppColors.primaryGlow;

  bool _canEditReport(Report report) {
    if (widget.isSuperuser) return true;
    if (!_allReportsMode) return true;
    return report.createdBy?.toString() == widget.userId;
  }

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
    _loadReports();
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  void _syncYesterdayReminder() {
    if (!mounted) return;
    if (_allReportsMode) {
      _yesterdayReminder = false;
      return;
    }
    if (_yesterdayReminderDismissed) {
      _yesterdayReminder = false;
      return;
    }
    final now = DateTime.now();
    final y = now.subtract(const Duration(days: 1));
    final yd = DateTime(y.year, y.month, y.day);
    final has = _reports.any((r) {
      final d = r.reportDate;
      return d.year == yd.year && d.month == yd.month && d.day == yd.day;
    });
    _yesterdayReminder = !has;
  }

  Future<void> _loadTeacherOptions() async {
    if (!mounted) return;
    setState(() => _teachersLoading = true);
    try {
      final teachers = await _reportsService.getReportAuthors(
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
      );
      if (!mounted) return;
      setState(() {
        _teacherOptions = teachers;
        if (_filterTeacherId != null &&
            !teachers.any((t) => t.id == _filterTeacherId)) {
          _filterTeacherId = null;
        }
      });
    } catch (e) {
      if (kDebugMode) print('Ошибка загрузки преподавателей: $e');
    } finally {
      if (mounted) setState(() => _teachersLoading = false);
    }
  }

  Future<void> _loadReportsList({bool refreshTeachers = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (refreshTeachers) await _loadTeacherOptions();
      final reports = await _reportsService.getAllReportsList(
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
        isLate: _filterOnlyLate,
        createdBy: _filterTeacherId,
      );
      if (mounted) {
        setState(() {
          _reports = reports;
          _syncYesterdayReminder();
        });
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка загрузки списка отчётов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(networkErrorMessage(e)),
            backgroundColor: Colors.red,
            action: SnackBarAction(label: 'Повторить', onPressed: () => _loadReportsList()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final reports = await _reportsService.getAllReports();
      if (mounted) {
        setState(() {
          _reports = reports;
          _syncYesterdayReminder();
        });
      }
    } catch (e) {
      if (kDebugMode) print('Ошибка загрузки отчетов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(networkErrorMessage(e)),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => _loadReports(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onRefresh() async {
    if (_allReportsMode) {
      await _loadReportsList();
    } else {
      await _loadReports();
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd.MM.yyyy').format(picked);
      });
    }
  }

  Future<void> _openBuilder() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportBuilderScreen(initialDate: _selectedDate),
      ),
    );
    if (result == true) {
      await _onRefresh();
    }
  }

  Future<void> _openBuilderEdit(int reportId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportBuilderScreen(reportId: reportId),
      ),
    );
    if (result == true) {
      await _onRefresh();
    }
  }

  /// Защита от двойного тапа на кнопку «По шаблону»: пока идёт поиск/открытие,
  /// повторные нажатия игнорируются (флаг быстрее, чем перерисовка через _isLoading).
  bool _openingTemplate = false;

  /// Открыть конструктор, предзаполненный отчётом ровно 14 дней назад от выбранной даты.
  /// Учитель чаще всего ведёт занятия с тем же расписанием по дням недели —
  /// шаблон ускоряет ввод, а отмены он внесёт точечно сам.
  Future<void> _openBuilderFromTwoWeeksAgo() async {
    if (_openingTemplate) return;
    _openingTemplate = true;
    try {
      // Календарное вычитание (а не Duration(days:14)) — устойчиво к DST.
      // DateTime сам нормализует отрицательный день месяца.
      final target = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - 14);

      // report_date приходит из Postgres типа `date`; pg-драйвер часто отдаёт его
      // как UTC-метку (XX:00:00Z), и сырая дата может «съезжать» на ±1 день
      // относительно локального дня пользователя. Сравниваем по локальным компонентам.
      bool sameLocalDay(Report r) {
        final d = r.reportDate.toLocal();
        return d.year == target.year && d.month == target.month && d.day == target.day;
      }
      bool ownedByMe(Report r) {
        // В «Все отчёты» нужно взять именно свой отчёт; в «Мои отчёты» список и так свой.
        if (!_allReportsMode) return true;
        if (r.createdBy == null) return true;
        return r.createdBy?.toString() == widget.userId;
      }

      Report? template;
      for (final r in _reports) {
        if (sameLocalDay(r) && ownedByMe(r)) {
          template = r;
          break;
        }
      }

      // Если в локальном кэше шаблон не нашёлся — добираем свежий список с сервера.
      // GET /reports всегда возвращает только мои отчёты, поэтому подходит и для режима
      // «Все отчёты» (нам всё равно нужен именно свой шаблон). Это же закрывает
      // потенциальную пагинацию /reports в будущем и устаревший кэш после правок
      // отчётов в другой сессии/устройстве.
      if (template == null) {
        try {
          final fresh = await _reportsService.getAllReports();
          for (final r in fresh) {
            if (sameLocalDay(r)) {
              template = r;
              break;
            }
          }
        } catch (_) {
          // молча: ниже покажем «не найден»; настоящие сетевые ошибки уже видны в _loadReports.
        }
      }

      if (!mounted) return;
      if (template == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
              'Ваш отчёт за ${DateFormat('dd.MM.yyyy').format(target)} не найден. '
              'Шаблон взять не из чего.',
            ),
          ),
        );
        return;
      }

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ReportBuilderScreen(
            initialDate: _selectedDate,
            templateReportId: template!.id,
          ),
        ),
      );
      if (result == true) {
        await _onRefresh();
      }
    } finally {
      _openingTemplate = false;
    }
  }

  Future<void> _openReportText(Report report) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReportTextViewScreen(report: report),
      ),
    );
  }

  Future<void> _deleteReport(Report report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить отчет?'),
        content: const Text(
          'Это удалит отчет и все связанные занятия. Действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await _reportsService.deleteReport(report.id);
      await _onRefresh();
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
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Отчеты за день',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.pie_chart_rounded, color: _accent1),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MonthlySalaryScreen(),
                  ),
                );
              },
              tooltip: 'Зарплата за месяц',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.add_rounded, color: _accent1),
              onPressed: _openBuilder,
              tooltip: 'Новый отчет',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: _accent1),
              onPressed: _allReportsMode ? _loadReportsList : _loadReports,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          if (_yesterdayReminder && !_allReportsMode)
            Material(
              color: Colors.amber.withValues(alpha: isDark ? 0.22 : 0.35),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'За вчера (${DateFormat('dd.MM.yyyy').format(DateTime.now().subtract(const Duration(days: 1)))}) отчёт не найден.',
                        style: TextStyle(fontSize: 13, color: scheme.onSurface, height: 1.25),
                      ),
                    ),
                    TextButton(
                      onPressed: _openBuilder,
                      child: const Text('Создать'),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _yesterdayReminderDismissed = true;
                        _yesterdayReminder = false;
                      }),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.isSuperuser) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Мои отчёты'), icon: Icon(Icons.person_outline_rounded, size: 18)),
                  ButtonSegment(value: true, label: Text('Все отчёты'), icon: Icon(Icons.list_alt_rounded, size: 18)),
                ],
                selected: {_allReportsMode},
                onSelectionChanged: (Set<bool> selected) {
                  final all = selected.first;
                  setState(() => _allReportsMode = all);
                  if (all) {
                    _filterTeacherId = null;
                    unawaited(_loadTeacherOptions());
                    _loadReportsList(refreshTeachers: false);
                  } else {
                    _loadReports();
                  }
                },
              ),
            ),
            if (_allReportsMode) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Период и фильтр', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface.withValues(alpha: 0.7))),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(context: context, initialDate: _filterDateFrom, firstDate: DateTime(2020), lastDate: DateTime.now());
                                  if (d != null && mounted) {
                                    setState(() => _filterDateFrom = d);
                                    unawaited(_loadTeacherOptions());
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(DateFormat('dd.MM.yyyy').format(_filterDateFrom), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            Text(' — ', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final d = await showDatePicker(context: context, initialDate: _filterDateTo, firstDate: DateTime(2020), lastDate: DateTime.now());
                                  if (d != null && mounted) {
                                    setState(() => _filterDateTo = d);
                                    unawaited(_loadTeacherOptions());
                                  }
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(DateFormat('dd.MM.yyyy').format(_filterDateTo), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int?>(
                          initialValue: _filterTeacherId,
                          decoration: InputDecoration(
                            labelText: 'Преподаватель',
                            isDense: true,
                            suffixIcon: _teachersLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : null,
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Все преподаватели'),
                            ),
                            ..._teacherOptions.map(
                              (t) => DropdownMenuItem<int?>(
                                value: t.id,
                                child: Text(
                                  t.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _teachersLoading
                              ? null
                              : (v) {
                                  setState(() => _filterTeacherId = v);
                                  if (!_isLoading) unawaited(_loadReportsList());
                                },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<bool?>(
                                initialValue: _filterOnlyLate,
                                decoration: const InputDecoration(labelText: 'Поздние', isDense: true),
                                items: const [
                                  DropdownMenuItem(value: null, child: Text('Все')),
                                  DropdownMenuItem(value: true, child: Text('Только поздние')),
                                  DropdownMenuItem(value: false, child: Text('Только вовремя')),
                                ],
                                onChanged: (v) => setState(() { _filterOnlyLate = v; }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () => _loadReportsList(refreshTeachers: true),
                              icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded, size: 20),
                              label: const Text('Показать'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
          if (!_allReportsMode) ...[
          // Поле ввода даты
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Card(
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha:0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [_accent1, _accent2]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _accent1.withValues(alpha:0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.calendar_today_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Дата для нового отчёта',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha:0.65),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _dateController.text,
                              style: TextStyle(
                                fontSize: 16,
                                color: scheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Только для кнопки «Сформировать отчёт». Список ниже — все ваши отчёты.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.25,
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha:isDark ? 0.38 : 0.32)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Поле ввода отчета
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha:0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(colors: [_accent1, _accent2]),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent1.withValues(alpha:0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _openBuilder,
                              icon: const Icon(Icons.playlist_add_check_rounded),
                              label: const Text(
                                'Сформировать отчет',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _openBuilderFromTwoWeeksAgo,
                            icon: Icon(Icons.event_repeat_rounded, color: _accent1),
                            label: Text(
                              'По шаблону 2-недельной давности',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _accent1,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: _accent1.withValues(alpha: 0.6)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Заполнит шаблон отчета за '
                          '${DateFormat('dd.MM.yyyy').format(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - 14))}. '
                          'У всех будет стоять ПРОВЕДЕНО!!!. Обязательно к ручной проверке! ',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),
          ],
          // Список отчетов
          Expanded(
            child: _isLoading && _reports.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                      strokeWidth: 3,
                    ),
                  )
                : _reports.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _accent1.withValues(alpha:0.2),
                                      _accent2.withValues(alpha:0.2),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.description_rounded,
                                  size: 60,
                                  color: _accent1.withValues(alpha:0.7),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'Нет отчетов',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                            color: scheme.onSurface.withValues(alpha:0.75),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Создайте отчет за день — занятия сформируются автоматически',
                                style: TextStyle(
                                  fontSize: 16,
                            color: scheme.onSurface.withValues(alpha:0.60),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          cacheExtent: 400,
                          itemCount: _reports.length,
                          itemBuilder: (context, index) {
                            final report = _reports[index];
                            final canEdit = _canEditReport(report);
                            return RepaintBoundary(
                              key: ValueKey('report_${report.id}'),
                              child: Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              elevation: 2,
                              shadowColor: Colors.black.withValues(alpha:0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: report.isEdited
                                          ? [Colors.orange.shade400, Colors.orange.shade700]
                                          : [_accent1, _accent2],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (report.isEdited ? Colors.orange : _accent1)
                                            .withValues(alpha:0.25),
                                        blurRadius: 10,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.description_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  DateFormat('dd.MM.yyyy').format(report.reportDate),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_filterTeacherId == null &&
                                        report.createdByLabel != null) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          'Кто сдал: ${report.createdByLabel}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      report.content,
                                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.70)),
                                    ),
                                    const SizedBox(height: 4),
                                    if (report.isLate)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(alpha:0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Поздний отчет',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.red.shade700,
                                                ),
                                              ),
                                            ),
                                            if (widget.isSuperuser) ...[
                                              const SizedBox(width: 8),
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                                onPressed: () async {
                                                  try {
                                                    await _reportsService.setReportNotLate(report.id);
                                                    if (!context.mounted) return;
                                                    await _onRefresh();
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(duration: Duration(seconds: 3), content: Text('Отчёт учтён как сдан вовремя')),
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(duration: const Duration(seconds: 3), content: Text(e.toString()), backgroundColor: Colors.red),
                                                    );
                                                  }
                                                },
                                                child: Text(
                                                  'Считать вовремя',
                                                  style: TextStyle(fontSize: 12, color: scheme.primary),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    if (report.isEdited)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(alpha:0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Отредактирован',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.orange.shade700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _accent1.withValues(alpha:0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Занятий: ${report.lessonsCount ?? 0}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _accent1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _accent1.withValues(alpha:0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Занятий: ${report.lessonsCount ?? 0}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _accent1,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  itemBuilder: (context) => [
                                    if (canEdit)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_rounded, size: 20),
                                            SizedBox(width: 8),
                                            Text('Редактировать (конструктор)'),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'view_text',
                                      child: Row(
                                        children: [
                                          Icon(Icons.content_copy_rounded, size: 20),
                                          SizedBox(width: 8),
                                          Text('Текст отчёта (копировать)'),
                                        ],
                                      ),
                                    ),
                                    if (canEdit)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded,
                                                size: 20, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Удалить', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openBuilderEdit(report.id);
                                    } else if (value == 'view_text') {
                                      _openReportText(report);
                                    } else if (value == 'delete') {
                                      _deleteReport(report);
                                    }
                                  },
                                ),
                              ),
                            ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

