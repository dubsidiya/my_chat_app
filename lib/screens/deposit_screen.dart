import 'package:flutter/material.dart';
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

  static const double _maxAmount = 1000000;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _deposit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text);

    setState(() => _isLoading = true);

    try {
      final tx = await _studentsService.depositBalance(
        studentId: widget.studentId,
        amount: amount,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
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

