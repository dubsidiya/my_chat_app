import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../theme/app_colors.dart';
import '../models/student.dart';
import '../services/students_service.dart';
import '../services/storage_service.dart';
import 'student_detail_screen.dart';
import 'add_student_screen.dart';
import 'accounting_export_screen.dart';
import 'lessons_calendar_screen.dart';
import 'teacher_schedule_heatmap_screen.dart';

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
  Set<int> _hiddenStudentIds = <int>{};
  bool _showHidden = false;
  bool _showOnlyDebtors = false;
  bool _isSuperuser = false;
  int _makeupPendingTotal = 0;
  List<Map<String, dynamic>> _makeupPendingItems = [];
  
  static Color get _accent1 => AppColors.primary;
  static Color get _accent2 => AppColors.primaryGlow;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final userData = await StorageService.getUserData();
    _isSuperuser = userData?['isSuperuser'] == 'true';
    await _loadHiddenStudents();
    await _loadStudents();
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

  Future<void> _loadHiddenStudents() async {
    final ids = await StorageService.getHiddenStudentIds(widget.userId);
    if (!mounted) return;
    setState(() => _hiddenStudentIds = ids);
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final students = await _studentsService.getAllStudents();
      final makeup = await _studentsService.getMakeupPendingSummary();
      final itemsRaw = (makeup['items'] as List?) ?? const [];
      if (mounted) {
        setState(() {
          _students = students;
          _makeupPendingTotal = (makeup['totalPending'] as num?)?.toInt() ?? 0;
          _makeupPendingItems = itemsRaw
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailScreen(student: student),
      ),
    );
    _loadStudents();
  }

  Future<void> _hideStudent(Student student) async {
    await StorageService.hideStudent(widget.userId, student.id);
    if (!mounted) return;
    setState(() {
      _hiddenStudentIds = {..._hiddenStudentIds, student.id};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text('Ученик "${student.name}" скрыт'),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            await _unhideStudent(student, silent: true);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(duration: Duration(seconds: 2), content: Text('Скрытие отменено')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _unhideStudent(Student student, {bool silent = false}) async {
    await StorageService.unhideStudent(widget.userId, student.id);
    if (!mounted) return;
    setState(() {
      _hiddenStudentIds = {..._hiddenStudentIds}..remove(student.id);
    });
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text('Ученик "${student.name}" снова отображается')),
      );
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

  Future<bool> _deleteStudent(Student student) async {
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
      return true;
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
      return false;
    }
  }

  Future<bool> _deleteStudentFully(Student student) async {
    try {
      await _studentsService.deleteStudentFull(student.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ученик "${student.name}" удален полностью'),
            backgroundColor: Colors.green,
          ),
        );
        _loadStudents();
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка полного удаления: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  void _openMakeupPendingSheet() {
    final visibleMakeupItems = _showHidden
        ? _makeupPendingItems
        : _makeupPendingItems
            .where((item) => !_hiddenStudentIds.contains((item['studentId'] as num?)?.toInt()))
            .toList();
    if (visibleMakeupItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Сейчас нет занятий к отработке'),
        ),
      );
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.replay_rounded),
                  const SizedBox(width: 8),
                  Text(
                    'К отработке: ${visibleMakeupItems.fold<int>(0, (acc, item) => acc + ((item['pendingCount'] as num?)?.toInt() ?? 0))}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Запись исчезнет из списка автоматически, когда добавите занятие со статусом "Отработка".',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                    itemCount: visibleMakeupItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = visibleMakeupItems[index];
                    final name = (item['studentName'] ?? '').toString();
                    final pending = (item['pendingCount'] as num?)?.toInt() ?? 0;
                    final openMissed = (item['openMissedCount'] as num?)?.toInt() ??
                        (item['missedCount'] as num?)?.toInt() ??
                        0;
                    final openCancel = (item['openCancelCount'] as num?)?.toInt() ?? 0;
                    final makeup = (item['makeupCount'] as num?)?.toInt() ?? 0;
                    final studentId = (item['studentId'] as num?)?.toInt();
                    final subtitleParts = <String>[
                      if (openMissed > 0) 'пропусков: $openMissed',
                      if (openCancel > 0) 'отмен: $openCancel',
                      'отработок всего: $makeup',
                    ];
                    return ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: Text(name),
                      subtitle: Text(subtitleParts.join(' • ')),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$pending',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      onTap: studentId == null
                          ? null
                          : () {
                              final student = _students.where((s) => s.id == studentId).toList();
                              if (student.isEmpty) return;
                              Navigator.pop(ctx);
                              _openStudentDetail(student.first);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _searchQuery.trim().toLowerCase();
    final visibleMakeupTotal = _showHidden
        ? _makeupPendingTotal
        : _makeupPendingItems.fold<int>(
            0,
            (acc, item) => _hiddenStudentIds.contains((item['studentId'] as num?)?.toInt())
                ? acc
                : acc + ((item['pendingCount'] as num?)?.toInt() ?? 0),
          );
    final filteredStudents = _students.where((s) {
      if (!_showHidden && _hiddenStudentIds.contains(s.id)) return false;
      if (_showOnlyDebtors && s.balance >= 0) return false;
      return _matchesStudent(s, q);
    }).toList();
    final addedChildrenCount = _students.length;
    final hiddenVisibleCount = _students.where((s) => _hiddenStudentIds.contains(s.id)).length;
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
            child: Row(
              children: [
                Text(
                  'Должники',
                  style: TextStyle(
                    fontSize: 12,
                    color: _showOnlyDebtors
                        ? Colors.red.shade700
                        : scheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Switch.adaptive(
                  value: _showOnlyDebtors,
                  activeThumbColor: Colors.red.shade700,
                  onChanged: (value) => setState(() => _showOnlyDebtors = value),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Действия',
                  icon: Icon(Icons.more_vert_rounded, color: _accent1),
                  onSelected: (value) async {
                    switch (value) {
                      case 'makeup':
                        _openMakeupPendingSheet();
                        break;
                      case 'hidden':
                        setState(() => _showHidden = !_showHidden);
                        break;
                      case 'calendar':
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => const LessonsCalendarScreen()),
                        );
                        break;
                      case 'export':
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AccountingExportScreen()),
                        );
                        break;
                      case 'teacher_schedule':
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const TeacherScheduleHeatmapScreen(),
                          ),
                        );
                        break;
                      case 'refresh':
                        await _loadStudents();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'makeup',
                      child: Row(
                        children: [
                          const Icon(Icons.replay_rounded, color: Colors.orange),
                          const SizedBox(width: 10),
                          Text('К отработке${visibleMakeupTotal > 0 ? ' ($visibleMakeupTotal)' : ''}'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'hidden',
                      child: Row(
                        children: [
                          Icon(
                            _showHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                            color: _showHidden ? Colors.teal : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(_showHidden ? 'Скрыть выпускников' : 'Показать скрытых ($hiddenVisibleCount)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'calendar',
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_rounded, color: Colors.teal),
                          SizedBox(width: 10),
                          Text('Календарь занятий'),
                        ],
                      ),
                    ),
                    if (_isSuperuser)
                      const PopupMenuItem<String>(
                        value: 'teacher_schedule',
                        child: Row(
                          children: [
                            Icon(Icons.grid_on_rounded, color: Colors.indigo),
                            SizedBox(width: 10),
                            Text('График работы преподавателя'),
                          ],
                        ),
                      ),
                    const PopupMenuItem<String>(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_rounded, color: Colors.deepPurple),
                          SizedBox(width: 10),
                          Text('Выгрузка (бухгалтерия)'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'refresh',
                      child: Row(
                        children: [
                          Icon(Icons.refresh_rounded, color: _accent1),
                          const SizedBox(width: 10),
                          const Text('Обновить'),
                        ],
                      ),
                    ),
                  ],
                ),
                if (visibleMakeupTotal > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        visibleMakeupTotal > 99 ? '99+' : visibleMakeupTotal.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                strokeWidth: 3,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Column(
                    children: [
                      TextField(
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
                      if (!_showHidden && hiddenVisibleCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.visibility_off_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Text(
                                'Скрыто выпускников: $hiddenVisibleCount',
                                style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                              ),
                            ],
                          ),
                        ),
                    ],
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
                                gradient: LinearGradient(
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
                      final isHiddenStudent = _hiddenStudentIds.contains(student.id);
                      return Dismissible(
                        key: Key('student_${student.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: isHiddenStudent ? Colors.teal : Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isHiddenStudent ? Icons.visibility_rounded : Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          final result = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(isHiddenStudent ? 'Что сделать со скрытым учеником?' : 'Что сделать с учеником?'),
                              content: Text(
                                'Ученик: "${student.name}"\n\n'
                                '${isHiddenStudent ? 'Вернуть — снова показывать в вашем списке.\nУдалить — только снять вашу связь с учеником.' : 'Удалить — только снять вашу связь с учеником.\nСкрыть — оставить в базе, но убрать из ваших списков.'}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, 'cancel'),
                                  child: const Text('Отмена'),
                                ),
                                if (isHiddenStudent)
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'unhide'),
                                    child: const Text('Вернуть'),
                                  )
                                else
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'hide'),
                                    child: const Text('Скрыть'),
                                  ),
                                if (_isSuperuser)
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'delete_full'),
                                    child: const Text('Удалить полностью', style: TextStyle(color: Colors.red)),
                                  ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, 'delete'),
                                  child: const Text('Удалить связь'),
                                ),
                              ],
                            ),
                          );
                          if (!context.mounted) return false;
                          if (result == 'hide') {
                            await _hideStudent(student);
                            return false;
                          }
                          if (result == 'unhide') {
                            await _unhideStudent(student);
                            return false;
                          }
                          if (result == 'delete_full') {
                            final confirmFull = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Подтвердите полное удаление'),
                                content: Text(
                                  'Ученик "${student.name}" будет удален полностью из базы.\n\n'
                                  'Будут удалены все занятия и транзакции по этому ученику.\n'
                                  'Действие необратимо.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Отмена'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Удалить полностью', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirmFull == true) {
                              return await _deleteStudentFully(student);
                            }
                            return false;
                          }
                          if (result == 'delete') {
                            return await _deleteStudent(student);
                          }
                          return false;
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
                                if (isHiddenStudent) ...[
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed: () => _unhideStudent(student),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 28),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                                    ),
                                    child: const Text('Вернуть'),
                                  ),
                                ],
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
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Детей: $addedChildrenCount',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: "add",
            onPressed: _addStudent,
            backgroundColor: scheme.primary,
            child: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

