import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/api_config.dart';
import '../config/webrtc_config.dart';
import '../utils/microphone_permission.dart';
import '../utils/timed_http.dart';
import '../utils/webrtc_device_support.dart';
import 'storage_service.dart';
import 'voice_call_service.dart';
import 'websocket_service.dart';

enum GroupCallPhase {
  idle,
  incoming,
  outgoing,
  connecting,
  connected,
  ended,
  failed,
}

class GroupCallPeer {
  final String userId;
  final String label;
  final String state; // ringing | joined

  const GroupCallPeer({
    required this.userId,
    required this.label,
    required this.state,
  });
}

class GroupCallSnapshot {
  final GroupCallPhase phase;
  final String? callId;
  final String? chatId;
  final String? chatName;
  final String? statusMessage;
  final bool isMuted;
  final List<GroupCallPeer> roster;

  const GroupCallSnapshot({
    this.phase = GroupCallPhase.idle,
    this.callId,
    this.chatId,
    this.chatName,
    this.statusMessage,
    this.isMuted = false,
    this.roster = const [],
  });

  bool get isActive =>
      phase == GroupCallPhase.incoming ||
      phase == GroupCallPhase.outgoing ||
      phase == GroupCallPhase.connecting ||
      phase == GroupCallPhase.connected;

  GroupCallSnapshot copyWith({
    GroupCallPhase? phase,
    String? callId,
    String? chatId,
    String? chatName,
    String? statusMessage,
    bool? isMuted,
    List<GroupCallPeer>? roster,
  }) {
    return GroupCallSnapshot(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      chatId: chatId ?? this.chatId,
      chatName: chatName ?? this.chatName,
      statusMessage: statusMessage ?? this.statusMessage,
      isMuted: isMuted ?? this.isMuted,
      roster: roster ?? this.roster,
    );
  }
}

/// Mesh group voice (≤4). Signaling via `gcall_*` WebSocket messages.
class GroupVoiceCallService {
  GroupVoiceCallService._();
  static final GroupVoiceCallService instance = GroupVoiceCallService._();

  static const int maxParticipants = 4;

  final StreamController<GroupCallSnapshot> _stateController =
      StreamController<GroupCallSnapshot>.broadcast();

  Stream<GroupCallSnapshot> get stateStream => _stateController.stream;
  GroupCallSnapshot _snapshot = const GroupCallSnapshot();

  StreamSubscription<dynamic>? _wsSub;
  String? _myUserId;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Set<String> _remoteDescReady = {};
  List<Map<String, dynamic>>? _iceServers;
  bool _webRtcInitialized = false;
  MicrophoneAccess? _lastMicAccess;
  Timer? _idleResetTimer;
  Timer? _outgoingTimer;

  GroupCallSnapshot get snapshot => _snapshot;
  MicrophoneAccess? get lastMicrophoneAccess => _lastMicAccess;
  MediaStream? remoteStreamFor(String userId) => _remoteStreams[userId];

  void bindUser(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    if (_myUserId == uid && _wsSub != null) return;
    _myUserId = uid;
    _wsSub?.cancel();
    _wsSub = WebSocketService.instance.stream.listen(_onWsEvent);
    unawaited(WebSocketService.instance.connectIfNeeded());
  }

  void reset() {
    _wsSub?.cancel();
    _wsSub = null;
    _myUserId = null;
    _idleResetTimer?.cancel();
    _outgoingTimer?.cancel();
    unawaited(_tearDownAll());
    _emit(const GroupCallSnapshot(phase: GroupCallPhase.idle));
  }

  Future<void> bindUserIfNeeded() async {
    if (_myUserId != null) return;
    final user = await StorageService.getUserData();
    final id = user?['id']?.toString();
    if (id != null && id.isNotEmpty) bindUser(id);
  }

