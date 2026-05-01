import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../models/report_slot.dart';
import '../services/students_service.dart';
import '../services/reports_service.dart';
import '../services/storage_service.dart';
import '../services/report_builder_draft_storage.dart';
import '../utils/network_error_helper.dart';

class ReportBuilderScreen extends StatefulWidget {
  final DateTime? initialDate;
  final int? reportId; // если задан — режим редактирования

  const ReportBuilderScreen({super.key, this.initialDate, this.reportId});

  @override
  // ignore: library_private_types_in_public_api
  State<ReportBuilderScreen> createState() => _ReportBuilderScreenState();
}

class _SlotDraft {
  final TextEditingController startController = TextEditingController();
  final List<TextEditingController> priceControllers =
      List.generate(_ReportBuilderScreenState._maxStudentsPerSlot, (_) => TextEditingController());

  int durationMinutes = 60;
  final List<int?> studentIds = List<int?>.filled(_ReportBuilderScreenState._maxStudentsPerSlot, null);
  final List<String> statuses = List<String>.filled(_ReportBuilderScreenState._maxStudentsPerSlot, 'attended');

  void dispose() {
    startController.dispose();
    for (final controller in priceControllers) {
      controller.dispose();
    }
  }
}

class _ReportBuilderScreenState extends State<ReportBuilderScreen> {
  static const int _maxSlots = 10;
  static const int _maxStudentsPerSlot = 4;

  final StudentsService _studentsService = StudentsService();
  final ReportsService _reportsService = ReportsService();

  final TextEditingController _dateController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  List<Student> _students = [];
  final List<_SlotDraft> _slots = [];
  final Map<int, double> _lastPriceByStudent = {};
  Timer? _draftTimer;
  String? _userId;

  String _reportSaveErrorText(Object error) {
    final msg = networkErrorMessage(error);
    if (msg.contains('Для отработки не найден') || msg.contains('не найден неотработанный пропуск')) {
      return 'Нельзя провести отработку: нет пропусков к отработке.';
    }
    if (msg.contains('Этот пропуск уже отработан')) {
      return 'Нельзя провести отработку: этот пропуск уже закрыт.';
    }
    return msg;
  }

