import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/teacher_balance.dart';

class TeacherBalanceTransactionTile extends StatelessWidget {
  final TeacherBalanceTransaction transaction;
  final String Function(num value) formatMoney;
  final Future<void> Function(int reportId)? onOpenReport;

  const TeacherBalanceTransactionTile({
    super.key,
    required this.transaction,
    required this.formatMoney,
    this.onOpenReport,
  });

  Color _amountColor(double amount, ColorScheme scheme) {
    if (amount > 0) return Colors.green.shade700;
    if (amount < 0) return Colors.red.shade700;
    return scheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final scheme = Theme.of(context).colorScheme;
    final dt = tx.createdAt;
    final createdLabel =
        dt != null ? DateFormat('dd.MM.yyyy HH:mm').format(dt) : null;
    final dayLabel = tx.accrualDayLabel;
    final reportId = tx.reportId;
    final canOpenReport =
        tx.isLessonIncome && reportId != null && onOpenReport != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(tx.typeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tx.isLessonIncome && dayLabel != null)
              canOpenReport
                  ? InkWell(
                      onTap: () => onOpenReport!(reportId),
                      child: Text(
                        dayLabel,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: scheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : Text(dayLabel)
            else if (tx.description.isNotEmpty)
              Text(tx.description),
            if (createdLabel != null)
              Text(
                createdLabel,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        trailing: Text(
          '${tx.isCredit ? '+' : ''}${formatMoney(tx.amount)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _amountColor(tx.amount, scheme),
          ),
        ),
      ),
    );
  }
}
