import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/group_call.dart';
import 'package:my_chat_app/services/livekit_group_call_api.dart';
import 'package:my_chat_app/services/livekit_group_call_session.dart';

class _TokenSource implements LiveKitGroupTokenSource {
  final Map<String, Completer<LiveKitGroupToken>> pending = {};

  @override
  Future<LiveKitGroupToken> fetchToken(String callId, {String? answerTicket}) {
    return (pending[callId] ??= Completer<LiveKitGroupToken>()).future;
  }

  void complete(String callId) {
    pending[callId]!.complete(
      LiveKitGroupToken(
        serverUrl: 'wss://fake.livekit.invalid',
        participantToken: 'token-$callId',
        roomName: 'room-$callId',
        participantName: 'User',
      ),
    );
  }
}

class _FakeRoom implements LiveKitRoomAdapter {
  final StreamController<LiveKitRoomEvent> controller =
      StreamController<LiveKitRoomEvent>.broadcast();
  final List<LiveKitRoomParticipant> currentParticipants = [];
  bool allowAudio = true;
  bool failCamera = false;
  bool connected = false;
  bool disposed = false;
  bool _microphoneEnabled = false;
  bool _cameraEnabled = false;
  bool _canPlaybackAudio = false;
  int connectCount = 0;
  int disconnectCount = 0;
  int disposeCount = 0;
  int cameraSetCount = 0;
  int microphoneSetCount = 0;
  int switchCameraCount = 0;
  int speakerSetCount = 0;
  int startAudioCount = 0;

  @override
  Stream<LiveKitRoomEvent> get events => controller.stream;

  @override
  List<LiveKitRoomParticipant> get participants =>
      List.unmodifiable(currentParticipants);

  @override
  bool get canPlaybackAudio => _canPlaybackAudio;

  @override
  bool get cameraEnabled => _cameraEnabled;

  @override
  bool get microphoneEnabled => _microphoneEnabled;

  @override
  Future<void> connect(String serverUrl, String token) async {
    connectCount++;
    connected = true;
    controller.add(const LiveKitRoomEvent(LiveKitRoomEventKind.connected));
  }

  @override
  Future<void> disconnect() async {
    if (!connected) return;
    connected = false;
    disconnectCount++;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    disposeCount++;
    await controller.close();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    cameraSetCount++;
    if (enabled && failCamera) throw StateError('camera denied');
    _cameraEnabled = enabled;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    microphoneSetCount++;
    _microphoneEnabled = enabled;
  }

  @override
  Future<void> setSpeakerOn(bool enabled) async {
    speakerSetCount++;
  }

  @override
  Future<void> startAudio() async {
    startAudioCount++;
    _canPlaybackAudio = allowAudio;
    controller.add(
      LiveKitRoomEvent(
        LiveKitRoomEventKind.audioPlaybackChanged,
        audioPlaying: _canPlaybackAudio,
      ),
    );
  }

  @override
  Future<void> switchCamera() async {
    switchCameraCount++;
  }

  void emit(LiveKitRoomEvent event) => controller.add(event);
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('audio connect maps participants without enabling camera', () async {
    final source = _TokenSource();
    final room = _FakeRoom()
      ..currentParticipants.addAll(const [
        LiveKitRoomParticipant(
          userId: '1',
          label: 'Host',
          isLocal: true,
          isSpeaking: false,
          isMuted: false,
          isCameraEnabled: false,
          connectionQuality: 'excellent',
        ),
        LiveKitRoomParticipant(
          userId: '2',
          label: 'Guest',
          isLocal: false,
          isSpeaking: true,
          isMuted: true,
          isCameraEnabled: true,
          connectionQuality: 'good',
          videoTrack: 'fake-track',
        ),
      ]);
    final session = LiveKitGroupCallSession(
      tokenSource: source,
      roomFactory: () => room,
    );

    final connecting = session.connect(
      callId: 'audio',
      enableCamera: false,
      speakerOn: true,
    );
    await _flushEvents();
    source.complete('audio');
    expect(await connecting, isTrue);

    expect(room.microphoneSetCount, 1);
    expect(room.cameraSetCount, 0);
    expect(session.state.phase, GroupCallPhase.connected);
    expect(session.state.participants.first.label, 'Вы');
    expect(session.state.participants[1].isSpeaking, isTrue);
    expect(session.state.participants[1].videoTrack, 'fake-track');
    await session.disconnect();
  });

