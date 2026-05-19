import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/api_config.dart';
import '../config/webrtc_config.dart';
import '../utils/microphone_permission.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';
import 'websocket_service.dart';

enum VoiceCallPhase {
  idle,
  incoming,
  outgoing,
  connecting,
  connected,
  ended,
  failed,
}

class VoiceCallSnapshot {
  final VoiceCallPhase phase;
  final String? callId;
  final String? chatId;
  final String? peerUserId;
  final String? peerLabel;
  final String? statusMessage;
  final bool isMuted;

  const VoiceCallSnapshot({
    this.phase = VoiceCallPhase.idle,
    this.callId,
    this.chatId,
    this.peerUserId,
    this.peerLabel,
    this.statusMessage,
    this.isMuted = false,
  });

  bool get isActive =>
      phase == VoiceCallPhase.incoming ||
      phase == VoiceCallPhase.outgoing ||
      phase == VoiceCallPhase.connecting ||
      phase == VoiceCallPhase.connected;

  VoiceCallSnapshot copyWith({
    VoiceCallPhase? phase,
    String? callId,
    String? chatId,
    String? peerUserId,
    String? peerLabel,
    String? statusMessage,
    bool? isMuted,
  }) {
    return VoiceCallSnapshot(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      chatId: chatId ?? this.chatId,
      peerUserId: peerUserId ?? this.peerUserId,
      peerLabel: peerLabel ?? this.peerLabel,
      statusMessage: statusMessage ?? this.statusMessage,
      isMuted: isMuted ?? this.isMuted,
    );
  }
}

/// 1-on-1 voice calls over WebRTC; signaling via global WebSocket.
class VoiceCallService {
  VoiceCallService._();
  static final VoiceCallService instance = VoiceCallService._();

  final StreamController<VoiceCallSnapshot> _stateController =
      StreamController<VoiceCallSnapshot>.broadcast();

  Stream<VoiceCallSnapshot> get stateStream => _stateController.stream;
  VoiceCallSnapshot _snapshot = const VoiceCallSnapshot();

  StreamSubscription<dynamic>? _wsSub;
  String? _myUserId;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  List<Map<String, dynamic>>? _iceServers;
  MicrophoneAccess? _lastMicAccess;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;
  Timer? _connectingTimer;
  Future<void>? _peerConnectionSetupInFlight;
  Future<void>? _localAudioSetupInFlight;
  bool _webRtcInitialized = false;

