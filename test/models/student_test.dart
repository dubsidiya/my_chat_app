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
      expect(s.isArchived, false);
      expect(s.updatedAt, isNotNull);
    });

    test('is_archived из JSON', () {
      final s = Student.fromJson({
        'id': 3,
        'name': 'Выпускник',
        'balance': 0,
        'is_archived': true,
        'created_at': '2025-03-01T10:00:00Z',
      });
      expect(s.isArchived, true);
      expect(s.copyWith(isArchived: false).isArchived, false);
    });

    test('заглушка отвязанного ученика в пикере', () {
      final s = Student(
        id: 9,
        name: 'Пётр (нет в списке)',
        balance: 0,
        createdAt: DateTime.utc(1970),
        isUnavailableForPicker: true,
      );
      expect(s.isUnavailableForPicker, true);
      expect(s.copyWith(name: 'Пётр').isUnavailableForPicker, true);
      expect(s.copyWith(isUnavailableForPicker: false).isUnavailableForPicker, false);
    });
  });

  // Реальные wire-формы: GET /students отдаёт balance как строку ("1500.00",
  // "-500.50"), а не число (см. аудит M64/H15). Модель обязана распарсить
  // строку в корректный double, чтобы isDebtor работал.
  group('Student.fromJson — баланс строкой (реальный wire-shape)', () {
    test('balance как строка "1500.00" → 1500.0', () {
      final s = Student.fromJson({
        'id': 1,
        'name': 'Иван',
        'balance': '1500.00',
        'created_at': '2025-03-01T10:00:00.000Z',
      });
      expect(s.balance, 1500.0);
      expect(s.isDebtor, false);
    });

    test('balance как строка "-500.50" → -500.5 и isDebtor', () {
      final s = Student.fromJson({
        'id': 2,
        'name': 'Мария',
        'balance': '-500.50',
        'created_at': '2025-03-01T10:00:00.000Z',
      });
      expect(s.balance, -500.5);
      expect(s.isDebtor, true);
    });

    test('balance как строка "0.00" → 0.0, не должник', () {
      final s = Student.fromJson({
        'id': 3,
        'name': 'Пётр',
        'balance': '0.00',
        'created_at': '2025-03-01T10:00:00.000Z',
      });
      expect(s.balance, 0.0);
      expect(s.isDebtor, false);
    });
  });
}
