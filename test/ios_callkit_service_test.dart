import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/ios_callkit_service.dart';

Map<String, dynamic> _call({
  String callId = 'call-1',
  String callUuid = '123e4567-e89b-42d3-a456-426614174000',
  bool group = false,
}) => {
  'callId': callId,
  'callUuid': callUuid,
  'chatId': '8',
  'fromUserId': '7',
  'fromLabel': 'Caller',
  'chatName': group ? 'Team' : 'Caller',
  'isGroup': group,
  'provider': group ? 'livekit' : 'raw',
  'mediaType': 'audio',
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 1))
      .toIso8601String(),
};

class _Platform implements IOSCallKitPlatform {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic> drained = {
    'calls': <dynamic>[],
    'events': <dynamic>[],
    'registration': <String, dynamic>{},
  };
  final List<String> completedAnswers = [];
  final List<String> connected = [];
  final List<(String, String)> ended = [];
  final List<(String, bool)> muted = [];

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;

  @override
  Future<bool> completeAnswer(String callUuid, bool success) async {
    completedAnswers.add('$callUuid:$success');
    return true;
  }

  @override
  Future<Map<String, dynamic>> drain() async => drained;

  @override
  Future<Map<String, dynamic>> getRegistration() async => {};

  @override
  Future<bool> reportConnected(String callUuid) async {
    connected.add(callUuid);
    return true;
  }

  @override
  Future<bool> reportEnd(String callUuid, String reason) async {
    ended.add((callUuid, reason));
    return true;
  }

  @override
  Future<bool> syncMute(String callUuid, bool muted) async {
    this.muted.add((callUuid, muted));
    return true;
  }
}

class _StatusClient implements IOSCallStatusClient {
  IOSCallStatus status;

  _StatusClient(this.status);

  @override
  Future<IOSCallStatus> fetch(String callId) async => status;
}

class _Handler implements IOSCallActionHandler {
  final List<String> operations = [];
  bool answerResult = true;

  @override
  Future<void> applyIncoming(IOSCallKitCall call) async {
    operations.add('incoming:${call.callId}');
  }

  @override
  Future<bool> answer(IOSCallKitCall call) async {
    operations.add('answer:${call.callId}');
    return answerResult;
  }

  @override
  Future<void> end(IOSCallKitCall call, String reason) async {
    operations.add('end:${call.callId}:$reason');
  }

  @override
  Future<void> setMuted(IOSCallKitCall call, bool muted) async {
    operations.add('mute:${call.callId}:$muted');
  }
}

void main() {
  test(
    'cold drain preserves incoming-before-answer and deduplicates replay',
    () async {
      final platform = _Platform();
      final call = _call();
      platform.drained = {
        'calls': [
          {'call': call, 'state': 'reported'},
        ],
        'events': [
          {'eventId': 'incoming-1', 'type': 'incomingReported', 'call': call},
          {'eventId': 'answer-1', 'type': 'answerRequested', 'call': call},
          {'eventId': 'answer-1', 'type': 'answerRequested', 'call': call},
        ],
        'registration': <String, dynamic>{},
      };
      final handler = _Handler();
      final service = IOSCallKitService(
        platform: platform,
        statusClient: _StatusClient(
          const IOSCallStatus(
            active: true,
            state: 'ringing',
            callId: 'call-1',
            callUuid: '123e4567-e89b-42d3-a456-426614174000',
            role: 'callee',
          ),
        ),
        actionHandler: handler,
        forceSupported: true,
        observeCallServices: false,
      );

      await service.initialize();

      expect(handler.operations, ['incoming:call-1', 'answer:call-1']);
      expect(platform.completedAnswers, [
        '123e4567-e89b-42d3-a456-426614174000:true',
      ]);
      expect(service.ownsIncomingUI('call-1'), isTrue);
      await service.dispose();
      await platform.controller.close();
    },
  );

  test('stale answer closes CallKit without starting media', () async {
    final platform = _Platform();
    final call = _call();
    platform.drained = {
      'calls': <dynamic>[],
      'events': [
        {'eventId': 'answer-stale', 'type': 'answerRequested', 'call': call},
      ],
      'registration': <String, dynamic>{},
    };
    final handler = _Handler();
    final service = IOSCallKitService(
      platform: platform,
      statusClient: _StatusClient(
        const IOSCallStatus(active: false, state: 'none'),
      ),
      actionHandler: handler,
      forceSupported: true,
      observeCallServices: false,
    );

    await service.initialize();

    expect(handler.operations, ['incoming:call-1', 'end:call-1:unanswered']);
    expect(platform.completedAnswers.single, endsWith(':false'));
    expect(platform.ended.single.$2, 'unanswered');
    await service.dispose();
    await platform.controller.close();
  });

  test('native mute and end actions are ordered and idempotent', () async {
    final platform = _Platform();
    final call = _call();
    final handler = _Handler();
    final service = IOSCallKitService(
      platform: platform,
      statusClient: _StatusClient(
        const IOSCallStatus(active: true, state: 'ringing'),
      ),
      actionHandler: handler,
      forceSupported: true,
      observeCallServices: false,
    );
    await service.initialize();

    platform.controller.add({
      'eventId': 'incoming-2',
      'type': 'incomingReported',
      'call': call,
    });
    platform.controller.add({
      'eventId': 'mute-1',
      'type': 'muteRequested',
      'call': call,
      'muted': true,
    });
    platform.controller.add({
      'eventId': 'end-1',
      'type': 'endRequested',
      'call': call,
      'reason': 'localEnded',
    });
    platform.controller.add({
      'eventId': 'end-1',
      'type': 'endRequested',
      'call': call,
      'reason': 'localEnded',
    });
    await pumpEventQueue(times: 20);

    expect(handler.operations, [
      'incoming:call-1',
      'mute:call-1:true',
      'end:call-1:localEnded',
    ]);
    expect(service.ownsIncomingUI('call-1'), isFalse);
    await service.dispose();
    await platform.controller.close();
  });
}
