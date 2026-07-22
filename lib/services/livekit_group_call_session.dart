import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;

import '../models/group_call.dart';
import 'livekit_group_call_api.dart';

enum LiveKitRoomEventKind {
  connected,
  reconnecting,
  reconnected,
  disconnected,
  participantsChanged,
  audioPlaybackChanged,
}

class LiveKitRoomEvent {
  final LiveKitRoomEventKind kind;
  final String? reason;
  final bool? audioPlaying;

  const LiveKitRoomEvent(this.kind, {this.reason, this.audioPlaying});
}

class LiveKitRoomParticipant {
  final String userId;
  final String label;
  final bool isLocal;
  final bool isSpeaking;
  final bool isMuted;
  final bool isCameraEnabled;
  final String connectionQuality;
  final Object? videoTrack;

  const LiveKitRoomParticipant({
    required this.userId,
    required this.label,
    required this.isLocal,
    required this.isSpeaking,
    required this.isMuted,
    required this.isCameraEnabled,
    required this.connectionQuality,
    this.videoTrack,
  });
}

abstract class LiveKitRoomAdapter {
  Stream<LiveKitRoomEvent> get events;
  List<LiveKitRoomParticipant> get participants;
  bool get canPlaybackAudio;
  bool get microphoneEnabled;
  bool get cameraEnabled;

  Future<void> connect(String serverUrl, String token);
  Future<void> setMicrophoneEnabled(bool enabled);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> switchCamera();
  Future<void> setSpeakerOn(bool enabled);
  Future<void> startAudio();
  Future<void> disconnect();
  Future<void> dispose();
}

typedef LiveKitRoomAdapterFactory = LiveKitRoomAdapter Function();

