import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';
import '../models/lesson.dart';
import '../models/transaction.dart';
import '../services/students_service.dart';
import 'add_lesson_screen.dart';
import 'deposit_screen.dart';

class StudentDetailScreen extends StatefulWidget {
  final Student student;

  StudentDetailScreen({required this.student});

  @override
  _StudentDetailScreenState createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> with SingleTickerProviderStateMixin {
  final StudentsService _studentsService = StudentsService();
  List<Lesson> _lessons = [];
  List<Transaction> _transactions = [];
  double _balance = 0;
  bool _isLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _balance = widget.student.balance;
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final lessons = await _studentsService.getStudentLessons(widget.student.id);
      final transactions = await _studentsService.getStudentTransactions(widget.student.id);
      await _updateBalance();
      if (mounted) {
        setState(() {
          _lessons = lessons;
          _transactions = transactions;
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

  // Обновление данных без показа индикатора загрузки
  Future<void> _refreshData() async {
    if (!mounted) return;
    try {
      final lessons = await _studentsService.getStudentLessons(widget.student.id);
      final transactions = await _studentsService.getStudentTransactions(widget.student.id);
      await _updateBalance();
      if (mounted) {
        setState(() {
          _lessons = lessons;
          _transactions = transactions;
        });
      }
    } catch (e) {
      print('Ошибка обновления данных: $e');
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
      // Быстрое обновление данных после добавления занятия
      await _refreshData();
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
      // Быстрое обновление данных после пополнения
      await _refreshData();
    }
  }

  Future<void> _updateBalance() async {
    try {
      final students = await _studentsService.getAllStudents();
      final updatedStudent = students.firstWhere(
        (s) => s.id == widget.student.id,
      );
      if (mounted) {
      setState(() {
        _balance = updatedStudent.balance;
      });
      }
    } catch (e) {
      print('Ошибка обновления баланса: $e');
    }
  }

  Future<void> _deleteStudent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить ученика?'),
        content: Text(
          'Вы уверены, что хотите удалить "${widget.student.name}"?\n\n'
          'Это действие удалит все связанные данные:\n'
          '• Все занятия (${_lessons.length})\n'
          '• Все транзакции (${_transactions.length})\n'
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

    if (confirm != true) return;

    try {
      await _studentsService.deleteStudent(widget.student.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ученик "${widget.student.name}" удален'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Возвращаемся назад с результатом
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
      // Быстрое обновление данных после удаления занятия
      await _refreshData();
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
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () => _deleteStudent(),
            tooltip: 'Удалить ученика',
          ),
        ],
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

          // Табы для занятий и транзакций
          Expanded(
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: 'Занятия (${_lessons.length})'),
                    Tab(text: 'Транзакции (${_transactions.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Вкладка занятий
                      _isLoading
                ? Center(child: CircularProgressIndicator())
                : _lessons.isEmpty
                    ? Center(
                        child: Text(
                          'Нет занятий',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                              : RefreshIndicator(
                                  onRefresh: _refreshData,
                                  child: ListView.builder(
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
                      // Вкладка транзакций
                      _isLoading
                          ? Center(child: CircularProgressIndicator())
                          : _transactions.isEmpty
                              ? RefreshIndicator(
                                  onRefresh: _refreshData,
                                  child: SingleChildScrollView(
                                    physics: AlwaysScrollableScrollPhysics(),
                                    child: Container(
                                      height: MediaQuery.of(context).size.height * 0.5,
                                      child: Center(
                                        child: Text(
                                          'Нет транзакций',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _refreshData,
                                  child: ListView.builder(
                                    padding: EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: _transactions.length,
                                    itemBuilder: (context, index) {
                                    final transaction = _transactions[index];
                                    final isDeposit = transaction.type == 'deposit';
                                    final isLesson = transaction.type == 'lesson';
                                    
                                    return Card(
                                      margin: EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        leading: Icon(
                                          isDeposit 
                                              ? Icons.add_circle 
                                              : isLesson 
                                                  ? Icons.event 
                                                  : Icons.undo,
                                          color: isDeposit 
                                              ? Colors.green 
                                              : isLesson 
                                                  ? Colors.blue 
                                                  : Colors.orange,
                                        ),
                                        title: Text(
                                          isDeposit 
                                              ? 'Пополнение баланса'
                                              : isLesson 
                                                  ? 'Занятие'
                                                  : 'Возврат',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (isDeposit && transaction.depositTypeLabel.isNotEmpty)
                                              Container(
                                                margin: EdgeInsets.only(top: 4, bottom: 4),
                                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: transaction.isBankDeposit 
                                                      ? Colors.blue.shade50 
                                                      : Colors.orange.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: transaction.isBankDeposit 
                                                        ? Colors.blue.shade200 
                                                        : Colors.orange.shade200,
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      transaction.isBankDeposit 
                                                          ? Icons.account_balance 
                                                          : Icons.money,
                                                      size: 14,
                                                      color: transaction.isBankDeposit 
                                                          ? Colors.blue.shade700 
                                                          : Colors.orange.shade700,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      transaction.depositTypeLabel,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: transaction.isBankDeposit 
                                                            ? Colors.blue.shade700 
                                                            : Colors.orange.shade700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (transaction.description != null)
                                              Text(
                                                transaction.description!,
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            SizedBox(height: 4),
                                            Text(
                                              DateFormat('dd.MM.yyyy HH:mm')
                                                  .format(transaction.createdAt),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Text(
                                          '${isDeposit ? '+' : '-'}${transaction.amount.toStringAsFixed(0)} ₽',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isDeposit 
                                                ? Colors.green 
                                                : Colors.red,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  ),
                                ),
                    ],
                  ),
                ),
              ],
                      ),
          ),
        ],
      ),
    );
  }
}

