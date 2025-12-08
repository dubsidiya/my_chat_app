import 'package:flutter/material.dart';

class AddMembersDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableUsers;

  const AddMembersDialog({required this.availableUsers});

  @override
  State<AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends State<AddMembersDialog> {
  final Set<String> _selectedUserIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Добавить участников'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.availableUsers.isEmpty
            ? Center(child: Text('Нет доступных пользователей'))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.availableUsers.length,
                itemBuilder: (context, index) {
                  final user = widget.availableUsers[index];
                  final userId = user['id'] as String;
                  final email = user['email'] as String;
                  final isSelected = _selectedUserIds.contains(userId);

                  return CheckboxListTile(
                    title: Text(email),
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedUserIds.add(userId);
                        } else {
                          _selectedUserIds.remove(userId);
                        }
                      });
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _selectedUserIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedUserIds),
          child: Text('Добавить (${_selectedUserIds.length})'),
        ),
      ],
    );
  }
}

