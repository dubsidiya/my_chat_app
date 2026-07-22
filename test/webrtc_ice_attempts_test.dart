import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/webrtc_ice_attempts.dart';

void main() {
  test('buildIceServerAttempts prefers full (TURN) before stun-only', () {
    final full = [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': ['turn:example.com:3478'],
        'username': 'u',
        'credential': 'p',
      },
    ];
    final stunOnly = [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    const defaults = [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];

    final attempts = buildIceServerAttempts(
      full: full,
      stunOnly: stunOnly,
      defaults: defaults,
    );

    expect(attempts.length, 3);
    expect(attempts.first, same(full));
    expect(attempts[1], same(stunOnly));
    expect(attempts[2], same(defaults));
  });

  test('buildIceServerAttempts skips empty stunOnly', () {
    final full = [
      {'urls': 'turn:example.com:3478'},
    ];
    const defaults = [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];

    final attempts = buildIceServerAttempts(
      full: full,
      stunOnly: const [],
      defaults: defaults,
    );

    expect(attempts, [full, defaults]);
  });
}
