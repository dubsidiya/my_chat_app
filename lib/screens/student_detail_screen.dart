import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../models/lesson.dart';
import '../services/students_service.dart';
import 'add_lesson_screen.dart';
import 'deposit_screen.dart';

class StudentDetailScreen extends StatefulWidget {
  final Student student;

  StudentDetailScreen({required this.student});

  @override
  _StudentDetailScreenState createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final StudentsService _studentsService = StudentsService();
  List<Lesson> _lessons = [];
  double _balance = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _balance = widget.student.balance;
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final lessons = await _studentsService.getStudentLessons(widget.student.id);
      if (mounted) {
        setState(() {
          _lessons = lessons;
        });
      }
    } catch (e) {
      print('Ошибка загрузки данных: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _addLesson() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddLessonScreen(studentId: widget.student.id),
      ),
    );

    if (result == true) {
      _loadData();
      // Обновляем баланс
      final students = await _studentsService.getAllStudents();
      final updatedStudent = students.firstWhere(
        (s) => s.id == widget.student.id,
      );
      setState(() {
        _balance = updatedStudent.balance;
      });
    }
  }

  void _deposit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DepositScreen(studentId: widget.student.id),
      ),
    );

    if (result == true) {
      _loadData();
      // Обновляем баланс
      final students = await _studentsService.getAllStudents();
      final updatedStudent = students.firstWhere(
        (s) => s.id == widget.student.id,
      );
      setState(() {
        _balance = updatedStudent.balance;
      });
    }
  }

  Future<void> _deleteLesson(Lesson lesson) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить занятие?'),
        content: Text('Это действие нельзя отменить'),
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

    try {
      await _studentsService.deleteLesson(lesson.id);
      _loadData();
      // Обновляем баланс
      final students = await _studentsService.getAllStudents();
      final updatedStudent = students.firstWhere(
        (s) => s.id == widget.student.id,
      );
      setState(() {
        _balance = updatedStudent.balance;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebtor = _balance < 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.student.name),
      ),
      body: Column(
        children: [
          // Карточка с балансом
          Container(
            width: double.infinity,
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDebtor ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDebtor ? Colors.red : Colors.green,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Баланс',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '${_balance.toStringAsFixed(0)} ₽',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDebtor ? Colors.red : Colors.green,
                  ),
                ),
                if (isDebtor)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Долг',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Информация о студенте
          if (widget.student.parentName != null ||
              widget.student.phone != null ||
              widget.student.email != null)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.student.parentName != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.person_outline, size: 16),
                          SizedBox(width: 8),
                          Text('Родитель: ${widget.student.parentName}'),
                        ],
                      ),
                    ),
                  if (widget.student.phone != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.phone, size: 16),
                          SizedBox(width: 8),
                          Text(widget.student.phone!),
                        ],
                      ),
                    ),
                  if (widget.student.email != null)
                    Row(
                      children: [
                        Icon(Icons.email, size: 16),
                        SizedBox(width: 8),
                        Text(widget.student.email!),
                      ],
                    ),
                ],
              ),
            ),

          SizedBox(height: 16),

          // Кнопки действий
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _deposit,
                    icon: Icon(Icons.add),
                    label: Text('Пополнить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addLesson,
                    icon: Icon(Icons.event),
                    label: Text('Добавить занятие'),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Список занятий
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _lessons.isEmpty
                    ? Center(
                        child: Text(
                          'Нет занятий',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _lessons.length,
                        itemBuilder: (context, index) {
                          final lesson = _lessons[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(Icons.event),
                              title: Text(
                                DateFormat('dd.MM.yyyy')
                                    .format(lesson.lessonDate),
                              ),
                              subtitle: lesson.lessonTime != null
                                  ? Text('Время: ${lesson.lessonTime}')
                                  : null,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${lesson.price.toStringAsFixed(0)} ₽',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteLesson(lesson),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

