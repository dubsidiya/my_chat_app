import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/report.dart';
import '../services/reports_service.dart';
import 'edit_report_screen.dart';

class ReportsChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  ReportsChatScreen({required this.userId, required this.userEmail});

  @override
  _ReportsChatScreenState createState() => _ReportsChatScreenState();
}

class _ReportsChatScreenState extends State<ReportsChatScreen> {
  final ReportsService _reportsService = ReportsService();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  List<Report> _reports = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
    _loadReports();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final reports = await _reportsService.getAllReports();
      if (mounted) {
        setState(() {
          _reports = reports;
        });
      }
    } catch (e) {
      print('Ошибка загрузки отчетов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при загрузке отчетов: $e'),
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

  Future<void> _createReport() async {
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
      final report = await _reportsService.createReport(
        reportDate: _selectedDate,
        content: content,
      );

      if (mounted) {
        _contentController.clear();
        _loadReports();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Отчет создан! Создано занятий: ${report.lessonsCount ?? 0}',
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

  Future<void> _editReport(Report report) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditReportScreen(report: report),
      ),
    );

    if (result == true) {
      _loadReports();
    }
  }

  Future<void> _deleteReport(Report report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить отчет?'),
        content: Text(
          'Это удалит отчет и все связанные занятия. Действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await _reportsService.deleteReport(report.id);
      _loadReports();
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
        title: Text('Отчеты за день'),
      ),
      body: Column(
        children: [
          // Поле ввода даты
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Дата отчета',
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
          ),

          // Поле ввода отчета
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    labelText: 'Содержание отчета',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 10,
                  minLines: 5,
                ),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createReport,
                  icon: Icon(Icons.send),
                  label: Text('Создать отчет'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1),

          // Список отчетов
          Expanded(
            child: _isLoading && _reports.isEmpty
                ? Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Нет отчетов',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Создайте отчет за день',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        child: ListView.builder(
                          padding: EdgeInsets.all(8),
                          itemCount: _reports.length,
                          itemBuilder: (context, index) {
                            final report = _reports[index];
                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.description,
                                  color: report.isEdited ? Colors.orange : Colors.blue,
                                ),
                                title: Text(
                                  DateFormat('dd.MM.yyyy').format(report.reportDate),
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      report.content,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Занятий: ${report.lessonsCount ?? 0}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    if (report.isEdited)
                                      Text(
                                        'Отредактирован',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 20),
                                          SizedBox(width: 8),
                                          Text('Редактировать'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, size: 20, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Удалить', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editReport(report);
                                    } else if (value == 'delete') {
                                      _deleteReport(report);
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

