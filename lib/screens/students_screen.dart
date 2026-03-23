import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../theme/app_colors.dart';
import '../models/student.dart';
import '../services/students_service.dart';
import 'student_detail_screen.dart';
import 'add_student_screen.dart';
import 'accounting_export_screen.dart';

class StudentsScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  const StudentsScreen({super.key, required this.userId, required this.userEmail});

  @override
  // ignore: library_private_types_in_public_api
  _StudentsScreenState createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final StudentsService _studentsService = StudentsService();
  final TextEditingController _searchController = TextEditingController();
  List<Student> _students = [];
  bool _isLoading = false;
  String _searchQuery = '';
  
  static const Color _accent1 = AppColors.primary;
  static const Color _accent2 = AppColors.primaryGlow;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesStudent(Student student, String q) {
    if (q.isEmpty) return true;
    final query = q.toLowerCase();
    final name = student.name.toLowerCase();
    final parent = (student.parentName ?? '').toLowerCase();
    return name.contains(query) || parent.contains(query);
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
      if (kDebugMode) print('Ошибка загрузки студентов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
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
        builder: (_) => const AddStudentScreen(),
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
            duration: const Duration(seconds: 3),
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
            duration: const Duration(seconds: 3),
            content: Text('Ошибка удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _searchQuery.trim().toLowerCase();
    final filteredStudents = _students.where((s) => _matchesStudent(s, q)).toList();
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Учет занятий',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.receipt_long_rounded, color: Colors.deepPurple),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountingExportScreen()),
                );
              },
              tooltip: 'Выгрузка (бухгалтерия)',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded, color: _accent1),
              onPressed: _loadStudents,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                strokeWidth: 3,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Глобальный поиск по детям',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.trim().isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: _students.isEmpty
                      ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _accent1.withValues(alpha:0.2),
                                _accent2.withValues(alpha:0.2),
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.school_rounded,
                            size: 60,
                            color: _accent1.withValues(alpha:0.7),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Нет студентов',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface.withValues(alpha:0.75),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Добавьте первого ученика или загрузите выписку',
                          style: TextStyle(
                            fontSize: 16,
                            color: scheme.onSurface.withValues(alpha:0.60),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [_accent1, _accent2],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent1.withValues(alpha:0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _addStudent,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text(
                                  'Добавить',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
                      : filteredStudents.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 44,
                                      color: scheme.onSurface.withValues(alpha: 0.45),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Ничего не найдено',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onSurface.withValues(alpha: 0.75),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                          _searchController.clear();
                                        });
                                      },
                                      icon: const Icon(Icons.clear_all_rounded),
                                      label: const Text('Сбросить поиск'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadStudents,
                              child: ListView.builder(
                    itemCount: filteredStudents.length,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemBuilder: (context, index) {
                      final student = filteredStudents[index];
                      return Dismissible(
                        key: Key('student_${student.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Удалить ученика?'),
                              content: Text(
                                'Вы уверены, что хотите удалить "${student.name}"?\n\n'
                                'Это действие удалит вашу связь с учеником.\n'
                                'Если ученик привязан к другим преподавателям, его данные останутся у них.\n\n'
                                'Это действие нельзя отменить!',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Отмена'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Удалить', style: TextStyle(color: Colors.red)),
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
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          leading: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: student.isDebtor
                                    ? [Colors.red.shade400, Colors.red.shade700]
                                    : [_accent1, _accent2],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: (student.isDebtor ? Colors.red : _accent1).withValues(alpha:0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
                          ),
                          title: Text(
                            student.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: scheme.onSurface,
                            ),
                          ),
                          subtitle: student.parentName != null
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    student.parentName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: scheme.onSurface.withValues(alpha:0.65)),
                                  ),
                                )
                              : null,
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${student.balance.toStringAsFixed(0)} ₽',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: student.balance < 0
                                          ? Colors.red
                                          : student.balance > 0
                                              ? Colors.green.shade700
                                              : scheme.onSurface.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ),
                                if (student.isDebtor) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha:0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Долг',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          onTap: () => _openStudentDetail(student),
                        ),
                        ),
                      );
                    },
                              ),
                            ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: "add",
        onPressed: _addStudent,
        backgroundColor: scheme.primary,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

