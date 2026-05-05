import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/students_service.dart';
import '../models/transaction.dart';

class DepositScreen extends StatefulWidget {
  final int studentId;
  final String? studentName;

  const DepositScreen({super.key, required this.studentId, this.studentName});

  @override
  // ignore: library_private_types_in_public_api
  _DepositScreenState createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _studentsService = StudentsService();
  bool _isLoading = false;
  bool _manualCorrection = false;
  bool _teachersLoading = false;
  List<DepositTeacherOption> _teachers = const [];
  int? _selectedTeacherId;

  static const double _maxAmount = 1000000;
  static const int _recentDepositWindowDays = 5;
  static const int _recentDepositsPreviewLimit = 3;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    setState(() => _teachersLoading = true);
    try {
      final teachers = await _studentsService.getStudentDepositTeachers(widget.studentId);
      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _selectedTeacherId = teachers.length == 1 ? teachers.first.id : null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Не удалось загрузить преподавателей: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _teachersLoading = false);
      }
    }
  }

  Future<void> _deposit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text);

    setState(() => _isLoading = true);

    try {
      if (_selectedTeacherId == null) {
        throw Exception('Выберите преподавателя для пополнения');
      }
      final recentDeposits = await _findRecentDeposits();
      if (!mounted) return;
      final confirmed = await _confirmDepositIfRecentFound(
        amount: amount,
        recentDeposits: recentDeposits,
      );
      if (!mounted || !confirmed) return;

      final tx = await _studentsService.depositBalance(
        studentId: widget.studentId,
        amount: amount,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        targetTeacherId: _selectedTeacherId,
      );

      if (mounted) {
        Navigator.pop<Transaction>(context, tx);
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

  Future<List<Transaction>> _findRecentDeposits() async {
    final cutoff = DateTime.now().toUtc().subtract(
      const Duration(days: _recentDepositWindowDays),
    );
    final transactions = await _studentsService.getStudentTransactions(widget.studentId);
    return transactions.where((t) {
      return t.type == 'deposit' && t.createdAt.toUtc().isAfter(cutoff);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<bool> _confirmDepositIfRecentFound({
    required double amount,
    required List<Transaction> recentDeposits,
  }) async {
    if (recentDeposits.isEmpty) return true;
    if (!mounted) return false;

    final preview = recentDeposits.take(_recentDepositsPreviewLimit).map((t) {
      final dt = DateFormat('dd.MM.yyyy HH:mm').format(t.createdAt.toLocal());
      final sum = t.amount.toStringAsFixed(0);
      return '• $dt — +$sum ₽';
    }).join('\n');
    final restCount = recentDeposits.length - _recentDepositsPreviewLimit;

    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Недавнее пополнение уже было'),
          content: Text(
            'За последние $_recentDepositWindowDays дней по этому ученику уже есть '
            '${recentDeposits.length} пополнени${_depositWordEnding(recentDeposits.length)}.\n\n'
            '$preview'
            '${restCount > 0 ? '\n…и ещё $restCount' : ''}\n\n'
            'Точно провести новое пополнение на ${amount.toStringAsFixed(0)} ₽?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Нет'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Да, провести'),
            ),
          ],
        );
      },
    );

    return shouldProceed == true;
  }

  String _depositWordEnding(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'е';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'я';
    return 'й';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentName == null || widget.studentName!.trim().isEmpty
            ? 'Пополнить баланс'
            : 'Пополнить: ${widget.studentName}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(Icons.person, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ученик: ${widget.studentName?.trim().isNotEmpty == true ? widget.studentName!.trim() : 'ID ${widget.studentId}'}\n'
                      'ID: ${widget.studentId}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_teachersLoading)
              const LinearProgressIndicator(minHeight: 2),
            DropdownButtonFormField<int>(
              key: ValueKey(_selectedTeacherId),
              initialValue: _selectedTeacherId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Преподаватель *',
                border: OutlineInputBorder(),
              ),
              items: _teachers
                  .map(
                    (t) => DropdownMenuItem<int>(
                      value: t.id,
                      child: Text(
                        t.email == null ? t.name : '${t.name} (${t.email})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _isLoading || _teachersLoading
                  ? null
                  : (v) => setState(() => _selectedTeacherId = v),
              validator: (value) {
                if (value == null) {
                  return 'Выберите преподавателя';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _manualCorrection,
              onChanged: _isLoading ? null : (v) => setState(() => _manualCorrection = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Ручная корректировка'),
              subtitle: Text(
                'Требует обязательный комментарий',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Сумма (₽) *',
                      border: OutlineInputBorder(),
                      prefixText: '+ ',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите сумму';
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return 'Введите корректную сумму';
                      }
                      if (amount > _maxAmount) {
                        return 'Слишком большая сумма';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _isLoading ? null : _deposit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: scheme.onPrimary,
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
                        : const Text('Пополнить'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: _manualCorrection ? 'Комментарий *' : 'Описание (опционально)',
                border: const OutlineInputBorder(),
                hintText: _manualCorrection
                    ? 'Например: Исправление ошибки, пересчет'
                    : 'Например: Оплата за месяц',
              ),
              maxLines: 2,
              validator: (value) {
                if (_manualCorrection) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Комментарий обязателен для ручной корректировки';
                  }
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

