import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/students_service.dart';
import '../models/lesson.dart';

class AddLessonScreen extends StatefulWidget {
  final int studentId;

  const AddLessonScreen({super.key, required this.studentId});

  @override
  // ignore: library_private_types_in_public_api
  _AddLessonScreenState createState() => _AddLessonScreenState();
}

class _AddLessonScreenState extends State<AddLessonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  final _timeController = TextEditingController();
  final _studentsService = StudentsService();
  DateTime _selectedDate = DateTime.now();
  int _durationMinutes = 60;
  bool _isLoading = false;

  static const double _largeAmountWarn = 10000;
  static const double _maxAmount = 1000000;

  @override
  void dispose() {
    _priceController.dispose();
    _notesController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // Удаляем метод _selectTime, так как теперь время вводится вручную

  Future<void> _saveLesson() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final lesson = await _studentsService.createLesson(
        studentId: widget.studentId,
        lessonDate: _selectedDate,
        lessonTime: _timeController.text.isEmpty ? null : _timeController.text,
        durationMinutes: _durationMinutes,
        price: double.parse(_priceController.text),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      // Запомним последнюю цену для выбранной длительности
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('lesson_price_$_durationMinutes', double.parse(_priceController.text));
      } catch (_) {}

      if (mounted) {
        Navigator.pop<Lesson>(context, lesson);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить занятие'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Дата
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Дата занятия *',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('dd.MM.yyyy').format(_selectedDate),
                    ),
                    const Icon(Icons.calendar_today),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Время
            TextFormField(
              controller: _timeController,
              decoration: const InputDecoration(
                labelText: 'Время (опционально, формат: ЧЧ:ММ)',
                border: OutlineInputBorder(),
                hintText: 'Например: 14:30',
                prefixIcon: Icon(Icons.access_time),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                // Форматтер для времени ЧЧ:ММ
                _TimeTextInputFormatter(),
              ],
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  // Проверяем формат времени ЧЧ:ММ
                  final timeRegex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
                  if (!timeRegex.hasMatch(value)) {
                    return 'Введите время в формате ЧЧ:ММ (например: 14:30)';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Шаблоны длительности
            Text(
              'Длительность',
              style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [60, 90, 120])
                  ChoiceChip(
                    label: Text('$m мин'),
                    selected: _durationMinutes == m,
                    onSelected: _isLoading
                        ? null
                        : (v) async {
                            if (!v) return;
                            setState(() => _durationMinutes = m);
                            if (_priceController.text.trim().isNotEmpty) return;
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              final saved = prefs.getDouble('lesson_price_$m');
                              if (saved != null && saved > 0 && mounted) {
                                _priceController.text = saved.toStringAsFixed(0);
                              }
                            } catch (_) {}
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Цена
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Стоимость занятия (₽) *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите стоимость';
                }
                final price = double.tryParse(value);
                if (price == null || price <= 0) {
                  return 'Введите корректную стоимость';
                }
                if (price > _maxAmount) {
                  return 'Слишком большая сумма';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Заметки
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Заметки',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final raw = _priceController.text.trim();
                      final price = double.tryParse(raw);
                      if (price != null && price >= _largeAmountWarn) {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Подтвердить сумму?'),
                            content: Text('Стоимость занятия: ${price.toStringAsFixed(0)} ₽\n\nПродолжить?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Отмена'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Подтвердить'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                      }
                      await _saveLesson();
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                      ),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

// Форматтер для времени ЧЧ:ММ
class _TimeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    // Удаляем все символы кроме цифр и двоеточия
    final digitsOnly = text.replaceAll(RegExp(r'[^\d:]'), '');
    
    // Если пусто, возвращаем как есть
    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }
    
    // Если только цифры, форматируем
    if (!digitsOnly.contains(':')) {
      if (digitsOnly.length <= 2) {
        return newValue.copyWith(text: digitsOnly);
      } else if (digitsOnly.length == 3) {
        // Вставляем двоеточие после второй цифры
        return newValue.copyWith(
          text: '${digitsOnly.substring(0, 2)}:${digitsOnly.substring(2)}',
          selection: const TextSelection.collapsed(offset: 4),
        );
      } else {
        // Форматируем как ЧЧ:ММ
        final hours = digitsOnly.substring(0, 2);
        final minutes = digitsOnly.substring(2, 4);
        return newValue.copyWith(
          text: '$hours:$minutes',
          selection: const TextSelection.collapsed(offset: 5),
        );
      }
    }
    
    // Если уже есть двоеточие
    final parts = digitsOnly.split(':');
    if (parts.length == 1) {
      // Только часы
      if (parts[0].length <= 2) {
        return newValue.copyWith(text: parts[0]);
      } else {
        // Форматируем как ЧЧ:ММ
        return newValue.copyWith(
          text: '${parts[0].substring(0, 2)}:${parts[0].substring(2, 4)}',
          selection: const TextSelection.collapsed(offset: 5),
        );
      }
    } else {
      // Есть и часы и минуты
      String hours = parts[0];
      String minutes = parts[1];
      
      // Ограничиваем часы до 23
      if (hours.length > 2) {
        hours = hours.substring(0, 2);
      }
      if (int.tryParse(hours) != null && int.parse(hours) > 23) {
        hours = '23';
      }
      
      // Ограничиваем минуты до 59
      if (minutes.length > 2) {
        minutes = minutes.substring(0, 2);
      }
      if (int.tryParse(minutes) != null && int.parse(minutes) > 59) {
        minutes = '59';
      }
      
      return newValue.copyWith(
        text: '$hours:$minutes',
        selection: TextSelection.collapsed(offset: '$hours:$minutes'.length),
      );
    }
  }
}

