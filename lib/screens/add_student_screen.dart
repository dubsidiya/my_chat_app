import 'package:flutter/material.dart';
import 'dart:async';
import '../services/students_service.dart';

class AddStudentScreen extends StatefulWidget {
  const AddStudentScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _AddStudentScreenState createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  final _studentsService = StudentsService();
  bool _isLoading = false;
  bool _payByBankTransfer = false;
  Timer? _searchDebounce;
  bool _isSearchingByName = false;
  bool _isApplyingSuggestion = false;
  List<Map<String, dynamic>> _nameSuggestions = [];
  int? _selectedExistingStudentId;
  String? _selectedExistingStudentName;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _parentNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_isApplyingSuggestion) return;
    final current = _nameController.text.trim();
    if (_selectedExistingStudentId != null &&
        _selectedExistingStudentName != null &&
        current != _selectedExistingStudentName) {
      setState(() {
        _selectedExistingStudentId = null;
        _selectedExistingStudentName = null;
      });
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      _searchByName(current);
    });
  }

  Future<void> _searchByName(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      if (mounted) {
        setState(() {
          _nameSuggestions = [];
          _isSearchingByName = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isSearchingByName = true);
    try {
      final items = await _studentsService.searchStudentCandidates(q, limit: 8);
      if (!mounted) return;
      // Обновляем список только если пользователь не успел поменять текст.
      if (_nameController.text.trim() == q) {
        setState(() => _nameSuggestions = items);
      }
    } catch (_) {
      // Ошибку поиска не показываем навязчиво, чтобы не мешать вводу.
    } finally {
      if (mounted) setState(() => _isSearchingByName = false);
    }
  }

  void _applySuggestion(Map<String, dynamic> s) {
    final name = (s['name'] ?? '').toString();
    if (name.isEmpty) return;
    _isApplyingSuggestion = true;
    _nameController.text = name;
    _nameController.selection = TextSelection.collapsed(offset: name.length);
    if (_parentNameController.text.trim().isEmpty && (s['parent_name'] ?? '').toString().trim().isNotEmpty) {
      _parentNameController.text = (s['parent_name'] ?? '').toString();
    }
    if (_phoneController.text.trim().isEmpty && (s['phone'] ?? '').toString().trim().isNotEmpty) {
      _phoneController.text = (s['phone'] ?? '').toString();
    }
    if (_emailController.text.trim().isEmpty && (s['email'] ?? '').toString().trim().isNotEmpty) {
      _emailController.text = (s['email'] ?? '').toString();
    }
    final payByBank = s['pay_by_bank_transfer'] == true;
    setState(() {
      _selectedExistingStudentId = s['id'] as int?;
      _selectedExistingStudentName = name;
      _nameSuggestions = [];
      _payByBankTransfer = payByBank;
    });
    _isApplyingSuggestion = false;
  }

  Future<void> _confirmAndApplySuggestion(Map<String, dynamic> s) async {
    final name = (s['name'] ?? '').toString().trim();
    if (name.isEmpty) return;
    final parent = (s['parent_name'] ?? '').toString().trim();
    final phone = (s['phone'] ?? '').toString().trim();
    final email = (s['email'] ?? '').toString().trim();
    final isLinked = s['is_linked'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выбрать этого ученика?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (parent.isNotEmpty) Text('Родитель: $parent'),
            if (phone.isNotEmpty) Text('Телефон: $phone'),
            if (email.isNotEmpty) Text('Email: $email'),
            const SizedBox(height: 8),
            Text(
              isLinked
                  ? 'Этот ученик уже в вашем списке.'
                  : 'Этот ученик уже есть в базе. Будет выполнена привязка, а не создание нового.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выбрать'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _applySuggestion(s);
    }
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = _selectedExistingStudentId != null
          ? await _studentsService.linkExistingStudent(studentId: _selectedExistingStudentId!)
          : await _studentsService.createStudent(
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
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
              _selectedExistingStudentId != null
                  ? 'Выбран существующий ученик — добавлен к вам'
                  : (result.wasExisting
                      ? 'Ученик уже существует — добавлен к вам'
                      : 'Ученик добавлен'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
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
        title: const Text('Добавить студента'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя студента *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите имя студента';
                }
                return null;
              },
            ),
            if (_isSearchingByName) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_selectedExistingStudentId != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Будет привязан существующий ученик из базы',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedExistingStudentId = null;
                          _selectedExistingStudentName = null;
                        });
                      },
                      child: const Text('Сбросить'),
                    ),
                  ],
                ),
              ),
            ],
            if (_nameSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.6),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                      ),
                      child: const Text(
                        'Похожие ученики в базе — можно выбрать, чтобы не создать дубль',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    ..._nameSuggestions.map((s) {
                      final name = (s['name'] ?? '').toString();
                      final parent = (s['parent_name'] ?? '').toString();
                      final phone = (s['phone'] ?? '').toString();
                      final isLinked = s['is_linked'] == true;
                      final meta = <String>[
                        if (parent.trim().isNotEmpty) 'Родитель: $parent',
                        if (phone.trim().isNotEmpty) phone,
                      ].join(' • ');
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isLinked ? Icons.person : Icons.person_add_alt_1,
                          color: isLinked ? Colors.green : null,
                        ),
                        title: Text(name),
                        subtitle: meta.isEmpty ? null : Text(meta),
                        trailing: Text(
                          isLinked ? 'уже у вас' : 'в базе',
                          style: TextStyle(
                            fontSize: 11,
                            color: isLinked ? Colors.green : scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                        onTap: () => _confirmAndApplySuggestion(s),
                      );
                    }),
                  ],
                ),
              ),
            ],
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
                style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha:0.6)),
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveStudent,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
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
            ),
          ],
        ),
      ),
    );
  }
}

