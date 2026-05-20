import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/api_config.dart';
import '../config/webrtc_config.dart';
import '../utils/microphone_permission.dart';
import '../utils/webrtc_device_support.dart';
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
  static const int _maxPendingRemoteCandidates = 80;
  bool _remoteDescriptionSet = false;
  Timer? _connectingTimer;
  Timer? _outgoingTimer;
  Timer? _idleResetTimer;
  Future<void>? _peerConnectionSetupInFlight;
  Future<void>? _localAudioSetupInFlight;
  bool _webRtcInitialized = false;
  bool _hasTurnServer = false;
  /// После сбойного createPeerConnection повторный getUserMedia на Android падает (баг плагина).
  bool _webRtcMediaBroken = false;

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
    _idleResetTimer?.cancel();
    _idleResetTimer = null;
    _lastMicAccess = null;
    _webRtcMediaBroken = false;
    unawaited(_tearDownMedia());
    _emit(const VoiceCallSnapshot(phase: VoiceCallPhase.idle));
  }

  Future<bool> startOutgoingCall({
    required String chatId,
    required String peerUserId,
    required String peerLabel,
  }) async {
    try {
      if (kIsWeb) {
        _emitFailed('Голосовые звонки пока только в мобильном приложении');
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

      if (!await _ensureMicrophonePermission()) {
        return false;
      }

      // Заранее проверяем, что нативный flutter_webrtc вообще доступен.
      // Если на iOS release сломан pod install — здесь же отдадим понятное
      // сообщение, а не упадём на середине offer/answer когда peer уже принял.
      if (!await _ensureWebRtcReady()) {
        return false;
      }

      if (!await _ensureSignalingConnected()) {
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
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
      _startOutgoingTimeout();

      // Микрофон и PeerConnection — только после call_accept (см. _createAndSendOffer).
      unawaited(_preloadIceServers());

      final sent = _sendSignal({
        'type': 'call_invite',
        'call_id': callId,
        'chat_id': chatId,
      });
      if (!sent) {
        _cancelOutgoingTimeout();
        await _tearDownMedia();
        _emitFailed('Нет соединения с сервером');
        return false;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall startOutgoingCall: $e\n$st');
      _cancelOutgoingTimeout();
      await _tearDownMedia();
      _emitFailed('Не удалось начать звонок: ${_shortError(e)}');
      return false;
    }
  }

  String _shortError(Object e) {
    final raw = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isEmpty) return 'неизвестная ошибка';
    return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
  }

  /// Сброс активного звонка, если UI не удалось открыть (см. [VoiceCallHost]).
  Future<void> abortActiveCall(String message) async {
    if (!_snapshot.isActive) return;
    await hangUp();
    _emitFailed(message);
  }

  Future<bool> _ensureSignalingConnected() async {
    await WebSocketService.instance.connectIfNeeded();
    if (WebSocketService.instance.isConnected) return true;
    // На iOS release TLS+WS handshake может занять заметно больше времени, чем
    // в Android-эмуляторе. 10 с — компромисс между «звонок реально не начнётся
    // быстро» и «не оставлять кнопку без ответа».
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (WebSocketService.instance.isConnected) return true;
      if (i == 30 || i == 60) {
        // Триггерим повторное connectIfNeeded, если первая попытка отвалилась.
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

  Future<void> acceptIncoming() async {
    // Кнопка «Принять» в UI вызывает acceptIncoming через `unawaited(...)`,
    // т.е. любая внезапная ошибка (MissingPluginException, ошибка mic и т.д.)
    // молча терялась — пользователь видел, что «Принять» ничего не делает.
    // Ловим всё локально и переводим звонок в failed с понятным текстом.
    try {
      if (_snapshot.phase != VoiceCallPhase.incoming) return;
      if (await WebRtcDeviceSupport.isUnsupportedSimulator()) {
        _emitFailed(WebRtcDeviceSupport.unsupportedSimulatorMessage);
        await rejectIncoming(reason: 'media_error');
        return;
      }
      final callId = _snapshot.callId;
      final chatId = _snapshot.chatId;
      if (callId == null || chatId == null) return;

      if (!await _ensureMicrophonePermission()) {
        await rejectIncoming(reason: 'no_mic');
        return;
      }

      // Тот же ранний контракт, что и в startOutgoingCall: если flutter_webrtc
      // не зарегистрирован, peer не должен узнать о принятии звонка.
      if (!await _ensureWebRtcReady()) {
        await rejectIncoming(reason: 'media_error');
        return;
      }

      _emit(
        _snapshot.copyWith(
          phase: VoiceCallPhase.connecting,
          statusMessage: _connectingStatusHint(),
        ),
      );
      _startConnectingTimeout();
      final sent = _sendSignal({
        'type': 'call_accept',
        'call_id': callId,
        'chat_id': chatId,
      });
      if (!sent) {
        _cancelConnectingTimeout();
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
      }
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall acceptIncoming: $e\n$st');
      _cancelConnectingTimeout();
      await _tearDownMedia();
      _emitFailed('Не удалось принять звонок: ${_shortError(e)}');
    }
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

  /// Завершить активный звонок изнутри (медиа-ошибка, ICE failed, timeout),
  /// сохранив детальный [message] в snapshot.statusMessage.
  ///
  /// Чистый [hangUp] поверх любого failed-сообщения затирает текст на "Завершён";
  /// в катчах внутренних путей это убивало диагностику ("вызов завершён" вместо
  /// "Не удалось запустить аудио для звонка: …"). Этот хелпер сначала шлёт
  /// call_hangup peer-у пока snapshot ещё активен, потом эмитит failed с
  /// сохранением деталей.
  Future<void> _finalizeFailedCall(String message) async {
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null && _snapshot.isActive) {
      _sendSignal({
        'type': 'call_hangup',
        'call_id': callId,
        'chat_id': chatId,
      });
    }
    _emitFailed(message);
    await _tearDownMedia();
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
    final inviteCallId = event['call_id']?.toString();
    final inviteChatId = event['chat_id']?.toString();

    if (_snapshot.isActive) {
      if (inviteCallId != null && inviteCallId == _snapshot.callId) {
        return;
      }
      // Оба нажали «позвонить» в одном чате: отменяем свой исходящий и показываем входящий.
      if (inviteChatId != null &&
          inviteChatId == _snapshot.chatId &&
          _snapshot.phase == VoiceCallPhase.outgoing) {
        unawaited(_replaceOutgoingWithIncoming(event));
        return;
      }
      if (inviteCallId != null && inviteChatId != null) {
        _sendSignal({
          'type': 'call_reject',
          'call_id': inviteCallId,
          'chat_id': inviteChatId,
          'reason': 'busy',
        });
      }
      return;
    }
    _applyIncomingInvite(event);
  }

  void _applyIncomingInvite(Map event) {
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
    unawaited(_preloadIceServers());
  }

  Future<void> _replaceOutgoingWithIncoming(Map event) async {
    _cancelOutgoingTimeout();
    final oldCallId = _snapshot.callId;
    final oldChatId = _snapshot.chatId;
    await _tearDownMedia();
    if (oldCallId != null && oldChatId != null) {
      _sendSignal({
        'type': 'call_hangup',
        'call_id': oldCallId,
        'chat_id': oldChatId,
      });
    }
    _applyIncomingInvite(event);
  }

  Future<void> _onAccept(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (_snapshot.phase != VoiceCallPhase.outgoing) return;
    _cancelOutgoingTimeout();
    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connecting,
        statusMessage: _connectingStatusHint(),
      ),
    );
    _startConnectingTimeout();
    try {
      await _createAndSendOffer();
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall offer error: $e\n$st');
      // Под-вызов мог уже сам позвать _finalizeFailedCall с детальным
      // сообщением — не затираем его generic-текстом.
      final alreadyFailed = _snapshot.phase == VoiceCallPhase.failed ||
          _snapshot.phase == VoiceCallPhase.ended ||
          _snapshot.phase == VoiceCallPhase.idle;
      if (!alreadyFailed) {
        final msg = _webRtcMediaBroken
            ? 'Ошибка WebRTC. Полностью закройте приложение и откройте снова.'
            : 'Не удалось установить соединение: ${_shortError(e)}';
        unawaited(_finalizeFailedCall(msg));
      }
    }
  }

  void _onReject(Map event) {
    if (!_matchesActiveCall(event)) return;
    _cancelOutgoingTimeout();
    _tearDownMedia();
    final reason = event['reason']?.toString() ?? 'declined';
    final statusMessage = reason == 'busy'
        ? 'Абонент занят'
        : reason == 'no_mic' || reason == 'media_error'
            ? 'Абонент не смог принять звонок'
            : 'Абонент отклонил';
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        statusMessage: statusMessage,
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
    try {
      final desc = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      );
      if (desc.sdp == null || desc.sdp!.isEmpty) return;

      if (_snapshot.phase != VoiceCallPhase.connecting) {
        _emit(
          _snapshot.copyWith(
            phase: VoiceCallPhase.connecting,
            statusMessage: _connectingStatusHint(),
          ),
        );
      }
      _startConnectingTimeout();

      await _createAndSendAnswer(desc);
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall answer error: $e\n$st');
      final alreadyFailed = _snapshot.phase == VoiceCallPhase.failed ||
          _snapshot.phase == VoiceCallPhase.ended ||
          _snapshot.phase == VoiceCallPhase.idle;
      if (!alreadyFailed) {
        unawaited(
          _finalizeFailedCall('Ошибка согласования медиа: ${_shortError(e)}'),
        );
      }
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

  String _connectingStatusHint() {
    if (!_hasTurnServer) {
      return 'Соединение… (без TURN часть сетей не соединится)';
    }
    return 'Соединение…';
  }

  /// Offerer (звонящий после call_accept): PC → микрофон → offer.
  Future<void> _createAndSendOffer() async {
    await _preparePeerConnectionShell();
    if (!await _ensureLocalAudioStream()) {
      throw StateError('local audio unavailable');
    }
    await _attachLocalTracksToPeerConnection();

    final offer = await _pc!.createOffer(<String, dynamic>{});
    await _pc!.setLocalDescription(offer);
    if (kDebugMode) {
      print('VoiceCall: offer created, sdp length=${offer.sdp?.length ?? 0}');
    }

    final sent = _sendSignal({
      'type': 'call_offer',
      'call_id': _snapshot.callId,
      'chat_id': _snapshot.chatId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
    if (!sent) {
      throw StateError('failed to send call_offer');
    }
  }

  /// Answerer: PC → remote offer → микрофон → answer (unified-plan).
  Future<void> _createAndSendAnswer(RTCSessionDescription remoteOffer) async {
    await _preparePeerConnectionShell();
    await _setRemoteDescription(remoteOffer);
    if (!await _ensureLocalAudioStream()) {
      throw StateError('local audio unavailable');
    }
    await _attachLocalTracksToPeerConnection();

    final answer = await _pc!.createAnswer(<String, dynamic>{});
    await _pc!.setLocalDescription(answer);
    if (kDebugMode) {
      print('VoiceCall: answer created, sdp length=${answer.sdp?.length ?? 0}');
    }

    final sent = _sendSignal({
      'type': 'call_answer',
      'call_id': _snapshot.callId,
      'chat_id': _snapshot.chatId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
    if (!sent) {
      throw StateError('failed to send call_answer');
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

  /// Ранний sanity-check на доступность flutter_webrtc. На iOS release часто
  /// прилетает MissingPluginException, если pod-ы не подтянулись (та же
  /// причина, что у permission_handler). Хотим узнать до отправки сигнала, а
  /// не на половине offer/answer-handshake, когда peer уже думает «приняли».
  Future<bool> _ensureWebRtcReady() async {
    if (kIsWeb) return true;
    try {
      await _ensureWebRtcInitialized();
      return true;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall WebRTC not ready: $e\n$st');
      _emitFailed(
        'WebRTC недоступен в этой сборке. '
        'Пересоберите приложение из чистого состояния (pod install). '
        'Детали: ${_shortError(e)}',
      );
      return false;
    }
  }

  Future<bool> _ensureLocalAudioStream() async {
    if (_webRtcMediaBroken) {
      _emitFailed(
        'Ошибка WebRTC. Полностью закройте приложение и откройте снова.',
      );
      return false;
    }
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (!_snapshot.isActive) return false;
    if (_pc == null) {
      if (kDebugMode) print('VoiceCall getUserMedia: PeerConnection missing');
      return false;
    }

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
      if (err.contains('peerconnection') ||
          err.contains('transceivers') ||
          err.contains('nullpointer')) {
        _markWebRtcMediaBroken();
      }
      final notAllowed = err.contains('notallowed') ||
          err.contains('permission') ||
          err.contains('denied');
      final msg = _webRtcMediaBroken
          ? 'Ошибка WebRTC. Полностью закройте приложение и откройте снова.'
          : notAllowed
              ? 'Нет доступа к микрофону'
              : 'Не удалось запустить аудио: ${_shortError(e)}';
      await _finalizeFailedCall(msg);
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

  Future<bool> _isPeerConnectionAlive(RTCPeerConnection pc) async {
    try {
      final state = await pc.getSignalingState();
      return state != null;
    } catch (e) {
      if (kDebugMode) print('VoiceCall PC alive check: $e');
      return false;
    }
  }

  Future<void> _disposePeerConnectionSafe(RTCPeerConnection? pc) async {
    if (pc == null) return;
    try {
      await pc.dispose();
      // iOS: дать нативному слою сбросить eventSink до следующего createPeerConnection.
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall dispose PC: $e');
    }
  }

  void _markWebRtcMediaBroken() {
    _webRtcMediaBroken = true;
  }

  List<Map<String, dynamic>> _iceServersStunOnly(
    List<Map<String, dynamic>> servers,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final raw in servers) {
      final urls = raw['urls'];
      final List<String> stunUrls;
      if (urls is List) {
        stunUrls = urls.map((e) => e.toString()).where((u) => u.startsWith('stun:')).toList();
      } else {
        final u = urls?.toString() ?? '';
        stunUrls = u.startsWith('stun:') ? [u] : <String>[];
      }
      if (stunUrls.isEmpty) continue;
      out.add({
        'urls': stunUrls.length == 1 ? stunUrls.first : stunUrls,
      });
    }
    return out;
  }

  Future<RTCPeerConnection> _createAlivePeerConnection() async {
    if (_webRtcMediaBroken) {
      throw StateError('WebRTC media stack broken');
    }

    final full = await _loadIceServers();
    final stunOnly = _iceServersStunOnly(full);
    const defaults = WebRtcConfig.defaultIceServers;
    // Android: full ICE (especially TURN) often yields a null native PC; retries
    // used to leave zombie observers and crash getUserMedia (patched in flutter_webrtc).
    final attempts = <List<Map<String, dynamic>>>[
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
        if (stunOnly.isNotEmpty) stunOnly,
        defaults,
        full,
      ] else ...[
        full,
        if (stunOnly.isNotEmpty) stunOnly,
        defaults,
      ],
    ];

    Object? lastError;
    for (var i = 0; i < attempts.length; i++) {
      final servers = attempts[i];
      RTCPeerConnection? pc;
      try {
        await _ensureWebRtcInitialized();
        await _prepareAudioSessionForCall();

        pc = await createPeerConnection(<String, dynamic>{
          'iceServers': servers,
          'sdpSemantics': 'unified-plan',
          'bundlePolicy': 'max-bundle',
          'rtcpMuxPolicy': 'require',
        });

        if (!await _isPeerConnectionAlive(pc)) {
          if (kDebugMode) {
            print(
              'VoiceCall: native PC null, retry ${i + 1}/${attempts.length} '
              '(servers=${servers.length})',
            );
          }
          await _disposePeerConnectionSafe(pc);
          // Пауза после dispose: нативные колбэки ICE/signaling (см. patch postEvent iOS).
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS)) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          lastError = StateError('native PeerConnection null');
          continue;
        }

        if (kDebugMode) {
          print('VoiceCall: PeerConnection OK on attempt ${i + 1}');
        }
        return pc;
      } catch (e) {
        lastError = e;
        await _disposePeerConnectionSafe(pc);
        if (kDebugMode) print('VoiceCall createPC attempt ${i + 1}: $e');
      }
    }

    _markWebRtcMediaBroken();
    throw lastError ?? StateError('PeerConnection unavailable');
  }

  void _wirePeerConnectionHandlers(RTCPeerConnection pc) {
    _pc = pc;
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (_snapshot.callId == null || _snapshot.chatId == null) return;
      _sendSignal({
        'type': 'call_ice',
        'call_id': _snapshot.callId,
        'chat_id': _snapshot.chatId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind != 'audio') return;
      unawaited(_bindRemoteAudioTrack(event));
    };

    pc.onAddStream = (MediaStream stream) {
      unawaited(_handleRemoteStream(stream));
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (kDebugMode) print('VoiceCall ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        unawaited(_finalizeFailedCall(
          _hasTurnServer
              ? 'Не удалось установить медиа-соединение (ICE)'
              : 'Не удалось соединиться. Нужен TURN на сервере (см. docs/VOICE_CALLS_COTURN.md)',
        ));
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (kDebugMode) print('VoiceCall PC state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_finalizeFailedCall('Соединение потеряно'));
      }
    };

    pc.onSignalingState = (RTCSignalingState state) {
      if (kDebugMode) print('VoiceCall signaling: $state');
    };
  }

  Future<void> _preparePeerConnectionShellImpl() async {
    if (_pc != null || !_snapshot.isActive) return;

    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    try {
      final pc = await _createAlivePeerConnection();
      _wirePeerConnectionHandlers(pc);
    } catch (e) {
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
        _hasTurnServer = _detectTurnInServers(_iceServers!);
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
          _hasTurnServer = _detectTurnInServers(_iceServers!);
          if (kDebugMode) {
            print(
              'VoiceCall ICE servers: count=${_iceServers!.length}, hasTurn=$_hasTurnServer',
            );
          }
          if (_iceServers!.isNotEmpty) return _iceServers!;
        }
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall ICE load error: $e');
    }
    _iceServers = WebRtcConfig.defaultIceServers;
    _hasTurnServer = _detectTurnInServers(_iceServers!);
    return _iceServers!;
  }

  bool _detectTurnInServers(List<Map<String, dynamic>> servers) {
    for (final s in servers) {
      final urls = s['urls'];
      final list = urls is List
          ? urls.map((e) => e.toString())
          : [urls?.toString() ?? ''];
      for (final url in list) {
        if (url.startsWith('turn:') || url.startsWith('turns:')) {
          return true;
        }
      }
    }
    return false;
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
          preferSpeakerOutput: false,
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
    // Defensive: на iOS бывает, что удалённый трек приходит с enabled=false и
    // звук молчит, пока его явно не включить.
    try {
      event.track.enabled = true;
    } catch (_) {}
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
    for (final track in stream.getAudioTracks()) {
      try {
        track.enabled = true;
      } catch (_) {}
    }
    _remoteStream = stream;
    _markConnected();
  }

  void _markConnected() {
    if (_snapshot.phase == VoiceCallPhase.connected) return;
    _webRtcMediaBroken = false;
    _cancelConnectingTimeout();
    // Аудиосессия в режиме звонка; маршрут (earpiece/громкая связь) — в VoiceCallScreen.
    unawaited(_reassertCallAudioSession());
    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connected,
        statusMessage: 'На связи',
      ),
    );
  }

  /// Подтверждаем режим «звонок» без принудительной громкой связи.
  Future<void> _reassertCallAudioSession() async {
    if (kIsWeb) return;
    try {
      if (WebRTC.platformIsIOS) {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: false,
        );
      } else if (WebRTC.platformIsAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
        await Helper.setSpeakerphoneOn(false);
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall reassert audio session: $e');
    }
  }

  void _startConnectingTimeout() {
    _connectingTimer?.cancel();
    _connectingTimer = Timer(const Duration(seconds: 35), () {
      if (_snapshot.phase != VoiceCallPhase.connecting) return;
      unawaited(_finalizeFailedCall(
        _hasTurnServer
            ? 'Не удалось соединиться за 35 с. Проверьте интернет и повторите.'
            : 'Не удалось соединиться. На сервере не настроен TURN — '
                'эмулятор и телефон в разных сетях без него не соединятся. '
                'См. docs/VOICE_CALLS_COTURN.md',
      ));
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
      // Defensive: на стороне клиента ограничиваем очередь, чтобы при гонке
      // (поток ICE от peer до setRemoteDescription) не разрастаться без границ.
      if (_pendingRemoteCandidates.length >= _maxPendingRemoteCandidates) {
        _pendingRemoteCandidates.removeAt(0);
      }
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
    _cancelOutgoingTimeout();
  }

  void _startOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = Timer(const Duration(seconds: 60), () {
      if (_snapshot.phase != VoiceCallPhase.outgoing) return;
      unawaited(_finalizeFailedCall('Нет ответа'));
    });
  }

  void _cancelOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = null;
  }

  Future<void> _tearDownMedia() async {
    _resetPeerConnectionState();
    _peerConnectionSetupInFlight = null;
    _localAudioSetupInFlight = null;
    _iceServers = null;
    _hasTurnServer = false;
    final pc = _pc;
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _remoteStream = null;
    await _disposePeerConnectionSafe(pc);
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
    _idleResetTimer?.cancel();
    _idleResetTimer = Timer(const Duration(seconds: 2), () {
      _idleResetTimer = null;
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
