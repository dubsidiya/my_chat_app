import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../services/students_service.dart';
import '../services/reports_service.dart';

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
  final TextEditingController priceController = TextEditingController();

  int durationMinutes = 60;
  int? studentId;

  void dispose() {
    startController.dispose();
    priceController.dispose();
  }
}

class _ReportBuilderScreenState extends State<ReportBuilderScreen> {
  static const int _maxSlots = 10;

  final StudentsService _studentsService = StudentsService();
  final ReportsService _reportsService = ReportsService();

  final TextEditingController _dateController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  List<Student> _students = [];
  final List<_SlotDraft> _slots = [];
  final Map<int, double> _lastPriceByStudent = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
    _init();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      final students = await _studentsService.getAllStudents();

      // Если редактирование — грузим отчет и заполняем слоты
      if (widget.reportId != null) {
        final report = await _reportsService.getReport(widget.reportId!);
        final reportDate = report.reportDate;

        final lessons = report.lessons ?? const [];
        final slotDrafts = <_SlotDraft>[];
        for (final l in lessons) {
          final timeRaw = (l['lesson_time'] ?? '').toString();
          final start = timeRaw.length >= 5 ? timeRaw.substring(0, 5) : timeRaw;
          final duration = (l['duration_minutes'] ?? 60) is int
              ? (l['duration_minutes'] as int)
              : int.tryParse(l['duration_minutes'].toString()) ?? 60;

          final slot = _SlotDraft();
          slot.startController.text = start;
          slot.durationMinutes = duration;
          slot.studentId = int.tryParse(l['student_id'].toString());

          final p = l['price'];
          slot.priceController.text = p is num ? p.toString() : (double.tryParse(p.toString())?.toString() ?? '');
          slotDrafts.add(slot);
        }

        // если слотов нет — оставим один пустой
        if (slotDrafts.isEmpty) {
          slotDrafts.add(_SlotDraft());
        }

        if (!mounted) return;
        setState(() {
          _students = students;
          _selectedDate = reportDate;
          _dateController.text = DateFormat('dd.MM.yyyy').format(reportDate);
          _slots.clear();
          _slots.addAll(slotDrafts.take(_maxSlots));
        });
      } else {
        if (!mounted) return;
        setState(() {
          _students = students;
          if (_slots.isEmpty) _slots.add(_SlotDraft());
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть конструктор: $e'), backgroundColor: Colors.red),
      );
      if (_slots.isEmpty) _slots.add(_SlotDraft());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
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
    required _SlotDraft slot,
    required int? studentId,
  }) async {
    if (studentId == null) return;
    if (slot.priceController.text.trim().isNotEmpty) return;

    final cached = _lastPriceByStudent[studentId];
    if (cached != null && cached > 0) {
      slot.priceController.text = cached.toStringAsFixed(0);
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
      // Не перетираем, если пользователь уже успел ввести
      if (slot.studentId != studentId) return;
      if (slot.priceController.text.trim().isNotEmpty) return;
      _lastPriceByStudent[studentId] = price;
      slot.priceController.text = price.toStringAsFixed(0);
    } catch (_) {
      // если не удалось — просто оставим пусто
    }
  }

  Future<void> _save() async {
    // локальная валидация
    if (_slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одно занятие'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (_slots.length > _maxSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Максимум $_maxSlots занятий в день'), backgroundColor: Colors.orange),
      );
      return;
    }

    final slotsPayload = <Map<String, dynamic>>[];

    for (int i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      final start = slot.startController.text.trim();
      final end = _computeEndTimeHHMM(start, slot.durationMinutes);

      final startErr = _validateTime(start);
      final endErr = _validateTime(end);
      if (startErr != null || endErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: проверьте время'), backgroundColor: Colors.orange),
        );
        return;
      }

      if (_toMinutes(end) <= _toMinutes(start)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: конец должен быть позже начала'), backgroundColor: Colors.orange),
        );
        return;
      }

      if (slot.studentId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: выберите ученика'), backgroundColor: Colors.orange),
        );
        return;
      }

      final p = _parsePrice(slot.priceController.text);
      if (p == null || p <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: укажите цену'), backgroundColor: Colors.orange),
        );
        return;
      }

      // Кэшируем последнюю цену по ребенку (на время сессии конструктора)
      _lastPriceByStudent[slot.studentId!] = p;

      slotsPayload.add({
        'timeStart': start,
        'timeEnd': end,
        'students': [
          {'studentId': slot.studentId, 'price': p},
        ],
      });
    }

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
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.reportId == null ? 'Отчет создан' : 'Отчет обновлен'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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
                              for (final m in const [60, 90, 120])
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

                          _StudentPickerRow(
                            label: 'Ребёнок *',
                            students: _students,
                            value: slot.studentId,
                            onChanged: (v) async {
                              setState(() => slot.studentId = v);
                              await _prefillLastPriceForStudent(slot: slot, studentId: v);
                              if (!mounted) return;
                              setState(() {});
                            },
                            priceController: slot.priceController,
                          ),
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
                  'Правила: до 10 занятий в день; одно занятие = один ребёнок.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha:0.55),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StudentPickerRow extends StatelessWidget {
  final String label;
  final List<Student> students;
  final int? value;
  final ValueChanged<int?> onChanged;
  final TextEditingController priceController;

  const _StudentPickerRow({
    required this.label,
    required this.students,
    required this.value,
    required this.onChanged,
    required this.priceController,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            key: ValueKey<int?>(value),
            initialValue: value,
            items: [
              ...students.map(
                (s) => DropdownMenuItem<int>(
                  value: s.id,
                  child: Text(s.name),
                ),
              ),
            ],
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: priceController,
            decoration: const InputDecoration(
              labelText: 'Цена (₽)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
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