class LiveKitSdkRoomAdapter implements LiveKitRoomAdapter {
  final lk.Room _room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );
  final StreamController<LiveKitRoomEvent> _events =
      StreamController<LiveKitRoomEvent>.broadcast();
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool _disposed = false;

  LiveKitSdkRoomAdapter() {
    _listener = _room.createListener()
      ..on<lk.RoomConnectedEvent>(
        (_) => _emit(const LiveKitRoomEvent(LiveKitRoomEventKind.connected)),
      )
      ..on<lk.RoomReconnectingEvent>(
        (_) => _emit(const LiveKitRoomEvent(LiveKitRoomEventKind.reconnecting)),
      )
      ..on<lk.RoomResumingEvent>(
        (_) => _emit(const LiveKitRoomEvent(LiveKitRoomEventKind.reconnecting)),
      )
      ..on<lk.RoomReconnectedEvent>(
        (_) => _emit(const LiveKitRoomEvent(LiveKitRoomEventKind.reconnected)),
      )
      ..on<lk.RoomDisconnectedEvent>(
        (event) => _emit(
          LiveKitRoomEvent(
            LiveKitRoomEventKind.disconnected,
            reason: event.reason?.toString(),
          ),
        ),
      )
      ..on<lk.ParticipantConnectedEvent>((_) => _participantsChanged())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _participantsChanged())
      ..on<lk.TrackSubscribedEvent>((_) => _participantsChanged())
      ..on<lk.TrackUnsubscribedEvent>((_) => _participantsChanged())
      ..on<lk.TrackMutedEvent>((_) => _participantsChanged())
      ..on<lk.TrackUnmutedEvent>((_) => _participantsChanged())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _participantsChanged())
      ..on<lk.ParticipantConnectionQualityUpdatedEvent>(
        (_) => _participantsChanged(),
      )
      ..on<lk.AudioPlaybackStatusChanged>(
        (event) => _emit(
          LiveKitRoomEvent(
            LiveKitRoomEventKind.audioPlaybackChanged,
            audioPlaying: event.isPlaying,
          ),
        ),
      );
    _room.addListener(_participantsChanged);
  }

  void _emit(LiveKitRoomEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  void _participantsChanged() {
    _emit(const LiveKitRoomEvent(LiveKitRoomEventKind.participantsChanged));
  }

  @override
  Stream<LiveKitRoomEvent> get events => _events.stream;

  String _userId(String identity) =>
      identity.startsWith('u-') ? identity.substring(2) : identity;

  LiveKitRoomParticipant _mapParticipant(
    lk.Participant participant, {
    required bool local,
  }) {
    final publication = participant.getTrackPublicationBySource(
      lk.TrackSource.camera,
    );
    final track = publication != null && !publication.muted
        ? publication.track
        : null;
    return LiveKitRoomParticipant(
      userId: _userId(participant.identity),
      label: participant.name.trim().isEmpty
          ? 'Участник'
          : participant.name.trim(),
      isLocal: local,
      isSpeaking: participant.isSpeaking,
      isMuted: participant.isMuted,
      isCameraEnabled: track is lk.VideoTrack,
      connectionQuality: participant.connectionQuality.name,
      videoTrack: track is lk.VideoTrack ? track : null,
    );
  }

  @override
  List<LiveKitRoomParticipant> get participants {
    final result = <LiveKitRoomParticipant>[];
    final local = _room.localParticipant;
    if (local != null) {
      result.add(_mapParticipant(local, local: true));
    }
    result.addAll(
      _room.remoteParticipants.values.map(
        (participant) => _mapParticipant(participant, local: false),
      ),
    );
    result.sort((left, right) {
      if (left.isSpeaking != right.isSpeaking) {
        return left.isSpeaking ? -1 : 1;
      }
      if (left.isLocal != right.isLocal) return left.isLocal ? -1 : 1;
      return left.label.compareTo(right.label);
    });
    return result;
  }

  @override
  bool get canPlaybackAudio => _room.canPlaybackAudio;

  @override
  bool get microphoneEnabled => !(_room.localParticipant?.isMuted ?? true);

  @override
  bool get cameraEnabled {
    final publication = _room.localParticipant?.getTrackPublicationBySource(
      lk.TrackSource.camera,
    );
    return publication?.track is lk.VideoTrack && publication?.muted != true;
  }

  @override
  Future<void> connect(String serverUrl, String token) =>
      _room.connect(serverUrl, token);

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _room.localParticipant?.setMicrophoneEnabled(enabled);
    _participantsChanged();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    await _room.localParticipant?.setCameraEnabled(enabled);
    _participantsChanged();
  }

  @override
  Future<void> switchCamera() async {
    final publication = _room.localParticipant?.getTrackPublicationBySource(
      lk.TrackSource.camera,
    );
    final track = publication?.track;
    if (track is! lk.LocalVideoTrack) return;
    final options = track.currentOptions;
    final current = options is lk.CameraCaptureOptions
        ? options.cameraPosition
        : lk.CameraPosition.front;
    await track.setCameraPosition(current.switched());
    _participantsChanged();
  }

  @override
  Future<void> setSpeakerOn(bool enabled) => _room.setSpeakerOn(enabled);

  @override
  Future<void> startAudio() => _room.startAudio();

  @override
  Future<void> disconnect() => _room.disconnect();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _room.removeListener(_participantsChanged);
    await _listener?.dispose();
    _listener = null;
    await _room.dispose();
    await _events.close();
  }
}

class LiveKitSessionState {
  final GroupCallPhase phase;
  final String statusMessage;
  final String? disconnectReason;
  final bool isMuted;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool webAudioBlocked;
  final bool cameraFallback;
  final List<GroupCallPeer> participants;

  const LiveKitSessionState({
    required this.phase,
    required this.statusMessage,
    this.disconnectReason,
    this.isMuted = false,
    this.isCameraEnabled = false,
    this.isSpeakerOn = true,
    this.webAudioBlocked = false,
    this.cameraFallback = false,
    this.participants = const [],
  });

  LiveKitSessionState copyWith({
    GroupCallPhase? phase,
    String? statusMessage,
    String? disconnectReason,
    bool? isMuted,
    bool? isCameraEnabled,
    bool? isSpeakerOn,
    bool? webAudioBlocked,
    bool? cameraFallback,
    List<GroupCallPeer>? participants,
  }) {
    return LiveKitSessionState(
      phase: phase ?? this.phase,
      statusMessage: statusMessage ?? this.statusMessage,
      disconnectReason: disconnectReason ?? this.disconnectReason,
      isMuted: isMuted ?? this.isMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      webAudioBlocked: webAudioBlocked ?? this.webAudioBlocked,
      cameraFallback: cameraFallback ?? this.cameraFallback,
      participants: participants ?? this.participants,
    );
  }
}

