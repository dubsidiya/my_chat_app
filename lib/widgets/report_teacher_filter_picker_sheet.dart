import 'package:flutter/material.dart';

import '../models/report_author_option.dart';

/// Bottom sheet: выбор преподавателя с поиском по имени.
class ReportTeacherFilterPickerSheet extends StatefulWidget {
  const ReportTeacherFilterPickerSheet({
    super.key,
    required this.teachers,
    required this.selectedId,
  });

  final List<ReportAuthorOption> teachers;
  final int? selectedId;

  @override
  State<ReportTeacherFilterPickerSheet> createState() =>
      _ReportTeacherFilterPickerSheetState();
}

class _ReportTeacherFilterPickerSheetState
    extends State<ReportTeacherFilterPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = filterReportTeachers(widget.teachers, _query);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Преподаватель',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Поиск преподавателя',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          _query = '';
                          _searchController.clear();
                        });
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Преподаватели не найдены',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pick = filtered[index];
                      final selected = pick.id == widget.selectedId ||
                          (pick.id == null && widget.selectedId == null);
                      return ListTile(
                        title: Text(
                          pick.label,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: selected
                            ? Icon(Icons.check_rounded, color: scheme.primary)
                            : null,
                        onTap: () => Navigator.pop(context, pick),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
