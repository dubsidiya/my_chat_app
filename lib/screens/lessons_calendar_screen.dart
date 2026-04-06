import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/students_service.dart';
import '../theme/app_colors.dart';

/// Календарь: сколько занятий у текущего пользователя в каждый день месяца.
class LessonsCalendarScreen extends StatefulWidget {
  const LessonsCalendarScreen({super.key});

  @override
  State<LessonsCalendarScreen> createState() => _LessonsCalendarScreenState();
}

class _LessonsCalendarScreenState extends State<LessonsCalendarScreen> {
  final StudentsService _studentsService = StudentsService();
  DateTime _focused = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<DateTime, int> _counts = {};
  bool _loading = false;
  String? _error;

  static const Color _accent = AppColors.primaryGlow;

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = DateTime(_focused.year, _focused.month, 1);
      final to = DateTime(_focused.year, _focused.month + 1, 0);
      final map = await _studentsService.getLessonsCalendarSummary(from: from, to: to);
      if (mounted) setState(() => _counts = map);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month - 1, 1);
    });
    _loadMonth();
  }

  void _nextMonth() {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month + 1, 1);
    });
    _loadMonth();
  }

  int _countFor(DateTime day) => _counts[DateTime(day.year, day.month, day.day)] ?? 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = DateFormat('LLLL yyyy', 'ru').format(_focused);
    final firstWeekday = DateTime(_focused.year, _focused.month, 1).weekday;
    // Понедельник = 1 … воскресенье = 7; сетка с понедельника.
    final leading = firstWeekday == 7 ? 6 : firstWeekday - 1;
    final daysInMonth = DateTime(_focused.year, _focused.month + 1, 0).day;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь занятий'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                IconButton(onPressed: _loading ? null : _prevMonth, icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(
                    '${title[0].toUpperCase()}${title.substring(1)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(onPressed: _loading ? null : _nextMonth, icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d, style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.55))),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: _loading && _counts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: rows,
                    itemBuilder: (context, row) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: List.generate(7, (col) {
                            final idx = row * 7 + col;
                            if (idx < leading || idx >= leading + daysInMonth) {
                              return const Expanded(child: SizedBox(height: 52));
                            }
                            final day = idx - leading + 1;
                            final date = DateTime(_focused.year, _focused.month, day);
                            final n = _countFor(date);
                            final today = DateUtils.isSameDay(date, DateTime.now());
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: today ? _accent.withValues(alpha: 0.18) : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: today ? _accent.withValues(alpha: 0.5) : scheme.outline.withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$day',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                        if (n > 0)
                                          Text(
                                            '$n',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: _accent,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Число в ячейке — ваши занятия за день (все ученики). Подробности — в карточке ученика или в отчёте.',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.65), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
