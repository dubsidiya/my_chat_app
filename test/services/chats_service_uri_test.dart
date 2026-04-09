import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/chats_service.dart';

void main() {
  test('ChatsService.buildUsersSearchUri clamps limit and keeps query', () {
    final uri = ChatsService.buildUsersSearchUri(
      'https://example.com',
      query: ' alice ',
      limit: 100,
    );

    expect(uri.path, '/auth/users');
    expect(uri.queryParameters['q'], 'alice');
    expect(uri.queryParameters['limit'], '20');
  });

  test('ChatsService.buildUsersSearchUri keeps minimum limit', () {
    final uri = ChatsService.buildUsersSearchUri(
      'https://example.com',
      query: 'ab',
      limit: 0,
    );
    expect(uri.queryParameters['limit'], '1');
  });
}
