import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/report_author_option.dart';
import '../models/teacher_placement_plan.dart';
import '../services/admin_service.dart';
import '../utils/network_error_helper.dart';
import 'nagavisor_screen.dart';

/// Планировщик: по выбранным преподавателям — в какие дни и время можно поставить ребёнка.
class TeacherScheduleOverviewScreen extends StatefulWidget {
  final List<int>? initialTeacherIds;
  final DateTime? initialFrom;
  final DateTime? initialTo;

  const TeacherScheduleOverviewScreen({
    super.key,
    this.initialTeacherIds,
    this.initialFrom,
    this.initialTo,
  });

  @override
  State<TeacherScheduleOverviewScreen> createState() =>
      _TeacherScheduleOverviewScreenState();
}

class _TeacherScheduleOverviewScreenState extends State<TeacherScheduleOverviewScreen> {
  final AdminService _admin = AdminService();

  late DateTime _from;
  late DateTime _to;
  List<ReportAuthorOption> _teachers = [];
  final Set<int> _selectedTeacherIds = {};
  TeacherPlacementPlan? _plan;
  bool _onlyOpen = true;

  bool _loadingTeachers = false;
  bool _loadingPlan = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = widget.initialFrom ?? DateTime(now.year, now.month, 1);
    _to = widget.initialTo ?? now;
    if (_from.isAfter(_to)) {
      final tmp = _from;
      _from = _to;
      _to = tmp;
    }
    unawaited(_loadTeachers());
  }

  bool get _periodValid => !_from.isAfter(_to);

  Future<void> _loadTeachers() async {
    if (!_periodValid) {
      setState(() => _error = 'Дата «С» не может быть позже «По»');
      return;
    }
    setState(() {
      _loadingTeachers = true;
      _error = null;
    });
    try {
      final list = await _admin.getTeacherScheduleTeachers(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _teachers = list;
        _selectedTeacherIds.removeWhere((id) => !list.any((t) => t.id == id));
        final initial = widget.initialTeacherIds;
        if (initial != null && _selectedTeacherIds.isEmpty) {
          for (final id in initial.take(5)) {
            if (list.any((t) => t.id == id)) _selectedTeacherIds.add(id);
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = networkErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _loadPlan() async {
    if (!_periodValid) {
      setState(() => _error = 'Дата «С» не может быть позже «По»');
      return;
    }
    if (_selectedTeacherIds.isEmpty) {
      setState(() => _error = 'Выберите 1–5 преподавателей');
      return;
    }
    setState(() {
      _loadingPlan = true;
      _error = null;
    });
    try {
      final data = await _admin.getTeacherPlacementPlan(
        from: _from,
        to: _to,
        teacherIds: _selectedTeacherIds.toList(),
      );
      if (mounted) setState(() => _plan = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _plan = null;
          _error = networkErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _loadingPlan = false);
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
      if (_from.isAfter(_to)) {
        _error = 'Дата «С» не может быть позже «По»';
        _plan = null;
      } else {
        _error = null;
      }
    });
    if (_periodValid) await _loadTeachers();
  }

  void _toggleTeacher(int id) {
    setState(() {
      if (_selectedTeacherIds.contains(id)) {
        _selectedTeacherIds.remove(id);
      } else if (_selectedTeacherIds.length < 5) {
        _selectedTeacherIds.add(id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не более 5 преподавателей')),
        );
      }
    });
  }

  Future<void> _apply() async {
    if (!_periodValid) {
      setState(() => _error = 'Дата «С» не может быть позже «По»');
      return;
    }
    await _loadTeachers();
    await _loadPlan();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.green.shade700;
      case 'limited':
        return Colors.orange.shade800;
      case 'full':
        return Colors.red.shade700;
      case 'unstable':
        return Colors.blueGrey.shade600;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Планировщик загрузки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Выберите преподавателей — увидите рекомендации по дням и времени на основе фактических уроков. Запись ребёнка делается отдельно.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Период анализа', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDate(isFrom: true),
                          child: Text(
                            'С ${DateFormat('dd.MM.yyyy').format(_from)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => _pickDate(isFrom: false),
                          child: Text(
                            'По ${DateFormat('dd.MM.yyyy').format(_to)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Преподаватели (${_selectedTeacherIds.length}/5)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingTeachers && _teachers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_teachers.isEmpty)
                    Text('Нет занятий в периоде', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _teachers.map((t) {
                        final selected = _selectedTeacherIds.contains(t.id);
                        return FilterChip(
                          label: Text(t.label, overflow: TextOverflow.ellipsis),
                          selected: selected,
                          onSelected: (_) => _toggleTeacher(t.id),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_loadingPlan || _loadingTeachers || !_periodValid) ? null : _apply,
                      icon: _loadingPlan
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.event_available_rounded),
                      label: const Text('Показать слоты'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
          ],
          if (plan != null) ...[
            const SizedBox(height: 12),
            if (plan.hint != null && plan.hint!.isNotEmpty)
              Text(plan.hint!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только «Можно поставить»'),
              value: _onlyOpen,
              onChanged: (v) => setState(() => _onlyOpen = v),
            ),
            ...plan.teachers.map((teacher) => _TeacherPlacementCard(
                  teacher: teacher,
                  onlyOpen: _onlyOpen,
                  statusColor: _statusColor,
                  onNagavisor: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => NagavisorScreen(
                          teacherId: teacher.teacherId,
                          teacherLabel: teacher.teacherLabel,
                          initialFrom: _from,
                          initialTo: _to,
                        ),
                      ),
                    );
                  },
                )),
          ],
        ],
      ),
    );
  }
}

class _TeacherPlacementCard extends StatelessWidget {
  final TeacherPlacementTeacher teacher;
  final bool onlyOpen;
  final Color Function(String status) statusColor;
  final VoidCallback onNagavisor;

  const _TeacherPlacementCard({
    required this.teacher,
    required this.onlyOpen,
    required this.statusColor,
    required this.onNagavisor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slots = onlyOpen ? teacher.openSlots : teacher.slots;
    final typical = teacher.typicalWeekdays.join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    teacher.teacherLabel,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  onPressed: onNagavisor,
                  icon: const Icon(Icons.person_search_rounded, size: 18),
                  label: const Text('Сводка'),
                ),
              ],
            ),
            if (typical.isNotEmpty)
              Text(
                'Обычно работает: $typical',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            Text(
              'Слотов «можно поставить»: ${teacher.openSlotsCount}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: teacher.openSlotsCount > 0 ? Colors.green.shade700 : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (slots.isEmpty)
              Text(
                onlyOpen ? 'Нет свободных устойчивых слотов в периоде' : 'Нет занятий с указанным временем',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              ...slots.map((slot) {
                final color = statusColor(slot.placementStatus);
                final peak = slot.studentsPeak;
                final density = peak != null && peak != slot.studentsCount
                    ? '${slot.studentsCount} уч. (пик $peak) · ${slot.lessonsCount} ур. · ${slot.weeksActive} нед.'
                    : '${slot.studentsCount} уч. · ${slot.lessonsCount} ур. · ${slot.weeksActive} нед.';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: color.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(12),
                    color: color.withValues(alpha: 0.06),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    title: Text(
                      '${slot.weekdayLabel} · ${slot.timeSlot}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${slot.placementLabel} · $density',
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    children: [
                      if (!slot.isRecurring)
                        Text(
                          'Слот встречался меньше 2 недель — осторожно с переносом',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                        ),
                      if (!slot.isTypicalDay)
                        Text(
                          'День не входит в обычный график преподавателя',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                        )
                      else
                        Text(
                          'День входит в обычный график преподавателя',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Ученики в слоте за период:',
                        style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                      ),
                      if (slot.students.isEmpty)
                        const Text('Никого (слот пустой в данных периода)')
                      else
                        ...slot.students.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• ${s.studentName}'),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
