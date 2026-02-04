import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/report.dart';
import '../services/reports_service.dart';

class EditReportScreen extends StatefulWidget {
  final Report report;

  EditReportScreen({required this.report});

  @override
  _EditReportScreenState createState() => _EditReportScreenState();
}

class _EditReportScreenState extends State<EditReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _dateController = TextEditingController();
  final _reportsService = ReportsService();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _contentController.text = widget.report.content;
    _selectedDate = widget.report.reportDate;
    _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
  }

  @override
  void dispose() {
    _contentController.dispose();
    _dateController.dispose();
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
        _dateController.text = DateFormat('dd.MM.yyyy').format(picked);
      });
    }
  }

  Future<void> _updateReport() async {
    if (!_formKey.currentState!.validate()) return;

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Введите содержание отчета'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final report = await _reportsService.updateReport(
        id: widget.report.id,
        reportDate: _selectedDate,
        content: content,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Отчет обновлен! Создано занятий: ${report.lessonsCount ?? 0}',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('Редактировать отчет'),
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
                  labelText: 'Дата отчета *',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_dateController.text),
                    Icon(Icons.calendar_today),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Содержание
            TextFormField(
              controller: _contentController,
              decoration: InputDecoration(
                labelText: 'Содержание отчета *',
                border: OutlineInputBorder(),
                helperText: 'Формат: дата, затем время и ученики с ценами (2.0 = 2000₽)',
              ),
              maxLines: 15,
              minLines: 8,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите содержание отчета';
                }
                return null;
              },
            ),
            SizedBox(height: 24),

            // Предупреждение
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(isDark ? 0.50 : 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange.shade500),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'При сохранении старые занятия будут удалены и созданы новые на основе обновленного текста.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isLoading ? null : _updateReport,
              child: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                      ),
                    )
                  : Text('Сохранить изменения'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange.shade600,
                foregroundColor: scheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

