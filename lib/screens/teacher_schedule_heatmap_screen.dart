import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_author_option.dart';
import '../models/teacher_schedule_heatmap.dart';
import '../services/admin_service.dart';
import '../theme/app_colors.dart';
import '../utils/network_error_helper.dart';

/// Теплокарта занятий преподавателя по дням недели и времени (только суперпользователь).
class TeacherScheduleHeatmapScreen extends StatefulWidget {
  const TeacherScheduleHeatmapScreen({super.key});

  @override
  State<TeacherScheduleHeatmapScreen> createState() =>
      _TeacherScheduleHeatmapScreenState();
}

class _TeacherScheduleHeatmapScreenState extends State<TeacherScheduleHeatmapScreen> {
  final AdminService _admin = AdminService();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  int? _teacherId;
  List<ReportAuthorOption> _teachers = [];
  TeacherScheduleHeatmap? _heatmap;
  bool _loadingTeachers = false;
  bool _loadingHeatmap = false;
  String? _error;

  static const List<String> _weekdayLabels = [
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Вс',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadTeachers());
  }

  Future<void> _loadTeachers() async {
    setState(() {
      _loadingTeachers = true;
      _error = null;
    });
    try {
      final list = await _admin.getTeacherScheduleTeachers(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _teachers = list;
        if (_teacherId != null && !list.any((t) => t.id == _teacherId)) {
          _teacherId = null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = networkErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _loadHeatmap() async {
    final tid = _teacherId;
    if (tid == null) {
      setState(() => _error = 'Выберите преподавателя');
      return;
    }
    setState(() {
      _loadingHeatmap = true;
      _error = null;
    });
    try {
      final data = await _admin.getTeacherScheduleHeatmap(
        from: _from,
        to: _to,
        teacherId: tid,
      );
      if (mounted) setState(() => _heatmap = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _heatmap = null;
          _error = networkErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loadingHeatmap = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = d;
      } else {
        _to = d;
      }
    });
    await _loadTeachers();
  }

  Future<void> _applyFilters() async {
    await _loadTeachers();
    await _loadHeatmap();
  }

  Color _cellColor(BuildContext context, int count, int max) {
    final scheme = Theme.of(context).colorScheme;
    if (count <= 0) {
      return scheme.surfaceContainerHighest.withValues(alpha: 0.35);
    }
    final t = max > 0 ? (count / max).clamp(0.0, 1.0) : 1.0;
    return Color.lerp(
      AppColors.primary.withValues(alpha: 0.15),
      AppColors.primary,
      t,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heat = _heatmap;

    return Scaffold(
      appBar: AppBar(
        title: const Text('График работы преподавателя'),
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
                  const Text(
                    'Период и преподаватель',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDate(isFrom: true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'С ${DateFormat('dd.MM.yyyy').format(_from)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDate(isFrom: false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'По ${DateFormat('dd.MM.yyyy').format(_to)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Преподаватель',
                      isDense: true,
                      suffixIcon: _loadingTeachers
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
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _teachers.any((t) => t.id == _teacherId)
                            ? _teacherId
                            : null,
                        hint: Text(
                          _teachers.isEmpty
                              ? 'Нет занятий в периоде'
                              : 'Выберите преподавателя',
                        ),
                        items: _teachers
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  t.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _loadingTeachers || _teachers.isEmpty
                            ? null
                            : (v) => setState(() => _teacherId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_loadingHeatmap || _loadingTeachers)
                          ? null
                          : _applyFilters,
                      icon: _loadingHeatmap
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.grid_on_rounded),
                      label: const Text('Показать график'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          if (heat != null) ...[
            const SizedBox(height: 12),
            Text(
              '${heat.teacherLabel} · ${heat.totalLessons} занятий за период',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (heat.lessonsWithoutTime > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Без указанного времени: ${heat.lessonsWithoutTime}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (heat.timeSlots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Нет занятий с указанным временем в выбранном периоде.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                ),
              )
            else
              _WeekdayColumnsGrid(
                heatmap: heat,
                weekdayLabels: _weekdayLabels,
                cellColor: _cellColor,
              ),
            const SizedBox(height: 8),
            Text(
              'В каждом столбце дня — только реальные времена этого дня (без пустых «чужих» слотов). '
              'Число — занятий за весь период в это время.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekdayColumnsGrid extends StatelessWidget {
  final TeacherScheduleHeatmap heatmap;
  final List<String> weekdayLabels;
  final Color Function(BuildContext context, int count, int max) cellColor;

  const _WeekdayColumnsGrid({
    required this.heatmap,
    required this.weekdayLabels,
    required this.cellColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = heatmap.maxCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(7, (i) {
            final weekday = i + 1;
            final slots = heatmap.slotsForWeekday(weekday);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      weekdayLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (slots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '—',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.35),
                          ),
                        ),
                      )
                    else
                      ...slots.map((slot) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Tooltip(
                            message:
                                '${weekdayLabels[i]} ${slot.timeSlot} — ${slot.count} занятий',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cellColor(context, slot.count, max),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outline.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    slot.timeSlot,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: slot.count >= max * 0.55
                                          ? Colors.white.withValues(alpha: 0.95)
                                          : scheme.onSurface.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${slot.count}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: slot.count >= max * 0.55
                                          ? Colors.white
                                          : scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
