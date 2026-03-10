import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/user.dart';

void main() {
  group('User.fromJson', () {
    test('парсит id и email', () {
      final u = User.fromJson({'id': 1, 'email': 'a@b.ru'});
      expect(u.id, '1');
      expect(u.email, 'a@b.ru');
    });
  });
}
