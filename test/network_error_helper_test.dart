import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/network_error_helper.dart';

void main() {
  group('networkErrorMessage', () {
    test('SocketException -> сообщение о нет подключения', () {
      final msg = networkErrorMessage(const SocketException('Connection refused'));
      expect(msg, contains('интернет'));
      expect(msg, isNot(contains('Connection refused')));
    });

    test('TimeoutException -> сообщение о таймауте', () {
      final msg = networkErrorMessage(TimeoutException('reports'));
      expect(msg, contains('Сервер не отвечает'));
      expect(msg, isNot(contains('reports')));
    });

    test('HandshakeException -> сообщение о соединении', () {
      final msg = networkErrorMessage(const HandshakeException('certificate'));
      expect(msg, contains('соединен'));
      expect(msg, isNot(contains('certificate')));
    });

    test('строка с SocketException -> нет подключения', () {
      final msg = networkErrorMessage(Exception('SocketException: Failed host lookup'));
      expect(msg, contains('интернет'));
    });

    test('строка с TimeoutException -> сервер не отвечает', () {
      final msg = networkErrorMessage(Exception('TimeoutException after 0:00:15.000000'));
      expect(msg, contains('Сервер не отвечает'));
    });

    test('обычный Exception -> убирается префикс Exception:', () {
      final msg = networkErrorMessage(Exception('Неверный логин или пароль'));
      expect(msg, 'Неверный логин или пароль');
    });

    test('строка Connection refused -> нет подключения', () {
      final msg = networkErrorMessage(Exception('Connection refused'));
      expect(msg, contains('интернет'));
    });

    test('длинное сообщение обрезается', () {
      final long = 'X' * 200;
      final msg = networkErrorMessage(Exception(long));
      expect(msg.length, lessThanOrEqualTo(120));
      expect(msg.endsWith('...'), isTrue);
    });
  });
}
