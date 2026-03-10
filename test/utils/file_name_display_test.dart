import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/file_name_display.dart';

void main() {
  group('decodeFileNameForDisplay', () {
    test('null или пустая строка — fallback', () {
      expect(decodeFileNameForDisplay(null), 'Файл');
      expect(decodeFileNameForDisplay(''), 'Файл');
      expect(decodeFileNameForDisplay('   '), 'Файл');
      expect(decodeFileNameForDisplay(null, fallback: 'Документ'), 'Документ');
    });

    test('обычная строка без % возвращается как есть', () {
      expect(decodeFileNameForDisplay('report.pdf'), 'report.pdf');
      expect(decodeFileNameForDisplay('Документ.docx'), 'Документ.docx');
    });

    test('percent-encoded декодируется', () {
      // "Привет" in UTF-8 percent-encoded
      expect(
        decodeFileNameForDisplay('%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82.pdf'),
        'Привет.pdf',
      );
    });

    test('невалидный % — возвращается исходная строка', () {
      expect(decodeFileNameForDisplay('file%2'), 'file%2');
    });
  });
}
