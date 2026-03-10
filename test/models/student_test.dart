import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/student.dart';

void main() {
  group('Student.fromJson', () {
    test('минимальные поля', () {
      final s = Student.fromJson({
        'id': 1,
        'name': 'Иван Петров',
        'balance': 0.0,
        'created_at': '2025-03-01T10:00:00Z',
      });
      expect(s.id, 1);
      expect(s.name, 'Иван Петров');
      expect(s.balance, 0.0);
      expect(s.isDebtor, false);
      expect(s.payByBankTransfer, false);
    });

    test('balance отрицательный — isDebtor', () {
      final s = Student.fromJson({
        'id': 1,
        'name': 'x',
        'balance': -500.5,
        'created_at': '2025-03-01T10:00:00Z',
      });
      expect(s.balance, -500.5);
      expect(s.isDebtor, true);
    });

    test('все опциональные поля', () {
      final s = Student.fromJson({
        'id': 2,
        'name': 'Мария',
        'parent_name': 'Ольга',
        'phone': '+7 999 123-45-67',
        'email': 'm@mail.ru',
        'notes': 'Заметка',
        'balance': 1000.0,
        'pay_by_bank_transfer': true,
        'created_at': '2025-03-01T10:00:00Z',
        'updated_at': '2025-03-02T12:00:00Z',
      });
      expect(s.parentName, 'Ольга');
      expect(s.phone, '+7 999 123-45-67');
      expect(s.email, 'm@mail.ru');
      expect(s.notes, 'Заметка');
      expect(s.payByBankTransfer, true);
      expect(s.updatedAt, isNotNull);
    });
  });
}