  Future<bool> startGroupCall({
    required String chatId,
    required String chatName,
  }) async {
    try {
      if (VoiceCallService.instance.snapshot.isActive) {
        _emitFailed('Сначала завершите личный звонок');
        return false;
      }
      if (!WebRtcDeviceSupport.webCallsAllowed) {
        _emitFailed(WebRtcDeviceSupport.insecureWebContextMessage);
        return false;
      }
      if (await WebRtcDeviceSupport.isUnsupportedSimulator()) {
        _emitFailed(WebRtcDeviceSupport.unsupportedSimulatorMessage);
        return false;
      }
      if (_snapshot.isActive) {
        _emitFailed('Звонок уже идёт');
        return false;
      }
      await bindUserIfNeeded();
      if (_myUserId == null) {
        _emitFailed('Не удалось начать звонок. Перезайдите в приложение.');
        return false;
      }
      if (!await _ensureMicrophonePermission()) return false;
      if (!await _ensureWebRtcReady()) return false;
      if (!await _ensureSignalingConnected()) {
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
        return false;
      }

      final callId = _newCallId();
      _emit(
        GroupCallSnapshot(
          phase: GroupCallPhase.outgoing,
          callId: callId,
          chatId: chatId,
          chatName: chatName,
          statusMessage: 'Создаём звонок…',
          roster: [
            GroupCallPeer(
              userId: _myUserId!,
              label: 'Вы',
              state: 'joined',
            ),
          ],
        ),
      );
      _startOutgoingTimeout();
      unawaited(_preloadIceServers());

      final sent = _send({
        'type': 'gcall_create',
        'call_id': callId,
        'chat_id': chatId,
      });
      if (!sent) {
        _cancelOutgoingTimeout();
        await _tearDownAll();
        _emitFailed('Нет соединения с сервером');
        return false;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) print('GroupCall start: $e\n$st');
      _cancelOutgoingTimeout();
      await _tearDownAll();
      _emitFailed('Не удалось начать групповой звонок');
      return false;
    }
  }

  Future<void> acceptIncoming() async {
    try {
      if (_snapshot.phase != GroupCallPhase.incoming) return;
      if (VoiceCallService.instance.snapshot.isActive) {
        await rejectIncoming(reason: 'busy');
        _emitFailed('Сначала завершите личный звонок');
        return;
      }
      if (!await _ensureMicrophonePermission()) {
        await rejectIncoming(reason: 'no_mic');
        return;
      }
      if (!await _ensureWebRtcReady()) {
        await rejectIncoming(reason: 'media_error');
        return;
      }
      final callId = _snapshot.callId;
      final chatId = _snapshot.chatId;
      if (callId == null || chatId == null) return;

      _emit(
        _snapshot.copyWith(
          phase: GroupCallPhase.connecting,
          statusMessage: 'Подключение…',
        ),
      );
      _send({
        'type': 'gcall_join',
        'call_id': callId,
        'chat_id': chatId,
      });
    } catch (e, st) {
      if (kDebugMode) print('GroupCall accept: $e\n$st');
      await _tearDownAll();
      _emitFailed('Не удалось присоединиться');
    }
  }

