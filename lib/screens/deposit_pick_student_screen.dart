import 'dart:async';
import 'package:flutter/material.dart';
import '../services/students_service.dart';
import '../models/transaction.dart';
import 'deposit_screen.dart';

class DepositPickResult {
  final int studentId;
  final String studentName;
  final Transaction transaction;

  const DepositPickResult({
    required this.studentId,
    required this.studentName,
    required this.transaction,
  });
}

class DepositPickStudentScreen extends StatefulWidget {
  const DepositPickStudentScreen({super.key});

  @override
  State<DepositPickStudentScreen> createState() => _DepositPickStudentScreenState();
}

class _DepositPickStudentScreenState extends State<DepositPickStudentScreen> {
  final StudentsService _studentsService = StudentsService();
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    final q = _controller.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final items = await _studentsService.searchStudentCandidates(q, limit: 12);
      if (!mounted) return;
      if (_controller.text.trim() == q) {
        setState(() => _items = items);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка поиска: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(Map<String, dynamic> s) async {
    final id = s['id'];
    final name = (s['name'] ?? '').toString().trim();
    if (id is! int || id <= 0 || name.isEmpty) return;

    final tx = await Navigator.push<Transaction?>(
      context,
      MaterialPageRoute(
        builder: (_) => DepositScreen(studentId: id, studentName: name),
      ),
    );
    if (tx == null || !mounted) return;
    Navigator.pop(
      context,
      DepositPickResult(studentId: id, studentName: name, transaction: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Кому пополнить баланс')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Начните вводить имя (минимум 2 символа)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _items = [];
                          });
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _controller.text.trim().length < 2
                ? Center(
                    child: Text(
                      'Введите минимум 2 символа',
                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  )
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'Ничего не найдено',
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final s = _items[i];
                          final name = (s['name'] ?? '').toString();
                          final parent = (s['parent_name'] ?? '').toString().trim();
                          final phone = (s['phone'] ?? '').toString().trim();
                          final meta = <String>[
                            if (parent.isNotEmpty) 'Родитель: $parent',
                            if (phone.isNotEmpty) phone,
                          ].join(' • ');
                          return ListTile(
                            leading: const Icon(Icons.person_rounded),
                            title: Text(name),
                            subtitle: meta.isEmpty ? null : Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _select(s),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

