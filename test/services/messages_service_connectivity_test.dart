import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/messages_service.dart';

void main() {
  test('MessagesService connectivity probe uses /healthz', () {
    final uri = MessagesService.connectivityProbeUri('https://example.com');
    expect(uri.toString(), 'https://example.com/healthz');
  });
}
