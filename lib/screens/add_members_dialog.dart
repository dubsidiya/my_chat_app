import 'package:flutter/material.dart';

class AddMembersDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableUsers;

  const AddMembersDialog({super.key, required this.availableUsers});

  @override
  // ignore: library_private_types_in_public_api
  State<AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<AddMembersDialog> {
  static const Color _accent1 = Color(0xFF667eea);
  static const Color _accent2 = Color(0xFF764ba2);
  static const Color _accent3 = Color(0xFFf093fb);

  final Set<String> _selectedUserIds = {};
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filteredUsers = widget.availableUsers.where((u) {
      final email = (u['email'] ?? '').toString().toLowerCase();
      final id = (u['id'] ?? '').toString().toLowerCase();
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return email.contains(q) || id.contains(q);
    }).toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_accent1, _accent2]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _accent1.withValues(alpha:0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Добавить участников',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Выбрано: ${_selectedUserIds.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Поиск
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12),
                  width: 1.2,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Поиск по логину',
                  hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha:0.55)),
                  prefixIcon: const Icon(Icons.search_rounded, color: _accent1),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: scheme.onSurface.withValues(alpha:0.70)),
                          onPressed: () {
                            setState(() {
                              _query = '';
                              _searchController.clear();
                            });
                          },
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: widget.availableUsers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _accent1.withValues(alpha:0.15),
                                  _accent3.withValues(alpha:0.15),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.group_off_rounded,
                              size: 42,
                              color: _accent1.withValues(alpha:0.7),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Нет доступных пользователей',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : filteredUsers.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Ничего не найдено',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final userId = (user['id'] ?? '').toString();
                            final email = (user['email'] ?? '').toString();
                            final isSelected = _selectedUserIds.contains(userId);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? _accent1.withValues(alpha:0.35)
                                      : scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha:isDark ? 0.25 : 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedUserIds.remove(userId);
                                    } else {
                                      _selectedUserIds.add(userId);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: isSelected
                                                ? [_accent1, _accent2]
                                                : [_accent3, _accent2],
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Center(
                                          child: Text(
                                            email.isNotEmpty ? email[0].toUpperCase() : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? _accent1.withValues(alpha:0.12)
                                              : (isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04)),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Checkbox(
                                          value: isSelected,
                                          activeColor: _accent1,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedUserIds.add(userId);
                                              } else {
                                                _selectedUserIds.remove(userId);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    ],
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: Text(
            'Отмена',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [_accent1, _accent2]),
            boxShadow: [
              BoxShadow(
                color: _accent1.withValues(alpha:0.28),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _selectedUserIds.isEmpty ? null : () => Navigator.pop(context, _selectedUserIds),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              'Добавить (${_selectedUserIds.length})',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

