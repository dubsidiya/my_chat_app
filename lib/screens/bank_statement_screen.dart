import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../services/students_service.dart';

class BankStatementScreen extends StatefulWidget {
  final Function()? onSuccess;

  BankStatementScreen({this.onSuccess});

  @override
  _BankStatementScreenState createState() => _BankStatementScreenState();
}

class _BankStatementScreenState extends State<BankStatementScreen> {
  final StudentsService _studentsService = StudentsService();
  bool _isLoading = false;
  Map<String, dynamic>? _previewData;
  List<Map<String, dynamic>> _selectedPayments = [];

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result != null && result.files.single.bytes != null) {
        await _processFile(result.files.single.bytes!, result.files.single.name);
      } else if (result != null && result.files.single.path != null) {
        // Для мобильных платформ
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        await _processFile(bytes, result.files.single.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _processFile(List<int> bytes, String fileName) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _previewData = null;
      _selectedPayments = [];
    });

    try {
      final result = await _studentsService.uploadBankStatement(bytes, fileName);
      
      if (mounted) {
        setState(() {
          _previewData = result;
          // Автоматически выбираем все платежи с найденными студентами
          _selectedPayments = (result['processedPayments'] as List?)
              ?.where((p) => p['student'] != null)
              .map((p) => {
                return {
                  'studentId': p['student']['id'],
                  'amount': p['amount'],
                  'date': p['date'],
                  'description': p['description'],
                };
              })
              .toList()
              .cast<Map<String, dynamic>>() ?? [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка обработки файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _applyPayments() async {
    if (_selectedPayments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выберите платежи для применения'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await _studentsService.applyPayments(_selectedPayments);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Успешно применено: ${result['success']}, ошибок: ${result['failed']}',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        if (widget.onSuccess != null) {
          widget.onSuccess!();
        }

        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка применения платежей: $e'),
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

  void _togglePayment(Map<String, dynamic> payment) {
    setState(() {
      if (payment['student'] == null) return; // Нельзя выбрать платеж без студента

      final paymentKey = '${payment['student']?['id']}_${payment['amount']}_${payment['date']}';
      final existingIndex = _selectedPayments.indexWhere(
        (p) => '${p['studentId']}_${p['amount']}_${p['date']}' == paymentKey,
      );

      if (existingIndex >= 0) {
        _selectedPayments.removeAt(existingIndex);
      } else {
        _selectedPayments.add({
          'studentId': payment['student']['id'],
          'amount': payment['amount'],
          'date': payment['date'],
          'description': payment['description'],
        });
      }
    });
  }

  bool _isPaymentSelected(Map<String, dynamic> payment) {
    if (payment['student'] == null) return false;
    
    final paymentKey = '${payment['student']?['id']}_${payment['amount']}_${payment['date']}';
    return _selectedPayments.any(
      (p) => '${p['studentId']}_${p['amount']}_${p['date']}' == paymentKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Загрузка банковской выписки'),
      ),
      body: _isLoading && _previewData == null
          ? Center(child: CircularProgressIndicator())
          : _previewData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Выберите файл выписки',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Поддерживаются форматы: CSV, Excel (.xlsx, .xls)',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: Icon(Icons.folder_open),
                        label: Text('Выбрать файл'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Информация о результатах
                    Container(
                      padding: EdgeInsets.all(16),
                      color: Colors.blue.shade50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Результаты обработки',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('Всего строк: ${_previewData!['totalRows']}'),
                          Text(
                            'Найдено платежей: ${_previewData!['processedPayments'].length}',
                          ),
                          Text(
                            'Ошибок: ${_previewData!['errors'].length}',
                            style: TextStyle(
                              color: _previewData!['errors'].length > 0
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Выбрано для применения: ${_selectedPayments.length}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Список платежей
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.all(8),
                        itemCount: _previewData!['processedPayments'].length,
                        itemBuilder: (context, index) {
                          final payment = _previewData!['processedPayments'][index];
                          final isSelected = _isPaymentSelected(payment);
                          final hasStudent = payment['student'] != null;

                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4),
                            color: hasStudent
                                ? (isSelected ? Colors.green.shade50 : Colors.white)
                                : Colors.orange.shade50,
                            child: CheckboxListTile(
                              value: isSelected,
                              onChanged: hasStudent
                                  ? (value) => _togglePayment(payment)
                                  : null,
                              title: Text(
                                payment['description'] ?? 'Без описания',
                                style: TextStyle(
                                  fontWeight: hasStudent ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (payment['student'] != null)
                                    Text(
                                      'Студент: ${payment['student']['name']}',
                                      style: TextStyle(color: Colors.green.shade700),
                                    )
                                  else
                                    Text(
                                      'Студент не найден',
                                      style: TextStyle(color: Colors.orange.shade700),
                                    ),
                                  SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        '${payment['amount'].toStringAsFixed(2)} ₽',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (payment['date'] != null) ...[
                                        SizedBox(width: 16),
                                        Text(
                                          'Дата: ${payment['date']}',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              secondary: Icon(
                                hasStudent
                                    ? (isSelected ? Icons.check_circle : Icons.person)
                                    : Icons.warning,
                                color: hasStudent
                                    ? (isSelected ? Colors.green : Colors.blue)
                                    : Colors.orange,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Кнопка применения
                    if (_selectedPayments.isNotEmpty)
                      Container(
                        padding: EdgeInsets.all(16),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _applyPayments,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.green,
                          ),
                          child: _isLoading
                              ? CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  'Применить ${_selectedPayments.length} платежей',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

