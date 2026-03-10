import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/transaction.dart';

void main() {
  group('Transaction.fromJson', () {
    test('минимальные поля', () {
      final t = Transaction.fromJson({
        'id': 1,
        'student_id': 10,
        'amount': 2000.0,
        'type': 'lesson',
        'created_by': 1,
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(t.id, 1);
      expect(t.studentId, 10);
      expect(t.amount, 2000.0);
      expect(t.type, 'lesson');
      expect(t.description, isNull);
      expect(t.lessonId, isNull);
    });

    test('deposit с описанием — isManualDeposit / isBankDeposit', () {
      final manual = Transaction.fromJson({
        'id': 1,
        'student_id': 10,
        'amount': 5000,
        'type': 'deposit',
        'description': 'Наличные от родителя',
        'created_by': 1,
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(manual.isManualDeposit, true);
      expect(manual.isBankDeposit, false);
      expect(manual.depositTypeLabel, 'Наличные');

      final bank = Transaction.fromJson({
        'id': 2,
        'student_id': 10,
        'amount': 5000,
        'type': 'deposit',
        'description': 'Пополнение из выписки банка',
        'created_by': 1,
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(bank.isManualDeposit, false);
      expect(bank.isBankDeposit, true);
      expect(bank.depositTypeLabel, 'Банковский перевод');
    });

    test('type не deposit — depositTypeLabel пустой, isManualDeposit false', () {
      final t = Transaction.fromJson({
        'id': 1,
        'student_id': 10,
        'amount': -2000,
        'type': 'lesson',
        'created_by': 1,
        'created_at': '2025-03-01T12:00:00Z',
      });
      expect(t.isManualDeposit, false);
      expect(t.isBankDeposit, false);
      expect(t.depositTypeLabel, '');
    });
  });
}