  test(
    'camera denial falls back to audio and reconnect is non-terminal',
    () async {
      final source = _TokenSource();
      final room = _FakeRoom()..failCamera = true;
      final session = LiveKitGroupCallSession(
        tokenSource: source,
        roomFactory: () => room,
      );
      final connecting = session.connect(
        callId: 'video',
        enableCamera: true,
        speakerOn: true,
      );
      await _flushEvents();
      source.complete('video');
      expect(await connecting, isTrue);
      expect(session.state.cameraFallback, isTrue);
      expect(session.state.isCameraEnabled, isFalse);
      expect(room.microphoneEnabled, isTrue);

      room.emit(const LiveKitRoomEvent(LiveKitRoomEventKind.reconnecting));
      await _flushEvents();
      expect(session.state.phase, GroupCallPhase.reconnecting);
      room.emit(const LiveKitRoomEvent(LiveKitRoomEventKind.reconnected));
      await _flushEvents();
      expect(session.state.phase, GroupCallPhase.connected);
      await session.disconnect();
    },
  );

  test('controls and web autoplay recovery delegate to room', () async {
    final source = _TokenSource();
    final room = _FakeRoom()..allowAudio = false;
    final session = LiveKitGroupCallSession(
      tokenSource: source,
      roomFactory: () => room,
    );
    final connecting = session.connect(
      callId: 'controls',
      enableCamera: false,
      speakerOn: true,
    );
    await _flushEvents();
    source.complete('controls');
    expect(await connecting, isTrue);
    expect(session.state.webAudioBlocked, isTrue);

    await session.setMuted(true);
    expect(session.state.isMuted, isTrue);
    expect(await session.setCameraEnabled(true), isTrue);
    await session.switchCamera();
    await session.setSpeakerOn(false);
    room.allowAudio = true;
    await session.recoverWebAudio();

    expect(room.cameraSetCount, 1);
    expect(room.switchCameraCount, 1);
    expect(room.speakerSetCount, 2);
    expect(session.state.webAudioBlocked, isFalse);
    await session.disconnect();
    await session.disconnect();
    expect(room.disconnectCount, 1);
    expect(room.disposeCount, 1);
  });

  test('terminal disconnect disposes room exactly once', () async {
    final source = _TokenSource();
    final room = _FakeRoom();
    final session = LiveKitGroupCallSession(
      tokenSource: source,
      roomFactory: () => room,
    );
    final connecting = session.connect(
      callId: 'terminal',
      enableCamera: false,
      speakerOn: true,
    );
    await _flushEvents();
    source.complete('terminal');
    expect(await connecting, isTrue);

    room.emit(
      const LiveKitRoomEvent(
        LiveKitRoomEventKind.disconnected,
        reason: 'duplicate_identity',
      ),
    );
    await _flushEvents();
    expect(session.state.phase, GroupCallPhase.failed);
    expect(session.state.statusMessage, contains('другом устройстве'));
    expect(room.disposeCount, 1);
    await session.disconnect();
    expect(room.disposeCount, 1);
  });

  test('stale async token cannot replace newer call generation', () async {
    final source = _TokenSource();
    final rooms = <_FakeRoom>[];
    final session = LiveKitGroupCallSession(
      tokenSource: source,
      roomFactory: () {
        final room = _FakeRoom();
        rooms.add(room);
        return room;
      },
    );

    final first = session.connect(
      callId: 'old',
      enableCamera: false,
      speakerOn: true,
    );
    await _flushEvents();
    final second = session.connect(
      callId: 'new',
      enableCamera: false,
      speakerOn: true,
    );
    await _flushEvents();
    source.complete('new');
    expect(await second, isTrue);
    source.complete('old');
    expect(await first, isFalse);

    expect(rooms.length, 2);
    expect(rooms.first.disposeCount, 1);
    expect(rooms.last.connectCount, 1);
    expect(session.state.phase, GroupCallPhase.connected);
    await session.disconnect();
  });
}
