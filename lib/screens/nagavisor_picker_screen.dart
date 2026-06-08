import 'package:flutter/material.dart';

import '../models/teacher_balance.dart';
import '../services/teacher_balance_service.dart';
import '../theme/app_colors.dart';
import '../utils/network_error_helper.dart';
import 'nagavisor_screen.dart';

/// Выбор преподавателя для nagavisor1.0 (только суперпользователь).
class NagavisorPickerScreen extends StatefulWidget {
  const NagavisorPickerScreen({super.key});

  @override
  State<NagavisorPickerScreen> createState() => _NagavisorPickerScreenState();
}

class _NagavisorPickerScreenState extends State<NagavisorPickerScreen> {
  final TeacherBalanceService _balanceService = TeacherBalanceService();
  final TextEditingController _searchController = TextEditingController();

  List<TeacherBalanceListItem> _teachers = [];
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _balanceService.listTeachers();
      if (!mounted) return;
      setState(() => _teachers = list);
    } catch (e) {
      if (mounted) setState(() => _error = networkErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TeacherBalanceListItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _teachers;
    return _teachers.where((t) => t.label.toLowerCase().contains(q)).toList();
  }

  void _openNagavisor(TeacherBalanceListItem teacher) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NagavisorScreen(
          teacherId: teacher.teacherId,
          teacherLabel: teacher.label,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('nagavisor1.0'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Сводка для разговора 1-on-1: качество, график, выплаты, отчёты, ученики',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск преподавателя',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          Expanded(
            child: _loading && _teachers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Преподаватели не найдены',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final t = filtered[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                child: Icon(Icons.person_search_rounded, color: AppColors.primary),
                              ),
                              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Открыть nagavisor1.0'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _openNagavisor(t),
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
