import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/report.dart';
import '../services/reports_service.dart';
import 'edit_report_screen.dart';
import 'report_builder_screen.dart';

class ReportsChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  ReportsChatScreen({required this.userId, required this.userEmail});

  @override
  _ReportsChatScreenState createState() => _ReportsChatScreenState();
}

class _ReportsChatScreenState extends State<ReportsChatScreen> {
  final ReportsService _reportsService = ReportsService();
  final TextEditingController _dateController = TextEditingController();
  List<Report> _reports = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();
  
  static const Color _accent1 = Color(0xFF667eea);
  static const Color _accent2 = Color.fromARGB(255, 124, 79, 168);

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('dd.MM.yyyy').format(_selectedDate);
    _loadReports();
  }

  @override
  void dispose() {
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

  Future<void> _openBuilder() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportBuilderScreen(initialDate: _selectedDate),
      ),
    );
    if (result == true) {
      _loadReports();
    }
  }

  Future<void> _openBuilderEdit(int reportId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportBuilderScreen(reportId: reportId),
      ),
    );
    if (result == true) {
      _loadReports();
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Отчеты за день',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.add_rounded, color: _accent1),
              onPressed: _openBuilder,
              tooltip: 'Новый отчет',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _accent1.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: _accent1),
              onPressed: _loadReports,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Поле ввода даты
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Card(
              elevation: 2,
              shadowColor: Colors.black.withOpacity(0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [_accent1, _accent2]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: _accent1.withOpacity(0.25),
                              blurRadius: 10,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(Icons.calendar_today_rounded, color: Colors.white),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Дата отчета',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              _dateController.text,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Поле ввода отчета
          Container(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 2,
                  shadowColor: Colors.black.withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(colors: [_accent1, _accent2]),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent1.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _openBuilder,
                              icon: Icon(Icons.playlist_add_check_rounded),
                              label: Text(
                                'Сформировать отчет',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1),

          // Список отчетов
          Expanded(
            child: _isLoading && _reports.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                      strokeWidth: 3,
                    ),
                  )
                : _reports.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _accent1.withOpacity(0.2),
                                      _accent2.withOpacity(0.2),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.description_rounded,
                                  size: 60,
                                  color: _accent1.withOpacity(0.7),
                                ),
                              ),
                              SizedBox(height: 28),
                              Text(
                                'Нет отчетов',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Создайте отчет за день — занятия сформируются автоматически',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadReports,
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          itemCount: _reports.length,
                          itemBuilder: (context, index) {
                            final report = _reports[index];
                            return Card(
                              margin: EdgeInsets.symmetric(vertical: 6),
                              elevation: 2,
                              shadowColor: Colors.black.withOpacity(0.08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: report.isEdited
                                          ? [Colors.orange.shade400, Colors.orange.shade700]
                                          : [_accent1, _accent2],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (report.isEdited ? Colors.orange : _accent1)
                                            .withOpacity(0.25),
                                        blurRadius: 10,
                                        offset: Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.description_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  DateFormat('dd.MM.yyyy').format(report.reportDate),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 6),
                                    Text(
                                      report.content,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.grey.shade700),
                                    ),
                                    SizedBox(height: 4),
                                    if (report.isLate)
                                      Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Поздний отчет',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (report.isEdited)
                                      Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Отредактирован',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.orange.shade700,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Container(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _accent1.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Занятий: ${report.lessonsCount ?? 0}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _accent1,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _accent1.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Занятий: ${report.lessonsCount ?? 0}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _accent1,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_rounded, size: 20),
                                          SizedBox(width: 8),
                                          Text('Редактировать (конструктор)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit_text',
                                      child: Row(
                                        children: [
                                          Icon(Icons.text_snippet_outlined, size: 20),
                                          SizedBox(width: 8),
                                          Text('Редактировать (текст)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline_rounded,
                                              size: 20, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Удалить', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openBuilderEdit(report.id);
                                    } else if (value == 'edit_text') {
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

