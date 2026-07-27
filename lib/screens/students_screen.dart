import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../theme/app_colors.dart';
import '../widgets/theme_motion.dart';
import '../models/student.dart';
import '../services/students_service.dart';
import '../services/storage_service.dart';
import 'student_detail_screen.dart';
import 'add_student_screen.dart';
import 'lessons_calendar_screen.dart';
import 'accounting_hub_screen.dart';

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
  bool _showArchived = false;
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
    await _migrateLocalHiddenToServerArchive();
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

  Set<int> get _archivedStudentIds =>
      _students.where((s) => s.isArchived).map((s) => s.id).toSet();

  /// Одноразово переносим старые локальные «скрытых» в серверный архив.
  Future<void> _migrateLocalHiddenToServerArchive() async {
    final localIds = await StorageService.getHiddenStudentIds(widget.userId);
    if (localIds.isEmpty) return;
    for (final id in localIds) {
      try {
        await _studentsService.archiveStudent(id);
      } catch (_) {
        // Нет связи / уже архив / сеть — пропускаем, локальный список всё равно очистим.
      }
    }
    await StorageService.clearHiddenStudentIds(widget.userId);
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

  Future<void> _archiveStudent(Student student) async {
    try {
      await _studentsService.archiveStudent(student.id);
      if (!mounted) return;
      setState(() {
        _students = _students
            .map((s) => s.id == student.id ? s.copyWith(isArchived: true) : s)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Ученик "${student.name}" в выпускниках'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () async {
              await _unarchiveStudent(student, silent: true);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(duration: Duration(seconds: 2), content: Text('Возврат отменён')),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Не удалось перенести в выпускники: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _unarchiveStudent(Student student, {bool silent = false}) async {
    try {
      await _studentsService.unarchiveStudent(student.id);
      if (!mounted) return;
      setState(() {
        _students = _students
            .map((s) => s.id == student.id ? s.copyWith(isArchived: false) : s)
            .toList();
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ученик "${student.name}" снова в активных'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Не удалось вернуть из выпускников: $e'),
          backgroundColor: Colors.red,
        ),
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
    final visibleMakeupItems = _showArchived
        ? _makeupPendingItems
        : _makeupPendingItems
            .where((item) => !_archivedStudentIds.contains((item['studentId'] as num?)?.toInt()))
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
    final visibleMakeupTotal = _showArchived
        ? _makeupPendingTotal
        : _makeupPendingItems.fold<int>(
            0,
            (acc, item) => _archivedStudentIds.contains((item['studentId'] as num?)?.toInt())
                ? acc
                : acc + ((item['pendingCount'] as num?)?.toInt() ?? 0),
          );
    final filteredStudents = _students.where((s) {
      if (!_showArchived && s.isArchived) return false;
      if (_showOnlyDebtors && s.balance >= 0) return false;
      return _matchesStudent(s, q);
    }).toList();
    final addedChildrenCount = _students.length;
    final archivedVisibleCount = _students.where((s) => s.isArchived).length;
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
                        setState(() => _showArchived = !_showArchived);
                        break;
                      case 'calendar':
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => const LessonsCalendarScreen()),
                        );
                        break;
                      case 'accounting':
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(builder: (_) => const AccountingHubScreen()),
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
                            _showArchived ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                            color: _showArchived ? Colors.teal : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(_showArchived
                              ? 'Скрыть выпускников'
                              : 'Показать выпускников ($archivedVisibleCount)'),
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
                        value: 'accounting',
                        child: Row(
                          children: [
                            Icon(Icons.business_center_rounded, color: Colors.deepPurple),
                            SizedBox(width: 10),
                            Text('Бухгалтерия'),
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
                      if (!_showArchived && archivedVisibleCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.visibility_off_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.6)),
                              const SizedBox(width: 6),
                              Text(
                                'В выпускниках: $archivedVisibleCount',
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
                      final isArchivedStudent = student.isArchived;
                      return Dismissible(
                        key: Key('student_${student.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: isArchivedStudent ? Colors.teal : Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            isArchivedStudent ? Icons.visibility_rounded : Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          final result = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(isArchivedStudent
                                  ? 'Что сделать с выпускником?'
                                  : 'Что сделать с учеником?'),
                              content: Text(
                                'Ученик: "${student.name}"\n\n'
                                '${isArchivedStudent ? 'Вернуть — снова в активный список на всех устройствах.\nУдалить связь — снять вашу привязку к ученику.' : 'В выпускники — убрать из активного списка и дневного отчёта, данные сохранятся.\nУдалить связь — только снять вашу привязку.'}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, 'cancel'),
                                  child: const Text('Отмена'),
                                ),
                                if (isArchivedStudent)
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'unarchive'),
                                    child: const Text('Вернуть'),
                                  )
                                else
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, 'archive'),
                                    child: const Text('В выпускники'),
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
                          if (result == 'archive') {
                            await _archiveStudent(student);
                            return false;
                          }
                          if (result == 'unarchive') {
                            await _unarchiveStudent(student);
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
                                if (isArchivedStudent) ...[
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed: () => _unarchiveStudent(student),
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
          PulsingGlow(
            borderRadius: BorderRadius.circular(16),
            child: FloatingActionButton(
              heroTag: "add",
              onPressed: _addStudent,
              backgroundColor: scheme.primary,
              child: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