  Future<void> rejectIncoming({String reason = 'declined'}) async {
    if (_snapshot.phase != GroupCallPhase.incoming &&
        _snapshot.phase != GroupCallPhase.connecting) {
      return;
    }
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null) {
      _send({
        'type': 'gcall_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': reason,
      });
    }
    await _tearDownAll();
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        callId: callId,
        chatId: chatId,
        chatName: _snapshot.chatName,
        statusMessage: 'Отклонён',
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> leave() async {
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null && _snapshot.isActive) {
      _send({
        'type': 'gcall_leave',
        'call_id': callId,
        'chat_id': chatId,
      });
    }
    await _tearDownAll();
    _emit(
      const GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        statusMessage: 'Вы вышли',
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> abortActiveCall(String message) async {
    if (!_snapshot.isActive) return;
    await leave();
    _emitFailed(message);
  }

  Future<void> toggleMute() async {
    final stream = _localStream;
    if (stream == null) return;
    final tracks = stream.getAudioTracks();
    if (tracks.isEmpty) return;
    final track = tracks.first;
    track.enabled = !track.enabled;
    _emit(_snapshot.copyWith(isMuted: !track.enabled));
  }

  void applyIncomingFromPush({
    required String callId,
    required String chatId,
    required String chatName,
    required String fromUserId,
    required String fromLabel,
  }) {
    if (callId.isEmpty || chatId.isEmpty) return;
    unawaited(bindUserIfNeeded());
    unawaited(WebSocketService.instance.connectIfNeeded());
    if (_snapshot.isActive) {
      if (_snapshot.callId == callId) return;
      return;
    }
    if (VoiceCallService.instance.snapshot.isActive) return;

    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.incoming,
        callId: callId,
        chatId: chatId,
        chatName: chatName.isNotEmpty ? chatName : 'Группа',
        statusMessage: 'Входящий групповой звонок',
        roster: [
          GroupCallPeer(
            userId: fromUserId,
            label: fromLabel.isNotEmpty ? fromLabel : 'Участник',
            state: 'joined',
          ),
        ],
      ),
    );
  }

  void _onWsEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type == null || !type.startsWith('gcall_')) return;

    switch (type) {
      case 'gcall_invite':
        _onInvite(event);
        break;
      case 'gcall_created':
        _onCreated(event);
        break;
      case 'gcall_joined':
        unawaited(_onJoined(event));
        break;
      case 'gcall_peer_joined':
        unawaited(_onPeerJoined(event));
        break;
      case 'gcall_peer_left':
        unawaited(_onPeerLeft(event));
        break;
      case 'gcall_ended':
        unawaited(_onEnded(event));
        break;
      case 'gcall_offer':
        unawaited(_onOffer(event));
        break;
      case 'gcall_answer':
        unawaited(_onAnswer(event));
        break;
      case 'gcall_ice':
        unawaited(_onIce(event));
        break;
      case 'gcall_error':
        _onError(event);
        break;
    }
  }

  void _onInvite(Map event) {
    final callId = event['call_id']?.toString() ?? '';
    final chatId = event['chat_id']?.toString() ?? '';
    if (callId.isEmpty || chatId.isEmpty) return;

    if (_snapshot.isActive) {
      if (_snapshot.callId == callId) {
        _applyRoster(event);
        return;
      }
      _send({
        'type': 'gcall_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'busy',
      });
      return;
    }
    if (VoiceCallService.instance.snapshot.isActive) {
      _send({
        'type': 'gcall_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'busy',
      });
      return;
    }

    final fromEmail = event['from_user_email']?.toString() ?? '';
    final chatName = event['chat_name']?.toString() ?? 'Группа';
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.incoming,
        callId: callId,
        chatId: chatId,
        chatName: chatName,
        statusMessage: fromEmail.isNotEmpty
            ? '$fromEmail приглашает в звонок'
            : 'Входящий групповой звонок',
        roster: _parseRoster(event),
      ),
    );
    unawaited(_preloadIceServers());
  }

  void _onCreated(Map event) {
    if (!_matchesActive(event) && _snapshot.phase != GroupCallPhase.outgoing) {
      return;
    }
    _cancelOutgoingTimeout();
    _emit(
      _snapshot.copyWith(
        phase: GroupCallPhase.connected,
        callId: event['call_id']?.toString() ?? _snapshot.callId,
        chatId: event['chat_id']?.toString() ?? _snapshot.chatId,
        chatName: event['chat_name']?.toString() ?? _snapshot.chatName,
        statusMessage: 'Ожидание участников…',
        roster: _parseRoster(event),
      ),
    );
    unawaited(_ensureLocalAudio());
  }

  Future<void> _onJoined(Map event) async {
    if (!_matchesActive(event) && _snapshot.phase != GroupCallPhase.connecting) {
      return;
    }
    _emit(
      _snapshot.copyWith(
        phase: GroupCallPhase.connected,
        statusMessage: 'На связи',
        roster: _parseRoster(event),
      ),
    );
    await _ensureLocalAudio();
    // Existing peers will send offers after gcall_peer_joined.
  }

  Future<void> _onPeerJoined(Map event) async {
    if (!_matchesActive(event)) return;
    if (_snapshot.phase != GroupCallPhase.connected &&
        _snapshot.phase != GroupCallPhase.connecting) {
      return;
    }
    _emit(_snapshot.copyWith(roster: _parseRoster(event)));
    final peerId = event['user_id']?.toString() ??
        event['from_user_id']?.toString() ??
        '';
    if (peerId.isEmpty || peerId == _myUserId) return;
    // Existing member creates offer toward the new joiner.
    if (!await _ensureLocalAudio()) return;
    await _createAndSendOfferTo(peerId);
  }

  Future<void> _onPeerLeft(Map event) async {
    if (!_matchesActive(event)) return;
    final peerId = event['from_user_id']?.toString() ?? '';
    if (peerId.isNotEmpty) {
      await _disposePeer(peerId);
    }
    _emit(
      _snapshot.copyWith(
        roster: _parseRoster(event),
        statusMessage: _snapshot.phase == GroupCallPhase.connected
            ? 'На связи'
            : _snapshot.statusMessage,
      ),
    );
  }

  Future<void> _onEnded(Map event) async {
    if (!_matchesActive(event, allowMissing: true)) return;
    await _tearDownAll();
    _emit(
      const GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        statusMessage: 'Звонок завершён',
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> _onOffer(Map event) async {
    if (!_matchesActive(event)) return;
    final fromId = event['from_user_id']?.toString() ?? '';
    if (fromId.isEmpty || fromId == _myUserId) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;

    if (!await _ensureLocalAudio()) return;
    final stream = _localStream;
    if (stream == null || stream.getAudioTracks().isEmpty) return;

    final pc = await _ensurePeerConnection(fromId);
    final desc = RTCSessionDescription(
      sdpMap['sdp']?.toString() ?? '',
      sdpMap['type']?.toString() ?? '',
    );
    await pc.setRemoteDescription(desc);
    _remoteDescReady.add(fromId);
    await _flushIce(fromId);

    for (final track in stream.getAudioTracks()) {
      final senders = await pc.getSenders();
      if (!senders.any((s) => s.track?.kind == 'audio')) {
        await pc.addTrack(track, stream);
      }
    }

    final answer = await pc.createAnswer(<String, dynamic>{});
    await pc.setLocalDescription(answer);
    _send({
      'type': 'gcall_answer',
      'call_id': _snapshot.callId,
      'chat_id': _snapshot.chatId,
      'to_user_id': fromId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
  }

  Future<void> _onAnswer(Map event) async {
    if (!_matchesActive(event)) return;
    final fromId = event['from_user_id']?.toString() ?? '';
    if (fromId.isEmpty) return;
    final pc = _pcs[fromId];
    if (pc == null) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      ),
    );
    _remoteDescReady.add(fromId);
    await _flushIce(fromId);
  }

  Future<void> _onIce(Map event) async {
    if (!_matchesActive(event)) return;
    final fromId = event['from_user_id']?.toString() ?? '';
    if (fromId.isEmpty) return;
    final candidate = event['candidate'];
    if (candidate is! Map) return;
    final ice = RTCIceCandidate(
      candidate['candidate']?.toString(),
      candidate['sdpMid']?.toString(),
      candidate['sdpMLineIndex'] is int
          ? candidate['sdpMLineIndex'] as int
          : int.tryParse('${candidate['sdpMLineIndex']}'),
    );
    if (!_remoteDescReady.contains(fromId)) {
      (_pendingIce[fromId] ??= []).add(ice);
      return;
    }
    final pc = _pcs[fromId];
    if (pc == null) return;
    try {
      await pc.addCandidate(ice);
    } catch (e) {
      if (kDebugMode) print('GroupCall ICE: $e');
    }
  }

  void _onError(Map event) {
    final code = event['code']?.toString() ?? 'error';
    if (_snapshot.isActive &&
        event['call_id'] != null &&
        event['call_id'].toString() != _snapshot.callId) {
      return;
    }
    unawaited(_tearDownAll());
    _emitFailed(_humanize(code));
  }

  Future<void> _createAndSendOfferTo(String peerId) async {
    if (_pcs.containsKey(peerId)) return;
    if (!await _ensureLocalAudio()) return;
    final stream = _localStream;
    if (stream == null || stream.getAudioTracks().isEmpty) return;

    final pc = await _ensurePeerConnection(peerId);
    for (final track in stream.getAudioTracks()) {
      await pc.addTrack(track, stream);
    }
    final offer = await pc.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
    });
    await pc.setLocalDescription(offer);
    _send({
      'type': 'gcall_offer',
      'call_id': _snapshot.callId,
      'chat_id': _snapshot.chatId,
      'to_user_id': peerId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<RTCPeerConnection> _ensurePeerConnection(String peerId) async {
    final existing = _pcs[peerId];
    if (existing != null) return existing;

    final servers = await _loadIceServers();
    await _ensureWebRtcInitialized();
    final pc = await createPeerConnection(<String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _send({
        'type': 'gcall_ice',
        'call_id': _snapshot.callId,
        'chat_id': _snapshot.chatId,
        'to_user_id': peerId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind != 'audio') return;
      try {
        event.track.enabled = true;
      } catch (_) {}
      if (event.streams.isNotEmpty) {
        _remoteStreams[peerId] = event.streams.first;
      }
      if (_snapshot.phase != GroupCallPhase.connected) {
        _emit(_snapshot.copyWith(
          phase: GroupCallPhase.connected,
          statusMessage: 'На связи',
        ));
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (kDebugMode) print('GroupCall ICE[$peerId]: $state');
    };

    _pcs[peerId] = pc;
    return pc;
  }

  Future<void> _flushIce(String peerId) async {
    final pending = _pendingIce.remove(peerId);
    final pc = _pcs[peerId];
    if (pending == null || pc == null) return;
    for (final c in pending) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _disposePeer(String peerId) async {
    _pendingIce.remove(peerId);
    _remoteDescReady.remove(peerId);
    _remoteStreams.remove(peerId);
    final pc = _pcs.remove(peerId);
    try {
      await pc?.dispose();
    } catch (_) {}
  }

  Future<bool> _ensureLocalAudio() async {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (!await _ensureMicrophonePermission()) return false;
    await _prepareAudioSession();
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    return _localStream!.getAudioTracks().isNotEmpty;
  }

  Future<void> _prepareAudioSession() async {
    if (kIsWeb) return;
    try {
      if (WebRTC.platformIsIOS) {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: true,
        );
      } else if (WebRTC.platformIsAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
        await Helper.setSpeakerphoneOn(true);
      }
    } catch (e) {
      if (kDebugMode) print('GroupCall audio session: $e');
    }
  }

  Future<bool> _ensureMicrophonePermission() async {
    final access = await MicrophonePermission.ensure();
    _lastMicAccess = access;
    if (access == MicrophoneAccess.granted) return true;
    _emitFailed(
      access == MicrophoneAccess.permanentlyDenied
          ? (kIsWeb
              ? 'Нет доступа к микрофону в браузере'
              : 'Нет доступа к микрофону. Разрешите в Настройках.')
          : 'Нет доступа к микрофону',
    );
    return false;
  }

  Future<bool> _ensureWebRtcReady() async {
    if (kIsWeb) return true;
    try {
      await _ensureWebRtcInitialized();
      return true;
    } catch (e) {
      _emitFailed('WebRTC недоступен в этой сборке');
      return false;
    }
  }

  Future<void> _ensureWebRtcInitialized() async {
    if (kIsWeb || _webRtcInitialized) return;
    await WebRTC.initialize(
      options: <String, dynamic>{
        'androidAudioConfiguration':
            AndroidAudioConfiguration.communication.toMap(),
      },
    );
    _webRtcInitialized = true;
  }

  Future<bool> _ensureSignalingConnected() async {
    await WebSocketService.instance.connectIfNeeded();
    if (WebSocketService.instance.isConnected) return true;
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (WebSocketService.instance.isConnected) return true;
      if (i == 30 || i == 60) {
        await WebSocketService.instance.connectIfNeeded();
      }
    }
    return WebSocketService.instance.isConnected;
  }

  Future<void> _preloadIceServers() async {
    try {
      await _loadIceServers();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    if (_iceServers != null) return _iceServers!;
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) {
        _iceServers = WebRtcConfig.defaultIceServers;
        return _iceServers!;
      }
      final response = await timedGet(
        Uri.parse('${ApiConfig.baseUrl}/calls/ice-servers'),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['iceServers'] is List) {
          _iceServers = (body['iceServers'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          if (_iceServers!.isNotEmpty) return _iceServers!;
        }
      }
    } catch (e) {
      if (kDebugMode) print('GroupCall ICE: $e');
    }
    _iceServers = WebRtcConfig.defaultIceServers;
    return _iceServers!;
  }

  List<GroupCallPeer> _parseRoster(Map event) {
    final raw = event['roster'];
    if (raw is! List) return _snapshot.roster;
    final out = <GroupCallPeer>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item['user_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final email = item['email']?.toString() ?? '';
      out.add(
        GroupCallPeer(
          userId: id,
          label: id == _myUserId
              ? 'Вы'
              : (email.isNotEmpty ? email : 'Участник'),
          state: item['state']?.toString() ?? 'ringing',
        ),
      );
    }
    return out;
  }

  void _applyRoster(Map event) {
    _emit(_snapshot.copyWith(roster: _parseRoster(event)));
  }

  bool _matchesActive(Map event, {bool allowMissing = false}) {
    final eventCallId = event['call_id']?.toString();
    final activeId = _snapshot.callId;
    if (activeId == null || activeId.isEmpty) return allowMissing;
    if (eventCallId == null || eventCallId.isEmpty) return true;
    return eventCallId == activeId;
  }

  Future<void> _tearDownAll() async {
    _cancelOutgoingTimeout();
    final ids = _pcs.keys.toList();
    for (final id in ids) {
      await _disposePeer(id);
    }
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _iceServers = null;
    _pendingIce.clear();
    _remoteDescReady.clear();
    _remoteStreams.clear();
  }

  bool _send(Map<String, dynamic> payload) {
    return WebSocketService.instance.send(payload);
  }

  String _newCallId() {
    final r = Random();
    return 'g-${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
  }

  void _emit(GroupCallSnapshot next) {
    _snapshot = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _emitFailed(String message) {
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.failed,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        chatName: _snapshot.chatName,
        statusMessage: message,
        roster: _snapshot.roster,
      ),
    );
    _scheduleIdleReset();
  }

  void _scheduleIdleReset() {
    _idleResetTimer?.cancel();
    _idleResetTimer = Timer(const Duration(seconds: 2), () {
      _idleResetTimer = null;
      if (_snapshot.phase == GroupCallPhase.ended ||
          _snapshot.phase == GroupCallPhase.failed) {
        _emit(const GroupCallSnapshot(phase: GroupCallPhase.idle));
      }
    });
  }

  void _startOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = Timer(const Duration(seconds: 20), () {
      if (_snapshot.phase != GroupCallPhase.outgoing) return;
      unawaited(_tearDownAll());
      _emitFailed('Нет ответа от сервера');
    });
  }

  void _cancelOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = null;
  }

  String _humanize(String code) {
    switch (code) {
      case 'busy':
        return 'Вы уже в звонке';
      case 'chat_call_active':
        return 'В этом чате уже идёт звонок';
      case 'room_full':
        return 'В звонке уже максимум участников ($maxParticipants)';
      case 'not_a_group_chat':
        return 'Групповые звонки только в группах';
      case 'not_a_member':
        return 'Нет доступа к чату';
      default:
        return 'Не удалось выполнить групповой звонок';
    }
  }
}
