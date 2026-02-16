import 'package:flutter/material.dart';
import '../models/student.dart';
import '../services/students_service.dart';

class EditStudentScreen extends StatefulWidget {
  final Student student;

  const EditStudentScreen({super.key, required this.student});

  @override
  _EditStudentScreenState createState() => _EditStudentScreenState();
}

class _EditStudentScreenState extends State<EditStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  final _studentsService = StudentsService();
  bool _isLoading = false;
  bool _payByBankTransfer = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.student.name;
    _parentNameController.text = widget.student.parentName ?? '';
    _phoneController.text = widget.student.phone ?? '';
    _emailController.text = widget.student.email ?? '';
    _notesController.text = widget.student.notes ?? '';
    _payByBankTransfer = widget.student.payByBankTransfer;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _parentNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updated = await _studentsService.updateStudent(
        id: widget.student.id,
        name: _nameController.text.trim(),
        parentName: _parentNameController.text.trim().isEmpty
            ? null
            : _parentNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        payByBankTransfer: _payByBankTransfer,
      );

      if (mounted) {
        Navigator.pop(context, updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Данные ученика сохранены'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать ученика'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя ученика *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите имя';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _parentNameController,
              decoration: const InputDecoration(
                labelText: 'Имя родителя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Телефон',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Заметки',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _payByBankTransfer,
              onChanged: (v) => setState(() => _payByBankTransfer = v),
              title: const Text('Платит на расчётный счёт'),
              subtitle: Text(
                'Если выключено — оплата наличными',
                style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.6)),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveStudent,
              child: _isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                      ),
                    )
                  : const Text('Сохранить'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
