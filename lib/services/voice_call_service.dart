import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/api_config.dart';
import '../config/webrtc_config.dart';
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

  VoiceCallSnapshot get snapshot => _snapshot;

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

    final micOk = await _ensureMicrophone();
    if (!micOk) {
      _emitFailed('Нет доступа к микрофону');
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

    final sent = _sendSignal({
      'type': 'call_invite',
      'call_id': callId,
      'chat_id': chatId,
    });
    if (!sent) {
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

    final micOk = await _ensureMicrophone();
    if (!micOk) {
      await rejectIncoming(reason: 'no_mic');
      _emitFailed('Нет доступа к микрофону');
      return;
    }

    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connecting,
        statusMessage: 'Соединение…',
      ),
    );
    _sendSignal({
      'type': 'call_accept',
      'call_id': callId,
      'chat_id': chatId,
    });
  }

  Future<void> rejectIncoming({String reason = 'declined'}) async {
    if (_snapshot.phase != VoiceCallPhase.incoming) return;
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
    _emit(
      const VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        statusMessage: 'Отклонён',
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
      await _pc!.setRemoteDescription(desc);
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _sendSignal({
        'type': 'call_answer',
        'call_id': _snapshot.callId,
        'chat_id': _snapshot.chatId,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
      _emit(
        _snapshot.copyWith(
          phase: VoiceCallPhase.connecting,
          statusMessage: 'Соединение…',
        ),
      );
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
      await _pc!.setRemoteDescription(desc);
    } catch (e) {
      if (kDebugMode) print('VoiceCall set answer error: $e');
    }
  }

  Future<void> _onIce(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (_pc == null) return;
    final candidate = event['candidate'];
    if (candidate is! Map) return;
    try {
      await _pc!.addCandidate(
        RTCIceCandidate(
          candidate['candidate']?.toString(),
          candidate['sdpMid']?.toString(),
          candidate['sdpMLineIndex'] is int
              ? candidate['sdpMLineIndex'] as int
              : int.tryParse('${candidate['sdpMLineIndex']}'),
        ),
      );
    } catch (e) {
      if (kDebugMode) print('VoiceCall ICE error: $e');
    }
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
    if (_pc != null) return;
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
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _emit(
          _snapshot.copyWith(
            phase: VoiceCallPhase.connected,
            statusMessage: 'На связи',
          ),
        );
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _emitFailed('Соединение потеряно');
        unawaited(hangUp());
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
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
          _iceServers = (body['iceServers'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          if (_iceServers!.isNotEmpty) return _iceServers!;
        }
      }
    } catch (_) {}
    _iceServers = WebRtcConfig.defaultIceServers;
    return _iceServers!;
  }

  Future<bool> _ensureMicrophone() async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      for (final t in stream.getTracks()) {
        await t.stop();
      }
      return true;
    } catch (e) {
      if (kDebugMode) print('VoiceCall mic permission: $e');
      return false;
    }
  }

  Future<void> _tearDownMedia() async {
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
