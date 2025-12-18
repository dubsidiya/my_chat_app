import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/students_service.dart';

class AddLessonScreen extends StatefulWidget {
  final int studentId;

  AddLessonScreen({required this.studentId});

  @override
  _AddLessonScreenState createState() => _AddLessonScreenState();
}

class _AddLessonScreenState extends State<AddLessonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  final _timeController = TextEditingController();
  final _studentsService = StudentsService();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

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
      await _studentsService.createLesson(
        studentId: widget.studentId,
        lessonDate: _selectedDate,
        lessonTime: _timeController.text.isEmpty ? null : _timeController.text,
        price: double.parse(_priceController.text),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Занятие добавлено'),
            backgroundColor: Colors.green,
          ),
        );
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Добавить занятие'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Дата
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Дата занятия *',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('dd.MM.yyyy').format(_selectedDate),
                    ),
                    Icon(Icons.calendar_today),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Время
            TextFormField(
              controller: _timeController,
              decoration: InputDecoration(
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
            SizedBox(height: 16),

            // Цена
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(
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
                return null;
              },
            ),
            SizedBox(height: 16),

            // Заметки
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Заметки',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isLoading ? null : _saveLesson,
              child: _isLoading
                  ? CircularProgressIndicator()
                  : Text('Сохранить'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
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
          selection: TextSelection.collapsed(offset: 4),
        );
      } else {
        // Форматируем как ЧЧ:ММ
        final hours = digitsOnly.substring(0, 2);
        final minutes = digitsOnly.substring(2, 4);
        return newValue.copyWith(
          text: '$hours:$minutes',
          selection: TextSelection.collapsed(offset: 5),
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
          selection: TextSelection.collapsed(offset: 5),
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

