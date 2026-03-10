import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('baseUrl не пустой', () {
      expect(ApiConfig.baseUrl, isNotEmpty);
    });

    test('baseUrl без завершающего слэша', () {
      expect(ApiConfig.baseUrl.endsWith('/'), false);
    });

    test('baseUrl начинается с http', () {
      expect(
        ApiConfig.baseUrl.startsWith('http://') || ApiConfig.baseUrl.startsWith('https://'),
        true,
      );
    });
  });
}
