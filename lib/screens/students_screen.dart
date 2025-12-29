import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/students_service.dart';
import 'student_detail_screen.dart';
import 'add_student_screen.dart';
import 'bank_statement_screen.dart';

class StudentsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  StudentsScreen({required this.userId, required this.userEmail});

  @override
  _StudentsScreenState createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final StudentsService _studentsService = StudentsService();
  List<Student> _students = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final students = await _studentsService.getAllStudents();
      if (mounted) {
        setState(() {
          _students = students;
        });
      }
    } catch (e) {
      print('Ошибка загрузки студентов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при загрузке студентов: $e'),
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

  void _openStudentDetail(Student student) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailScreen(student: student),
      ),
    );

    if (result == true) {
      _loadStudents();
    }
  }

  void _addStudent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddStudentScreen(),
      ),
    );

    if (result == true) {
      _loadStudents();
    }
  }

  Future<void> _deleteStudent(Student student) async {
    try {
      await _studentsService.deleteStudent(student.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ученик "${student.name}" удален'),
            backgroundColor: Colors.green,
          ),
        );
        _loadStudents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Учет занятий'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Нет студентов',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Нажмите + чтобы добавить',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStudents,
                  child: ListView.builder(
                    itemCount: _students.length,
                    padding: EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      return Dismissible(
                        key: Key('student_${student.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Удалить ученика?'),
                              content: Text(
                                'Вы уверены, что хотите удалить "${student.name}"?\n\n'
                                'Это действие удалит все связанные данные:\n'
                                '• Все занятия\n'
                                '• Все транзакции\n'
                                '• Историю баланса\n\n'
                                'Это действие нельзя отменить!',
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
                          if (result == true) {
                            await _deleteStudent(student);
                          }
                          return result ?? false;
                        },
                        child: Card(
                        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: student.isDebtor
                                ? Colors.red
                                : Colors.blue,
                            child: Icon(
                              Icons.person,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            student.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: student.parentName != null
                              ? Text(student.parentName!)
                              : null,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${student.balance.toStringAsFixed(0)} ₽',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: student.isDebtor
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                              if (student.isDebtor)
                                Text(
                                  'Долг',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _openStudentDetail(student),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "upload",
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BankStatementScreen(onSuccess: _loadStudents),
                ),
              );
              if (result == true) {
                _loadStudents();
              }
            },
            child: Icon(Icons.upload_file),
            backgroundColor: Colors.green,
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "add",
            onPressed: _addStudent,
            child: Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

