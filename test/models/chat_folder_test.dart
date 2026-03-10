import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/chat_folder.dart';

void main() {
  group('ChatFolder.fromJson', () {
    test('парсит id и name', () {
      final f = ChatFolder.fromJson({
        'id': 'folder1',
        'name': 'Работа',
      });
      expect(f.id, 'folder1');
      expect(f.name, 'Работа');
    });

    test('числовой id приводится к строке', () {
      final f = ChatFolder.fromJson({
        'id': 42,
        'name': 'x',
      });
      expect(f.id, '42');
    });
  });
}