class LiveKitGroupCallSession {
  final LiveKitGroupTokenSource tokenSource;
  final LiveKitRoomAdapterFactory roomFactory;
  final StreamController<LiveKitSessionState> _states =
      StreamController<LiveKitSessionState>.broadcast();

  LiveKitRoomAdapter? _room;
  StreamSubscription<LiveKitRoomEvent>? _roomEvents;
  int _generation = 0;
  Future<void>? _teardownInFlight;
  LiveKitSessionState _state = const LiveKitSessionState(
    phase: GroupCallPhase.idle,
    statusMessage: '',
  );

  LiveKitGroupCallSession({
    LiveKitGroupTokenSource? tokenSource,
    LiveKitRoomAdapterFactory? roomFactory,
  }) : tokenSource = tokenSource ?? const HttpLiveKitGroupTokenSource(),
       roomFactory = roomFactory ?? LiveKitSdkRoomAdapter.new;

  Stream<LiveKitSessionState> get states => _states.stream;
  LiveKitSessionState get state => _state;

  bool _current(int generation, LiveKitRoomAdapter room) =>
      generation == _generation && identical(_room, room);

  void _emit(LiveKitSessionState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  List<GroupCallPeer> _participants(LiveKitRoomAdapter room) => room
      .participants
      .map(
        (participant) => GroupCallPeer(
          userId: participant.userId,
          label: participant.isLocal ? 'Вы' : participant.label,
          state: 'joined',
          isLocal: participant.isLocal,
          isSpeaking: participant.isSpeaking,
          isMuted: participant.isMuted,
          isCameraEnabled: participant.isCameraEnabled,
          connectionQuality: participant.connectionQuality,
          videoTrack: participant.videoTrack,
        ),
      )
      .toList(growable: false);

  Future<bool> connect({
    required String callId,
    required bool enableCamera,
    required bool speakerOn,
    String? answerTicket,
  }) async {
    final generation = ++_generation;
    await _disposeCurrentRoom();
    if (generation != _generation) return false;
    final room = roomFactory();
    _room = room;
    _emit(
      LiveKitSessionState(
        phase: GroupCallPhase.connecting,
        statusMessage: 'Подключение…',
        isSpeakerOn: speakerOn,
      ),
    );
    _roomEvents = room.events.listen((event) {
      if (!_current(generation, room)) return;
      switch (event.kind) {
        case LiveKitRoomEventKind.connected:
          _emit(
            _state.copyWith(
              phase: GroupCallPhase.connected,
              statusMessage: 'На связи',
              participants: _participants(room),
            ),
          );
          break;
        case LiveKitRoomEventKind.reconnecting:
          _emit(
            _state.copyWith(
              phase: GroupCallPhase.reconnecting,
              statusMessage: 'Восстанавливаем соединение…',
            ),
          );
          break;
        case LiveKitRoomEventKind.reconnected:
          _emit(
            _state.copyWith(
              phase: GroupCallPhase.connected,
              statusMessage: 'На связи',
              participants: _participants(room),
            ),
          );
          break;
        case LiveKitRoomEventKind.disconnected:
          _emit(
            _state.copyWith(
              phase: GroupCallPhase.failed,
              statusMessage: _disconnectMessage(event.reason),
              disconnectReason: event.reason,
            ),
          );
          unawaited(_disposeCurrentRoom());
          break;
        case LiveKitRoomEventKind.participantsChanged:
          _emit(
            _state.copyWith(
              participants: _participants(room),
              isMuted: !room.microphoneEnabled,
              isCameraEnabled: room.cameraEnabled,
            ),
          );
          break;
        case LiveKitRoomEventKind.audioPlaybackChanged:
          _emit(_state.copyWith(webAudioBlocked: event.audioPlaying == false));
          break;
      }
    });

    try {
      final credentials = await tokenSource.fetchToken(
        callId,
        answerTicket: answerTicket,
      );
      if (!_current(generation, room)) {
        await _disposeRoom(room);
        return false;
      }
      await room.connect(credentials.serverUrl, credentials.participantToken);
      if (!_current(generation, room)) {
        await _disposeRoom(room);
        return false;
      }
      await room.setSpeakerOn(speakerOn);
      await room.setMicrophoneEnabled(true);
      var cameraFallback = false;
      if (enableCamera) {
        try {
          await room.setCameraEnabled(true);
        } catch (_) {
          cameraFallback = true;
        }
      }
      try {
        await room.startAudio();
      } catch (_) {}
      if (!_current(generation, room)) {
        await _disposeRoom(room);
        return false;
      }
      _emit(
        _state.copyWith(
          phase: GroupCallPhase.connected,
          statusMessage: cameraFallback
              ? 'Камера недоступна — продолжаем с аудио'
              : 'На связи',
          isMuted: !room.microphoneEnabled,
          isCameraEnabled: room.cameraEnabled,
          isSpeakerOn: speakerOn,
          webAudioBlocked: !room.canPlaybackAudio,
          cameraFallback: cameraFallback,
          participants: _participants(room),
        ),
      );
      return true;
    } catch (_) {
      if (_current(generation, room)) {
        await _disposeCurrentRoom();
        _emit(
          _state.copyWith(
            phase: GroupCallPhase.failed,
            statusMessage: 'Не удалось подключиться к звонку',
          ),
        );
      } else {
        await _disposeRoom(room);
      }
      return false;
    }
  }

  Future<void> setMuted(bool muted) async {
    final room = _room;
    if (room == null) return;
    await room.setMicrophoneEnabled(!muted);
    _emit(
      _state.copyWith(
        isMuted: !room.microphoneEnabled,
        participants: _participants(room),
      ),
    );
  }

  Future<bool> setCameraEnabled(bool enabled) async {
    final room = _room;
    if (room == null) return false;
    try {
      await room.setCameraEnabled(enabled);
      _emit(
        _state.copyWith(
          isCameraEnabled: room.cameraEnabled,
          cameraFallback: false,
          participants: _participants(room),
        ),
      );
      return room.cameraEnabled == enabled;
    } catch (_) {
      _emit(
        _state.copyWith(
          isCameraEnabled: room.cameraEnabled,
          cameraFallback: enabled,
        ),
      );
      return false;
    }
  }

  Future<void> switchCamera() async {
    final room = _room;
    if (room == null || !room.cameraEnabled) return;
    await room.switchCamera();
    _emit(_state.copyWith(participants: _participants(room)));
  }

  Future<void> setSpeakerOn(bool enabled) async {
    final room = _room;
    if (room == null) return;
    await room.setSpeakerOn(enabled);
    _emit(_state.copyWith(isSpeakerOn: enabled));
  }

  Future<void> recoverWebAudio() async {
    final room = _room;
    if (room == null) return;
    await room.startAudio();
    _emit(_state.copyWith(webAudioBlocked: !room.canPlaybackAudio));
  }

  Future<void> disconnect() async {
    ++_generation;
    await _disposeCurrentRoom();
    _emit(
      const LiveKitSessionState(phase: GroupCallPhase.idle, statusMessage: ''),
    );
  }

  Future<void> _disposeCurrentRoom() {
    final inFlight = _teardownInFlight;
    if (inFlight != null) return inFlight;
    final room = _room;
    _room = null;
    final subscription = _roomEvents;
    _roomEvents = null;
    if (room == null && subscription == null) return Future<void>.value();
    final future = () async {
      await subscription?.cancel();
      if (room != null) await _disposeRoom(room);
    }();
    _teardownInFlight = future;
    return future.whenComplete(() {
      if (identical(_teardownInFlight, future)) _teardownInFlight = null;
    });
  }

  Future<void> _disposeRoom(LiveKitRoomAdapter room) async {
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  String _disconnectMessage(String? reason) {
    final normalized = reason?.toLowerCase() ?? '';
    if (normalized.contains('duplicate')) {
      return 'Звонок открыт на другом устройстве';
    }
    return 'Соединение со звонком потеряно';
  }
}