  @override
  void initState() {
    super.initState();
    _draftTimer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_persistDraftSafe()));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final u = await StorageService.getUserData();
      if (mounted) setState(() => _userId = u?['id']);
    });
    _selectedDate = widget.initialDate ?? DateTime.now();
    _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
    _init();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      final students = await _studentsService.getAllStudents();
      final userData = await StorageService.getUserData();
      final userId = userData?['id'];
      final hiddenIds = userId == null
          ? <int>{}
          : await StorageService.getHiddenStudentIds(userId);
      final visibleStudents = students.where((s) => !hiddenIds.contains(s.id)).toList();

      // Если редактирование — грузим отчет и заполняем слоты
      if (widget.reportId != null) {
        final report = await _reportsService.getReport(widget.reportId!);
        final reportDate = report.reportDate;

        final lessons = report.lessons ?? const [];
        final slotDrafts = <_SlotDraft>[];
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final l in lessons) {
          final timeRaw = (l['lesson_time'] ?? '').toString();
          final start = timeRaw.length >= 5 ? timeRaw.substring(0, 5) : timeRaw;
          final duration = (l['duration_minutes'] ?? 60) is int
              ? (l['duration_minutes'] as int)
              : int.tryParse(l['duration_minutes'].toString()) ?? 60;
          final key = '$start|$duration';
          grouped.putIfAbsent(key, () => []).add(l);
        }

        for (final entry in grouped.entries) {
          final parts = entry.key.split('|');
          final start = parts[0];
          final duration = int.tryParse(parts[1]) ?? 60;
          final items = entry.value;

          // В одном слоте максимум 4 ученика — если больше, разбиваем на несколько слотов
          for (int i = 0; i < items.length; i += _maxStudentsPerSlot) {
            final chunk = items.skip(i).take(_maxStudentsPerSlot).toList();
            final slot = _SlotDraft();
            slot.startController.text = start;
            slot.durationMinutes = duration;

            for (int childIndex = 0; childIndex < chunk.length; childIndex++) {
              final item = chunk[childIndex];
              slot.studentIds[childIndex] = int.tryParse(item['student_id'].toString());
              slot.statuses[childIndex] = (item['status'] ?? 'attended').toString();
              final price = item['price'];
              slot.priceControllers[childIndex].text =
                  price is num ? price.toString() : (double.tryParse(price.toString())?.toString() ?? '');
            }
            slotDrafts.add(slot);
          }
        }

        // если слотов нет — оставим один пустой
        if (slotDrafts.isEmpty) {
          slotDrafts.add(_SlotDraft());
        }

        if (!mounted) return;
        setState(() {
          _students = visibleStudents;
          _selectedDate = reportDate;
          _dateController.text = DateFormat('dd.MM.yyyy').format(reportDate);
          _slots.clear();
          _slots.addAll(slotDrafts.take(_maxSlots));
        });
      } else {
        if (!mounted) return;
        setState(() {
          _students = visibleStudents;
          if (_slots.isEmpty) _slots.add(_SlotDraft());
        });
        if (widget.reportId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_offerRestoreDraft()));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Не удалось открыть конструктор: $e'), backgroundColor: Colors.red),
      );
      if (_slots.isEmpty) _slots.add(_SlotDraft());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    unawaited(_persistDraftSafe());
    _dateController.dispose();
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _persistDraftSafe() async {
    if (!mounted || widget.reportId != null) return;
    final uid = _userId ?? (await StorageService.getUserData())?['id'];
    if (uid == null) return;
    final map = _serializeDraft();
    if (map == null) return;
    await ReportBuilderDraftStorage.save(uid, map);
  }

  Map<String, dynamic>? _serializeDraft() {
    var any = false;
    final slots = <Map<String, dynamic>>[];
    for (final s in _slots) {
      if (s.startController.text.trim().isNotEmpty || s.studentIds.any((id) => id != null)) any = true;
      final row = <String, dynamic>{
        'start': s.startController.text,
        'duration': s.durationMinutes,
      };
      for (int childIndex = 0; childIndex < _maxStudentsPerSlot; childIndex++) {
        final n = childIndex + 1;
        row['s$n'] = s.studentIds[childIndex];
        row['p$n'] = s.priceControllers[childIndex].text;
        row['st$n'] = s.statuses[childIndex];
      }
      slots.add(row);
    }
    if (!any) return null;
    return {
      'version': 1,
      'reportDate': _selectedDate.toIso8601String(),
      'slots': slots,
    };
  }

  Future<void> _offerRestoreDraft() async {
    if (widget.reportId != null || !mounted) return;
    final uid = _userId ?? (await StorageService.getUserData())?['id'];
    if (uid == null) return;
    _userId = uid;
    final draft = await ReportBuilderDraftStorage.load(uid);
    if (draft == null || !mounted) return;
    if (draft['version'] != 1) return;
    final slotsRaw = draft['slots'];
    if (slotsRaw is! List || slotsRaw.isEmpty) return;

    final want = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Восстановить черновик?'),
        content: const Text('Найден несохранённый черновик отчёта на этом устройстве.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Восстановить')),
        ],
      ),
    );
    if (want != true || !mounted) return;

    for (final s in _slots) {
      s.dispose();
    }
    _slots.clear();

    final dateStr = draft['reportDate']?.toString();
    if (dateStr != null) {
      final d = DateTime.tryParse(dateStr);
      if (d != null) {
        _selectedDate = DateTime(d.year, d.month, d.day);
        _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
      }
    }

    for (final row in slotsRaw) {
      if (row is! Map) continue;
      final slot = _SlotDraft();
      slot.startController.text = row['start']?.toString() ?? '';
      slot.durationMinutes = row['duration'] is int ? row['duration'] as int : int.tryParse(row['duration']?.toString() ?? '') ?? 60;
      for (int childIndex = 0; childIndex < _maxStudentsPerSlot; childIndex++) {
        final n = childIndex + 1;
        slot.studentIds[childIndex] = row['s$n'] == null ? null : int.tryParse(row['s$n'].toString());
        slot.priceControllers[childIndex].text = row['p$n']?.toString() ?? '';
        slot.statuses[childIndex] = row['st$n']?.toString() ?? 'attended';
      }
      _slots.add(slot);
    }
    if (_slots.isEmpty) _slots.add(_SlotDraft());
    setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _dateController.text = DateFormat('dd.MM.yyyy').format(picked);
    });
    unawaited(_persistDraftSafe());
  }

  void _addSlot() {
    if (_slots.length >= _maxSlots) return;
    setState(() {
      _slots.add(_SlotDraft());
    });
  }

  void _removeSlot(int index) {
    if (index < 0 || index >= _slots.length) return;
    setState(() {
      final s = _slots.removeAt(index);
      s.dispose();
    });
  }

  String? _validateTime(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Время обязательно';
    final re = RegExp(r'^([01]?\d|2[0-3]):[0-5][0-9]$');
    if (!re.hasMatch(v)) return 'Формат ЧЧ:ММ';
    return null;
  }

  int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _minutesToHHMM(int mins) {
    final m = mins.clamp(0, 23 * 60 + 59);
    final hh = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _computeEndTimeHHMM(String start, int durationMinutes) {
    try {
      final a = _toMinutes(start);
      return _minutesToHHMM(a + durationMinutes);
    } catch (_) {
      return '';
    }
  }

  double? _parsePrice(String raw) {
    final v = raw.trim().replaceAll(',', '.');
    return double.tryParse(v);
  }

  Future<void> _prefillLastPriceForStudent({
    required TextEditingController controller,
    required int? studentId,
    required bool Function() isStillSameSelection,
  }) async {
    if (studentId == null) return;
    if (controller.text.trim().isNotEmpty) return;

    final cached = _lastPriceByStudent[studentId];
    if (cached != null && cached > 0) {
      controller.text = cached.toStringAsFixed(0);
      return;
    }

    try {
      final lessons = await _studentsService.getStudentLessonsMine(studentId);
      if (!mounted) return;
      // В бэкенде сортировка DESC, значит [0] — последнее занятие
      if (lessons.isEmpty) return;
      final last = lessons.first;
      final price = last.price;
      if (price <= 0) return;
      // Не перетираем, если выбор уже изменился или пользователь успел ввести
      if (!isStillSameSelection()) return;
      if (controller.text.trim().isNotEmpty) return;
      _lastPriceByStudent[studentId] = price;
      controller.text = price.toStringAsFixed(0);
    } catch (_) {
      // если не удалось — просто оставим пусто
    }
  }

  List<String> _priceWarningsForBuilt(List<ReportStructuredSlot> built) {
    final ref = Map<int, double>.from(_lastPriceByStudent);
    final w = <String>[];
    for (final sl in built) {
      for (final st in sl.students) {
        final prev = ref[st.studentId];
        if (prev != null && prev > 0 && st.price > 0) {
          final ratio = st.price / prev;
          if (ratio > 1.35 || ratio < 0.65) {
            w.add(
              'Ученик #${st.studentId}: ${st.price.toStringAsFixed(0)} ₽ заметно отличается от последней цены (${prev.toStringAsFixed(0)} ₽).',
            );
          }
        }
        ref[st.studentId] = st.price;
      }
    }
    return w;
  }

  List<ReportStructuredSlot>? _buildStructuredSlotsOrNull() {
    if (_slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Добавьте хотя бы одно занятие'), backgroundColor: Colors.orange),
      );
      return null;
    }
    if (_slots.length > _maxSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Максимум $_maxSlots занятий в день'), backgroundColor: Colors.orange),
      );
      return null;
    }

    final out = <ReportStructuredSlot>[];

    for (int i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      final start = slot.startController.text.trim();
      final end = _computeEndTimeHHMM(start, slot.durationMinutes);

      final startErr = _validateTime(start);
      final endErr = _validateTime(end);
      if (startErr != null || endErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Слот ${i + 1}: проверьте время'), backgroundColor: Colors.orange),
        );
        return null;
      }

      if (_toMinutes(end) <= _toMinutes(start)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Слот ${i + 1}: конец должен быть позже начала'), backgroundColor: Colors.orange),
        );
        return null;
      }

      if (slot.studentIds[0] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Слот ${i + 1}: выберите ученика 1'), backgroundColor: Colors.orange),
        );
        return null;
      }

      final selectedStudentIds = <int>{};
      final rowStudents = <ReportStructuredStudent>[];
      for (int childIndex = 0; childIndex < _maxStudentsPerSlot; childIndex++) {
        final studentId = slot.studentIds[childIndex];
        if (studentId == null) continue;

        if (!selectedStudentIds.add(studentId)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(seconds: 3), content: Text('Слот ${i + 1}: дети должны быть разными'), backgroundColor: Colors.orange),
          );
          return null;
        }

        final price = _parsePrice(slot.priceControllers[childIndex].text);
        if (price == null || price <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text('Слот ${i + 1}: укажите цену для ${childIndex + 1} ребёнка'),
              backgroundColor: Colors.orange,
            ),
          );
          return null;
        }

        rowStudents.add(
          ReportStructuredStudent(
            studentId: studentId,
            price: price,
            status: slot.statuses[childIndex],
          ),
        );
      }

      if (rowStudents.length > _maxStudentsPerSlot) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Слот ${i + 1}: максимум $_maxStudentsPerSlot ученика'), backgroundColor: Colors.orange),
        );
        return null;
      }

      out.add(ReportStructuredSlot(timeStart: start, timeEnd: end, students: rowStudents));
    }

    return out;
  }

  Future<void> _save() async {
    final built = _buildStructuredSlotsOrNull();
    if (built == null) return;

    final warnings = _priceWarningsForBuilt(built);
    if (warnings.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Проверьте цены'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Обнаружены сильные отличия от последних цен по ученикам:'),
                const SizedBox(height: 8),
                ...warnings.map((s) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $s'))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Исправить')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Всё верно, сохранить')),
          ],
        ),
      );
      if (ok != true) return;
    }

    final slotsPayload = built.map((e) => e.toJson()).toList();

    setState(() => _isLoading = true);
    try {
      if (widget.reportId == null) {
        await _reportsService.createReportStructured(
          reportDate: _selectedDate,
          slots: slotsPayload,
        );
      } else {
        await _reportsService.updateReportStructured(
          id: widget.reportId!,
          reportDate: _selectedDate,
          slots: slotsPayload,
        );
      }
      final uid = _userId ?? (await StorageService.getUserData())?['id'];
      if (uid != null) await ReportBuilderDraftStorage.clear(uid);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(widget.reportId == null ? 'Отчет создан' : 'Отчет обновлен'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(_reportSaveErrorText(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportId == null ? 'Новый отчет' : 'Редактирование отчета'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _save,
            icon: const Icon(Icons.save),
            tooltip: 'Сохранить',
          ),
        ],
      ),
      body: _isLoading && _students.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Дата *',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_dateController.text),
                        const Icon(Icons.calendar_today),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_students.isEmpty)
                  const Text('Нет доступных учеников. Добавьте учеников в “Учет занятий”.'),
                const SizedBox(height: 8),
                ...List.generate(_slots.length, (index) {
                  final slot = _slots[index];
                  final startText = slot.startController.text.trim();
                  final computedEnd = _validateTime(startText) == null
                      ? _computeEndTimeHHMM(startText, slot.durationMinutes)
                      : '';
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
                                  'Занятие ${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (_slots.length > 1)
                                IconButton(
                                  onPressed: _isLoading ? null : () => _removeSlot(index),
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  tooltip: 'Удалить',
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: slot.startController,
                            decoration: InputDecoration(
                              labelText: 'Время начала (ЧЧ:ММ) *',
                              border: const OutlineInputBorder(),
                              helperText: computedEnd.isEmpty ? null : 'Конец: $computedEnd',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [_TimeTextInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),

                          Text(
                            'Длительность',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final m in const [60, 90, 120, 180])
                                ChoiceChip(
                                  label: Text('$m мин'),
                                  selected: slot.durationMinutes == m,
                                  onSelected: _isLoading
                                      ? null
                                      : (v) {
                                          if (!v) return;
                                          setState(() => slot.durationMinutes = m);
                                        },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          for (int childIndex = 0; childIndex < _maxStudentsPerSlot; childIndex++) ...[
                            if (childIndex > 0) const SizedBox(height: 10),
                            _StudentPickerRow(
                              label: childIndex == 0
                                  ? 'Ребёнок 1 *'
                                  : 'Ребёнок ${childIndex + 1} (опционально)',
                              students: _students,
                              value: slot.studentIds[childIndex],
                              allowEmpty: childIndex > 0,
                              onChanged: (v) async {
                                setState(() {
                                  slot.studentIds[childIndex] = v;
                                  slot.priceControllers[childIndex].text = '';
                                  slot.statuses[childIndex] = 'attended';
                                });
                                if (v == null) return;
                                await _prefillLastPriceForStudent(
                                  controller: slot.priceControllers[childIndex],
                                  studentId: v,
                                  isStillSameSelection: () => slot.studentIds[childIndex] == v,
                                );
                                if (!mounted) return;
                                setState(() {});
                              },
                              priceController: slot.priceControllers[childIndex],
                              status: slot.statuses[childIndex],
                              onStatusChanged: (v) => setState(() => slot.statuses[childIndex] = v),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: (_isLoading || _slots.length >= _maxSlots) ? null : _addSlot,
                  icon: const Icon(Icons.add),
                  label: Text('Добавить занятие (${_slots.length}/$_maxSlots)'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Правила: до 10 занятий в день; на одно время — от 1 до 4 детей.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.55),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StudentPickerRow extends StatefulWidget {
  final String label;
  final List<Student> students;
  final int? value;
  final ValueChanged<int?> onChanged;
  final TextEditingController priceController;
  final bool allowEmpty;
  final String status;
  final ValueChanged<String> onStatusChanged;

  const _StudentPickerRow({
    required this.label,
    required this.students,
    required this.value,
    required this.onChanged,
    required this.priceController,
    required this.status,
    required this.onStatusChanged,
    this.allowEmpty = false,
  });

  @override
  State<_StudentPickerRow> createState() => _StudentPickerRowState();
}

class _StudentPickerRowState extends State<_StudentPickerRow> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Student> get _filteredStudents {
    final q = _searchController.text.trim().toLowerCase();
    List<Student> list = q.isEmpty
        ? List<Student>.from(widget.students)
        : widget.students.where((s) => s.name.toLowerCase().contains(q)).toList();
    if (widget.value != null && !list.any((s) => s.id == widget.value)) {
      final selected = widget.students.where((s) => s.id == widget.value).toList();
      if (selected.isNotEmpty) list = [selected.first, ...list];
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStudents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          decoration: const InputDecoration(
            labelText: 'Поиск ученика',
            hintText: 'Введите имя...',
            prefixIcon: Icon(Icons.search_rounded, size: 22),
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int?>(
                key: ValueKey<int?>(widget.value),
                initialValue: widget.value,
                items: [
                  if (widget.allowEmpty)
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('—'),
                    ),
                  ...filtered.map(
                    (s) => DropdownMenuItem<int?>(
                      value: s.id,
                      child: Text(s.name),
                    ),
                  ),
                  if (filtered.isEmpty && widget.students.isNotEmpty)
                    const DropdownMenuItem<int?>(
                      value: -1,
                      enabled: false,
                      child: Text('Нет совпадений'),
                    ),
                ],
                onChanged: (v) {
                  if (v == null || v != -1) widget.onChanged(v);
                },
                decoration: InputDecoration(
                  labelText: widget.label,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: widget.priceController,
                decoration: const InputDecoration(
                  labelText: 'Цена (₽)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: widget.status,
          items: const [
            DropdownMenuItem(value: 'attended', child: Text('Проведено')),
            DropdownMenuItem(value: 'missed', child: Text('Пропуск')),
            DropdownMenuItem(value: 'cancel_same_day', child: Text('Отмена в день')),
            DropdownMenuItem(value: 'makeup', child: Text('Отработка')),
          ],
          onChanged: (v) {
            if (v == null) return;
            widget.onStatusChanged(v);
          },
          decoration: const InputDecoration(
            labelText: 'Статус',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final digitsOnly = text.replaceAll(RegExp(r'[^\d:]'), '');
    if (digitsOnly.isEmpty) return newValue.copyWith(text: '');

    if (!digitsOnly.contains(':')) {
      if (digitsOnly.length <= 2) return newValue.copyWith(text: digitsOnly);
      final h = digitsOnly.substring(0, 2);
      final m = digitsOnly.substring(2, digitsOnly.length.clamp(2, 4));
      final next = m.isEmpty ? h : '$h:$m';
      return newValue.copyWith(text: next, selection: TextSelection.collapsed(offset: next.length));
    }

    final parts = digitsOnly.split(':');
    String h = parts[0];
    String m = parts.length > 1 ? parts[1] : '';
    if (h.length > 2) h = h.substring(0, 2);
    if (m.length > 2) m = m.substring(0, 2);
    final hh = int.tryParse(h);
    if (hh != null && hh > 23) h = '23';
    final mm = int.tryParse(m);
    if (mm != null && mm > 59) m = '59';
    final next = m.isEmpty ? '$h:' : '$h:$m';
    return newValue.copyWith(text: next, selection: TextSelection.collapsed(offset: next.length));
  }
}

