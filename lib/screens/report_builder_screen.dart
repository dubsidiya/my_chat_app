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
  State<ReportBuilderScreen> createState() => _ReportBuilderScreenState();
}

class _SlotDraft {
  final TextEditingController startController = TextEditingController();
  final TextEditingController endController = TextEditingController();
  final TextEditingController price1Controller = TextEditingController();
  final TextEditingController price2Controller = TextEditingController();

  int? student1Id;
  int? student2Id;

  void dispose() {
    startController.dispose();
    endController.dispose();
    price1Controller.dispose();
    price2Controller.dispose();
  }
}

class _ReportBuilderScreenState extends State<ReportBuilderScreen> {
  static const int _maxSlots = 10;
  static const int _maxStudentsPerSlot = 2;

  final StudentsService _studentsService = StudentsService();
  final ReportsService _reportsService = ReportsService();

  final TextEditingController _dateController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  List<Student> _students = [];
  final List<_SlotDraft> _slots = [];

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
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final l in lessons) {
          final timeRaw = (l['lesson_time'] ?? '').toString();
          final time = timeRaw.length >= 5 ? timeRaw.substring(0, 5) : timeRaw;
          final duration = (l['duration_minutes'] ?? 60) is int
              ? (l['duration_minutes'] as int)
              : int.tryParse(l['duration_minutes'].toString()) ?? 60;
          final key = '$time|$duration';
          grouped.putIfAbsent(key, () => []).add(l);
        }

        final slotDrafts = <_SlotDraft>[];
        for (final entry in grouped.entries) {
          final parts = entry.key.split('|');
          final start = parts[0];
          final duration = int.tryParse(parts[1]) ?? 60;
          final endMinutes = _toMinutes(start) + duration;
          final endH = (endMinutes ~/ 60).clamp(0, 23).toString().padLeft(2, '0');
          final endM = (endMinutes % 60).clamp(0, 59).toString().padLeft(2, '0');
          final end = '$endH:$endM';

          final slot = _SlotDraft();
          slot.startController.text = start;
          slot.endController.text = end;

          final items = entry.value;
          // максимум 2 ученика на слот
          if (items.isNotEmpty) {
            final sid1 = int.tryParse(items[0]['student_id'].toString());
            slot.student1Id = sid1;
            final p1 = items[0]['price'];
            slot.price1Controller.text = p1 is num ? p1.toString() : (double.tryParse(p1.toString())?.toString() ?? '');
          }
          if (items.length > 1) {
            final sid2 = int.tryParse(items[1]['student_id'].toString());
            slot.student2Id = sid2;
            final p2 = items[1]['price'];
            slot.price2Controller.text = p2 is num ? p2.toString() : (double.tryParse(p2.toString())?.toString() ?? '');
          }
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

  double? _parsePrice(String raw) {
    final v = raw.trim().replaceAll(',', '.');
    return double.tryParse(v);
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
        SnackBar(content: Text('Максимум $_maxSlots занятий в день'), backgroundColor: Colors.orange),
      );
      return;
    }

    final slotsPayload = <Map<String, dynamic>>[];

    for (int i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      final start = slot.startController.text.trim();
      final end = slot.endController.text.trim();

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

      final students = <Map<String, dynamic>>[];
      if (slot.student1Id != null) {
        final p = _parsePrice(slot.price1Controller.text);
        if (p == null || p <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Слот ${i + 1}: укажите цену для 1 ученика'), backgroundColor: Colors.orange),
          );
          return;
        }
        students.add({'studentId': slot.student1Id, 'price': p});
      }
      if (slot.student2Id != null) {
        final p = _parsePrice(slot.price2Controller.text);
        if (p == null || p <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Слот ${i + 1}: укажите цену для 2 ученика'), backgroundColor: Colors.orange),
          );
          return;
        }
        students.add({'studentId': slot.student2Id, 'price': p});
      }

      if (students.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: выберите ученика'), backgroundColor: Colors.orange),
        );
        return;
      }
      if (students.length > _maxStudentsPerSlot) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: максимум $_maxStudentsPerSlot ученика'), backgroundColor: Colors.orange),
        );
        return;
      }
      if (students.length == 2 && students[0]['studentId'] == students[1]['studentId']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Слот ${i + 1}: ученики должны быть разными'), backgroundColor: Colors.orange),
        );
        return;
      }

      slotsPayload.add({
        'timeStart': start,
        'timeEnd': end,
        'students': students,
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
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: slot.startController,
                                  decoration: const InputDecoration(
                                    labelText: 'Начало (ЧЧ:ММ)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [_TimeTextInputFormatter()],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: slot.endController,
                                  decoration: const InputDecoration(
                                    labelText: 'Конец (ЧЧ:ММ)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [_TimeTextInputFormatter()],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _StudentPickerRow(
                            label: 'Ученик 1 *',
                            students: _students,
                            value: slot.student1Id,
                            onChanged: (v) => setState(() => slot.student1Id = v),
                            priceController: slot.price1Controller,
                          ),
                          const SizedBox(height: 10),
                          _StudentPickerRow(
                            label: 'Ученик 2 (опционально)',
                            students: _students,
                            value: slot.student2Id,
                            onChanged: (v) => setState(() => slot.student2Id = v),
                            priceController: slot.price2Controller,
                            allowEmpty: true,
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
                const Text(
                  'Правила: до 10 занятий в день; на одно время — 1 или 2 ученика.',
                  style: TextStyle(color: Colors.grey),
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
  final bool allowEmpty;

  const _StudentPickerRow({
    required this.label,
    required this.students,
    required this.value,
    required this.onChanged,
    required this.priceController,
    this.allowEmpty = false,
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
              if (allowEmpty)
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('—'),
                ),
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

