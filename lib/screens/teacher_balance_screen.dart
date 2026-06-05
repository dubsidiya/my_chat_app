import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/teacher_balance.dart';
import '../models/report.dart';
import '../services/reports_service.dart';
import '../services/teacher_balance_service.dart';
import '../theme/app_colors.dart';
import '../utils/network_error_helper.dart';
import '../widgets/teacher_balance_transaction_tile.dart';
import 'report_text_view_screen.dart';

/// Рабочий баланс преподавателя: начисления с занятий, выплаты, премии.
class TeacherBalanceScreen extends StatefulWidget {
  const TeacherBalanceScreen({super.key});

  @override
  State<TeacherBalanceScreen> createState() => _TeacherBalanceScreenState();
}

class _TeacherBalanceScreenState extends State<TeacherBalanceScreen> {
  final TeacherBalanceService _service = TeacherBalanceService();
  final ReportsService _reportsService = ReportsService();
  double _balance = 0;
  List<TeacherBalanceTransaction> _transactions = [];
  bool _loading = false;
  String? _error;

  static Color get _accent => AppColors.primary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getMyTransactions();
      if (!mounted) return;
      setState(() {
        _balance = data.balance;
        _transactions = data.transactions;
      });
    } catch (e) {
      if (mounted) setState(() => _error = networkErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(num v) => '${NumberFormat('#,##0', 'ru_RU').format(v.round())} ₽';

  Color _amountColor(double amount, ColorScheme scheme) {
    if (amount > 0) return Colors.green.shade700;
    if (amount < 0) return Colors.red.shade700;
    return scheme.onSurfaceVariant;
  }

  Future<void> _openReport(int reportId) async {
    try {
      final Report report = await _reportsService.getReport(reportId);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReportTextViewScreen(report: report),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(networkErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Рабочий баланс'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading && _transactions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: scheme.error)),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_accent.withValues(alpha: 0.15), AppColors.primaryGlow.withValues(alpha: 0.12)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accent.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Текущий баланс',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _money(_balance),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: _amountColor(_balance, scheme),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'История операций',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 10),
                  if (_transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Операций пока нет',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    ..._transactions.map(
                      (tx) => TeacherBalanceTransactionTile(
                        transaction: tx,
                        formatMoney: _money,
                        onOpenReport: tx.reportId != null ? _openReport : null,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

}
