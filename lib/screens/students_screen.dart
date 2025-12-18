import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/students_service.dart';
import 'student_detail_screen.dart';
import 'add_student_screen.dart';

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
                      return Card(
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
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addStudent,
        child: Icon(Icons.add),
      ),
    );
  }
}

