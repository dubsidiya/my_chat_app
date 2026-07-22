import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/push_payload.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22, 12);

  test('expired incoming call push is discarded locally', () {
    expect(
      shouldDiscardIncomingCallPush({
        'type': 'incoming_call',
        'callId': 'call-1',
        'expiresAt': now.subtract(const Duration(seconds: 1)).toIso8601String(),
      }, now: now),
      isTrue,
    );
    expect(
      shouldDiscardIncomingCallPush({
        'type': 'incoming_call',
        'callId': 'call-1',
        'expiresAt': now.add(const Duration(seconds: 1)).toIso8601String(),
      }, now: now),
      isFalse,
    );
  });

  test('legacy incoming call payload remains compatible without expiry', () {
    expect(
      shouldDiscardIncomingCallPush({
        'type': 'incoming_group_call',
        'callId': 'legacy-call',
        'chatId': '8',
      }, now: now),
      isFalse,
    );
  });

  test('Apple remote foreground notification suppresses local duplicate', () {
    expect(
      shouldShowForegroundLocalNotification(
        platform: TargetPlatform.iOS,
        hasRemoteNotification: true,
      ),
      isFalse,
    );
    expect(
      shouldShowForegroundLocalNotification(
        platform: TargetPlatform.macOS,
        hasRemoteNotification: true,
      ),
      isFalse,
    );
    expect(
      shouldShowForegroundLocalNotification(
        platform: TargetPlatform.android,
        hasRemoteNotification: true,
      ),
      isTrue,
    );
    expect(
      shouldShowForegroundLocalNotification(
        platform: TargetPlatform.iOS,
        hasRemoteNotification: false,
      ),
      isTrue,
    );
  });

  test('notification identity is stable and reconciliation is recognized', () {
    const payload = {
      'type': 'call_reconcile',
      'callId': 'call-7',
      'notificationId': '0',
      'notificationTag': 'call_server_hash',
    };
    expect(isCallReconciliationPushData(payload), isTrue);
    expect(callNotificationIdentity(payload).id, 0);
    expect(callNotificationIdentity(payload).tag, 'call_server_hash');

    final first = callNotificationIdentity(const {
      'type': 'incoming_call',
      'callId': 'legacy-call',
    });
    final second = callNotificationIdentity(const {
      'type': 'incoming_call',
      'callId': 'legacy-call',
    });
    expect(first.id, second.id);
    expect(first.tag, second.tag);
  });
}