  VoiceCallSnapshot get snapshot => _snapshot;
  MicrophoneAccess? get lastMicrophoneAccess => _lastMicAccess;

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
    unawaited(_tearDownMedia());
    _emit(const VoiceCallSnapshot(phase: VoiceCallPhase.idle));
  }

  Future<bool> startOutgoingCall({
    required String chatId,
    required String peerUserId,
    required String peerLabel,
  }) async {
    if (kIsWeb) {
      _emitFailed('Голосовые звонки пока только в мобильном приложении');
      return false;
    }
    if (_snapshot.isActive) return false;
    await bindUserIfNeeded();
    if (_myUserId == null) return false;

    if (!await _ensureMicrophonePermission()) {
      return false;
    }

    final callId = _newCallId();
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.outgoing,
        callId: callId,
        chatId: chatId,
        peerUserId: peerUserId,
        peerLabel: peerLabel,
        statusMessage: 'Вызов…',
      ),
    );

    await _ensureWebRtcInitialized();
    if (!await _ensureLocalAudioStream()) {
      await _tearDownMedia();
      _emit(
        VoiceCallSnapshot(
          phase: VoiceCallPhase.failed,
          callId: callId,
          chatId: chatId,
          peerUserId: peerUserId,
          peerLabel: peerLabel,
          statusMessage: _snapshot.statusMessage ??
              'Не удалось включить микрофон для звонка',
        ),
      );
      _scheduleIdleReset();
      return false;
    }

    final sent = _sendSignal({
      'type': 'call_invite',
      'call_id': callId,
      'chat_id': chatId,
    });
    if (!sent) {
      await _tearDownMedia();
      _emitFailed('Нет соединения с сервером');
      return false;
    }
    return true;
  }

  Future<void> acceptIncoming() async {
    if (_snapshot.phase != VoiceCallPhase.incoming) return;
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId == null || chatId == null) return;

    if (!await _ensureMicrophonePermission()) {
      await rejectIncoming(reason: 'no_mic');
      return;
    }

    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connecting,
        statusMessage: 'Соединение…',
      ),
    );
    _startConnectingTimeout();
    try {
      await _ensureWebRtcInitialized();
      if (!await _ensureLocalAudioStream()) {
        await rejectIncoming(reason: 'no_mic');
        return;
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall media prep on accept: $e');
      await rejectIncoming(reason: 'media_error');
      return;
    }
    _sendSignal({
      'type': 'call_accept',
      'call_id': callId,
      'chat_id': chatId,
    });
  }

  Future<void> rejectIncoming({String reason = 'declined'}) async {
    final phase = _snapshot.phase;
    if (phase != VoiceCallPhase.incoming && phase != VoiceCallPhase.connecting) {
      return;
    }
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null) {
      _sendSignal({
        'type': 'call_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': reason,
      });
    }
    await _tearDownMedia();
    final statusMessage = reason == 'no_mic' || reason == 'media_error'
        ? (_snapshot.statusMessage ?? 'Не удалось принять звонок')
        : 'Отклонён';
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        callId: callId,
        chatId: chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        statusMessage: statusMessage,
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> hangUp() async {
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null && _snapshot.isActive) {
      _sendSignal({
        'type': 'call_hangup',
        'call_id': callId,
        'chat_id': chatId,
      });
    }
    await _tearDownMedia();
    _emit(
      const VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        statusMessage: 'Завершён',
      ),
    );
    _scheduleIdleReset();
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

  MediaStream? get remoteStream => _remoteStream;

  Future<void> bindUserIfNeeded() async {
    if (_myUserId != null) return;
    final user = await StorageService.getUserData();
    final id = user?['id']?.toString();
    if (id != null && id.isNotEmpty) bindUser(id);
  }

  /// Входящий звонок из FCM (приложение в фоне / открыто по push).
  void applyIncomingFromPush({
    required String callId,
    required String chatId,
    required String peerUserId,
    required String peerLabel,
  }) {
    if (callId.isEmpty || chatId.isEmpty || peerUserId.isEmpty) return;
    unawaited(bindUserIfNeeded());
    unawaited(WebSocketService.instance.connectIfNeeded());

    if (_snapshot.isActive) {
      if (_snapshot.callId == callId) return;
      return;
    }

    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.incoming,
        callId: callId,
        chatId: chatId,
        peerUserId: peerUserId,
        peerLabel: peerLabel,
        statusMessage: 'Входящий звонок',
      ),
    );
  }

  void _onWsEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type == null || !type.startsWith('call_')) return;

    switch (type) {
      case 'call_invite':
        _onInvite(event);
        break;
      case 'call_accept':
        _onAccept(event);
        break;
      case 'call_reject':
        _onReject(event);
        break;
      case 'call_hangup':
        _onHangup(event);
        break;
      case 'call_busy':
        _onBusy(event);
        break;
      case 'call_offer':
        unawaited(_onOffer(event));
        break;
      case 'call_answer':
        unawaited(_onAnswer(event));
        break;
      case 'call_ice':
        unawaited(_onIce(event));
        break;
      case 'call_error':
        _onError(event);
        break;
    }
  }

  void _onInvite(Map event) {
    if (_snapshot.isActive) {
      final callId = event['call_id']?.toString();
      final chatId = event['chat_id']?.toString();
      if (callId != null && chatId != null) {
        _sendSignal({
          'type': 'call_reject',
          'call_id': callId,
          'chat_id': chatId,
          'reason': 'busy',
        });
      }
      return;
    }
    final fromId = event['from_user_id']?.toString() ?? '';
    final fromEmail = event['from_user_email']?.toString() ?? 'Пользователь';
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.incoming,
        callId: event['call_id']?.toString(),
        chatId: event['chat_id']?.toString(),
        peerUserId: fromId,
        peerLabel: fromEmail,
        statusMessage: 'Входящий звонок',
      ),
    );
  }

  Future<void> _onAccept(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (_snapshot.phase != VoiceCallPhase.outgoing) return;
    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connecting,
        statusMessage: 'Соединение…',
      ),
    );
    _startConnectingTimeout();
    await _ensurePeerConnection();
    try {
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
      await _pc!.setLocalDescription(offer);
      _sendSignal({
        'type': 'call_offer',
        'call_id': _snapshot.callId,
        'chat_id': _snapshot.chatId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (e) {
      if (kDebugMode) print('VoiceCall offer error: $e');
      _emitFailed('Не удалось установить соединение');
      unawaited(hangUp());
    }
  }

  void _onReject(Map event) {
    if (!_matchesActiveCall(event)) return;
    _tearDownMedia();
    _emit(
      const VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        statusMessage: 'Абонент отклонил',
      ),
    );
    _scheduleIdleReset();
  }

  void _onHangup(Map event) {
    if (!_matchesActiveCall(event)) return;
    _tearDownMedia();
    _emit(
      const VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        statusMessage: 'Звонок завершён',
      ),
    );
    _scheduleIdleReset();
  }

  void _onBusy(Map event) {
    if (!_matchesActiveCall(event)) return;
    _tearDownMedia();
    _emit(
      const VoiceCallSnapshot(
        phase: VoiceCallPhase.failed,
        statusMessage: 'Абонент занят',
      ),
    );
    _scheduleIdleReset();
  }

  void _onError(Map event) {
    if (!_matchesActiveCall(event, allowNoCallId: true)) return;
    final code = event['code']?.toString() ?? 'error';
    _tearDownMedia();
    _emitFailed(_humanizeError(code));
  }

  Future<void> _onOffer(Map event) async {
    if (!_matchesActiveCall(event)) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;
    await _ensurePeerConnection();
    try {
      final desc = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      );
      await _setRemoteDescription(desc);
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _sendSignal({
        'type': 'call_answer',
        'call_id': _snapshot.callId,
        'chat_id': _snapshot.chatId,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
      if (_snapshot.phase != VoiceCallPhase.connecting) {
        _emit(
          _snapshot.copyWith(
            phase: VoiceCallPhase.connecting,
            statusMessage: 'Соединение…',
          ),
        );
      }
      _startConnectingTimeout();
    } catch (e) {
      if (kDebugMode) print('VoiceCall answer error: $e');
      _emitFailed('Ошибка согласования медиа');
      unawaited(hangUp());
    }
  }

  Future<void> _onAnswer(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (_pc == null) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;
    try {
      final desc = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      );
      await _setRemoteDescription(desc);
    } catch (e) {
      if (kDebugMode) print('VoiceCall set answer error: $e');
    }
  }

  Future<void> _onIce(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (_pc == null) return;
    final candidate = event['candidate'];
    if (candidate is! Map) return;
    await _addRemoteIceCandidate(_iceCandidateFromMap(candidate));
  }

  bool _matchesActiveCall(Map event, {bool allowNoCallId = false}) {
    final eventCallId = event['call_id']?.toString();
    final activeId = _snapshot.callId;
    if (activeId == null || activeId.isEmpty) {
      return allowNoCallId;
    }
    if (eventCallId == null || eventCallId.isEmpty) return true;
    return eventCallId == activeId;
  }

  Future<void> _ensurePeerConnection() async {
    await _ensureWebRtcInitialized();
    if (!await _ensureLocalAudioStream()) {
      throw StateError('local audio unavailable');
    }
    await _preparePeerConnectionShell();
    await _attachLocalTracksToPeerConnection();
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

  /// На Android getUserMedia падает, если в плагине уже есть PeerConnection с null native PC.
  /// Микрофон включаем до первого createPeerConnection.
  Future<bool> _ensureLocalAudioStream() async {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (!_snapshot.isActive) return false;

    if (_localAudioSetupInFlight != null) {
      await _localAudioSetupInFlight;
      return _localStream != null && _localStream!.getAudioTracks().isNotEmpty;
    }

    final setup = _ensureLocalAudioStreamImpl();
    _localAudioSetupInFlight = setup;
    try {
      return await setup;
    } finally {
      if (identical(_localAudioSetupInFlight, setup)) {
        _localAudioSetupInFlight = null;
      }
    }
  }

  Future<bool> _ensureLocalAudioStreamImpl() async {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (_pc != null) {
      // Уже создали PC без локального аудио — сбрасываем и начинаем заново.
      await _tearDownMedia();
    }

    if (!await _ensureMicrophonePermission()) {
      return false;
    }

    await _prepareAudioSessionForCall();
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      return _localStream!.getAudioTracks().isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('VoiceCall getUserMedia: $e');
      final err = e.toString().toLowerCase();
      final notAllowed = err.contains('notallowed') ||
          err.contains('permission') ||
          err.contains('denied');
      _emitFailed(
        notAllowed
            ? 'Нет доступа к микрофону'
            : 'Не удалось запустить аудио для звонка',
      );
      if (_snapshot.isActive) {
        unawaited(hangUp());
      }
      return false;
    }
  }

  Future<void> _preparePeerConnectionShell() async {
    if (_pc != null) return;
    if (!_snapshot.isActive) return;

    if (_peerConnectionSetupInFlight != null) {
      await _peerConnectionSetupInFlight;
      return;
    }

    final setup = _preparePeerConnectionShellImpl();
    _peerConnectionSetupInFlight = setup;
    try {
      await setup;
    } finally {
      if (identical(_peerConnectionSetupInFlight, setup)) {
        _peerConnectionSetupInFlight = null;
      }
    }
  }

  Future<void> _preparePeerConnectionShellImpl() async {
    if (_pc != null || !_snapshot.isActive) return;

    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    await _prepareAudioSessionForCall();

    final servers = await _loadIceServers();
    final config = <String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    };
    _pc = await createPeerConnection(config);

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_snapshot.callId == null || _snapshot.chatId == null) return;
      _sendSignal({
        'type': 'call_ice',
        'call_id': _snapshot.callId,
        'chat_id': _snapshot.chatId,
        'candidate': candidate.toMap(),
      });
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind != 'audio') return;
      unawaited(_bindRemoteAudioTrack(event));
    };

    _pc!.onAddStream = (MediaStream stream) {
      unawaited(_handleRemoteStream(stream));
    };

    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _emitFailed('Не удалось установить медиа-соединение (ICE)');
        unawaited(hangUp());
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _emitFailed('Соединение потеряно');
        unawaited(hangUp());
      }
    };

    try {
      await _pc!.getSignalingState();
    } catch (e) {
      if (kDebugMode) print('VoiceCall PC not ready: $e');
      await _tearDownMedia();
      rethrow;
    }
  }

  Future<void> _attachLocalTracksToPeerConnection() async {
    if (_pc == null || !_snapshot.isActive) return;
    final stream = _localStream;
    if (stream == null || stream.getAudioTracks().isEmpty) {
      throw StateError('local audio stream missing');
    }

    final senders = await _pc!.getSenders();
    final hasAudio = senders.any((s) => s.track?.kind == 'audio');
    if (hasAudio) return;

    for (final track in stream.getAudioTracks()) {
      await _pc!.addTrack(track, stream);
    }
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
          _iceServers = _normalizeIceServers(
            (body['iceServers'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
          );
          if (_iceServers!.isNotEmpty) return _iceServers!;
        }
      }
    } catch (_) {}
    _iceServers = WebRtcConfig.defaultIceServers;
    return _iceServers!;
  }

  Future<bool> _ensureMicrophonePermission() async {
    final access = await MicrophonePermission.ensure();
    _lastMicAccess = access;
    switch (access) {
      case MicrophoneAccess.granted:
        return true;
      case MicrophoneAccess.permanentlyDenied:
        _emitFailed(
          'Нет доступа к микрофону. Разрешите в Настройках → Reollity → Микрофон.',
        );
        return false;
      case MicrophoneAccess.denied:
        _emitFailed('Нет доступа к микрофону');
        return false;
    }
  }

  Future<void> _prepareAudioSessionForCall() async {
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
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall audio session: $e');
    }
  }

  Future<void> _bindRemoteAudioTrack(RTCTrackEvent event) async {
    if (event.streams.isNotEmpty) {
      await _handleRemoteStream(event.streams.first);
      return;
    }
    final stream =
        await createLocalMediaStream('remote-audio-${_snapshot.callId ?? "call"}');
    await stream.addTrack(event.track);
    await _handleRemoteStream(stream);
  }

  Future<void> _handleRemoteStream(MediaStream stream) async {
    if (stream.getAudioTracks().isEmpty) return;
    _remoteStream = stream;
    _markConnected();
  }

  void _markConnected() {
    if (_snapshot.phase == VoiceCallPhase.connected) return;
    _cancelConnectingTimeout();
    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connected,
        statusMessage: 'На связи',
      ),
    );
  }

  void _startConnectingTimeout() {
    _connectingTimer?.cancel();
    _connectingTimer = Timer(const Duration(seconds: 45), () {
      if (_snapshot.phase != VoiceCallPhase.connecting) return;
      _emitFailed(
        'Не удалось соединиться. Проверьте интернет; на сервере нужен TURN (UDP 3478 и 49152–49252).',
      );
      unawaited(hangUp());
    });
  }

  void _cancelConnectingTimeout() {
    _connectingTimer?.cancel();
    _connectingTimer = null;
  }

  RTCIceCandidate _iceCandidateFromMap(Map candidate) {
    return RTCIceCandidate(
      candidate['candidate']?.toString(),
      candidate['sdpMid']?.toString(),
      candidate['sdpMLineIndex'] is int
          ? candidate['sdpMLineIndex'] as int
          : int.tryParse('${candidate['sdpMLineIndex']}'),
    );
  }

  Future<void> _setRemoteDescription(RTCSessionDescription desc) async {
    if (_pc == null) return;
    await _pc!.setRemoteDescription(desc);
    _remoteDescriptionSet = true;
    await _flushPendingIceCandidates();
  }

  Future<void> _addRemoteIceCandidate(RTCIceCandidate candidate) async {
    if (_pc == null) return;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await _pc!.addCandidate(candidate);
    } catch (e) {
      if (kDebugMode) print('VoiceCall ICE error: $e');
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    if (_pc == null || _pendingRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (e) {
        if (kDebugMode) print('VoiceCall ICE flush error: $e');
      }
    }
  }

  List<Map<String, dynamic>> _normalizeIceServers(
    List<Map<String, dynamic>> servers,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final raw in servers) {
      final map = Map<String, dynamic>.from(raw);
      final urls = map['urls'];
      if (urls is String) {
        final parts = urls
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        map['urls'] = parts.length == 1 ? parts.first : parts;
      }
      out.add(map);
    }
    return out;
  }

  void _resetPeerConnectionState() {
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    _cancelConnectingTimeout();
  }

  Future<void> _tearDownMedia() async {
    _resetPeerConnectionState();
    _peerConnectionSetupInFlight = null;
    _localAudioSetupInFlight = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _remoteStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  bool _sendSignal(Map<String, dynamic> payload) {
    return WebSocketService.instance.send(payload);
  }

  String _newCallId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
  }

  void _emit(VoiceCallSnapshot next) {
    _snapshot = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _emitFailed(String message) {
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.failed,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        statusMessage: message,
      ),
    );
    _scheduleIdleReset();
  }

  void _scheduleIdleReset() {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_snapshot.phase == VoiceCallPhase.ended ||
          _snapshot.phase == VoiceCallPhase.failed) {
        _emit(const VoiceCallSnapshot(phase: VoiceCallPhase.idle));
      }
    });
  }

  String _humanizeError(String code) {
    switch (code) {
      case 'group_calls_not_supported':
        return 'Звонки только в личных чатах';
      case 'busy':
        return 'Вы уже в звонке';
      case 'not_a_member':
        return 'Нет доступа к чату';
      default:
        return 'Не удалось выполнить звонок';
    }
  }
}
