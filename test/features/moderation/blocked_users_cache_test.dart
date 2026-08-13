import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/features/moderation/blocked_users_cache.dart';

void main() {
  setUp(BlockedUsersCache.clear);

  test('isBlocked после rememberAll и add', () {
    expect(BlockedUsersCache.isBlocked('7'), isFalse);
    BlockedUsersCache.rememberAll(['7', ' 8 ']);
    expect(BlockedUsersCache.isBlocked('7'), isTrue);
    expect(BlockedUsersCache.isBlocked('8'), isTrue);
    BlockedUsersCache.add('9');
    expect(BlockedUsersCache.isBlocked('9'), isTrue);
    BlockedUsersCache.rememberAll(['1']);
    expect(BlockedUsersCache.isBlocked('7'), isFalse);
    expect(BlockedUsersCache.isBlocked('1'), isTrue);
  });

  test('пустой id не считается заблокированным', () {
    BlockedUsersCache.add('  ');
    expect(BlockedUsersCache.isBlocked(''), isFalse);
    expect(BlockedUsersCache.snapshot(), isEmpty);
  });

  test('applyServerList не затирает блок, поставленный во время запроса', () {
    final version = BlockedUsersCache.mutationVersion;
    BlockedUsersCache.add('7');
    BlockedUsersCache.applyServerList(const [], versionAtRequestStart: version);
    expect(BlockedUsersCache.isBlocked('7'), isTrue);
  });

  test('applyServerList заменяет список, если локальных add не было', () {
    BlockedUsersCache.rememberAll(['7']);
    final version = BlockedUsersCache.mutationVersion;
    BlockedUsersCache.applyServerList(const [
      '8',
    ], versionAtRequestStart: version);
    expect(BlockedUsersCache.isBlocked('7'), isFalse);
    expect(BlockedUsersCache.isBlocked('8'), isTrue);
  });
}
