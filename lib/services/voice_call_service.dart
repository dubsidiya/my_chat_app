import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/api_config.dart';
import '../config/webrtc_config.dart';
import '../utils/call_epoch.dart';
import '../utils/call_keep_alive.dart';
import '../utils/call_playback_pause.dart';
import '../utils/camera_permission.dart';
import '../utils/microphone_permission.dart';
import '../utils/webrtc_device_support.dart';
import '../utils/webrtc_ice_attempts.dart';
import '../utils/webrtc_ice_credentials.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';
import 'group_voice_call_service.dart';
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

enum CallMediaType { audio, video }

CallMediaType callMediaTypeFromRaw(dynamic raw) {
  final v = raw?.toString().trim().toLowerCase() ?? '';
  return v == 'video' ? CallMediaType.video : CallMediaType.audio;
}

bool? callCameraOffFromRaw(dynamic raw) => raw is bool ? raw : null;

class ParsedCallMediaUpdate {
  final CallMediaType? mediaType;
  final bool? cameraOff;

  const ParsedCallMediaUpdate({
    required this.mediaType,
    required this.cameraOff,
  });
}

ParsedCallMediaUpdate parseCallMediaUpdate(Map event) {
  final rawMediaType = event['media_type'] ?? event['mediaType'];
  return ParsedCallMediaUpdate(
    mediaType: rawMediaType == null ? null : callMediaTypeFromRaw(rawMediaType),
    cameraOff: callCameraOffFromRaw(event['camera_off'] ?? event['cameraOff']),
  );
}

class VoiceCallSnapshot {
  final VoiceCallPhase phase;
  final String? callId;
  final String? chatId;
  final String? peerUserId;
  final String? peerLabel;
  final String? statusMessage;
  final bool isMuted;
  final CallMediaType mediaType;
  final bool isCameraOff;
  final bool isRemoteCameraOff;
  final bool hasRemoteVideo;
  final bool isUsingFrontCamera;

  const VoiceCallSnapshot({
    this.phase = VoiceCallPhase.idle,
    this.callId,
    this.chatId,
    this.peerUserId,
    this.peerLabel,
    this.statusMessage,
    this.isMuted = false,
    this.mediaType = CallMediaType.audio,
    this.isCameraOff = false,
    this.isRemoteCameraOff = false,
    this.hasRemoteVideo = false,
    this.isUsingFrontCamera = true,
  });

  bool get isActive =>
      phase == VoiceCallPhase.incoming ||
      phase == VoiceCallPhase.outgoing ||
      phase == VoiceCallPhase.connecting ||
      phase == VoiceCallPhase.connected;

  bool get isVideo => mediaType == CallMediaType.video;

  VoiceCallSnapshot copyWith({
    VoiceCallPhase? phase,
    String? callId,
    String? chatId,
    String? peerUserId,
    String? peerLabel,
    String? statusMessage,
    bool? isMuted,
    CallMediaType? mediaType,
    bool? isCameraOff,
    bool? isRemoteCameraOff,
    bool? hasRemoteVideo,
    bool? isUsingFrontCamera,
  }) {
    return VoiceCallSnapshot(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      chatId: chatId ?? this.chatId,
      peerUserId: peerUserId ?? this.peerUserId,
      peerLabel: peerLabel ?? this.peerLabel,
      statusMessage: statusMessage ?? this.statusMessage,
      isMuted: isMuted ?? this.isMuted,
      mediaType: mediaType ?? this.mediaType,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isRemoteCameraOff: isRemoteCameraOff ?? this.isRemoteCameraOff,
      hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
      isUsingFrontCamera: isUsingFrontCamera ?? this.isUsingFrontCamera,
    );
  }
}

class ParsedCallStatus {
  final bool available;
  final bool active;
  final String? callId;
  final String? chatId;
  final String? state;
  final String? role;
  final DateTime? expiresAt;
  final CallMediaType mediaType;
  final bool mediaOwner;

  const ParsedCallStatus({
    required this.available,
    required this.active,
    this.callId,
    this.chatId,
    this.state,
    this.role,
    this.expiresAt,
    this.mediaType = CallMediaType.audio,
    this.mediaOwner = false,
  });
}

ParsedCallStatus parseCallStatus(Map event) {
  return ParsedCallStatus(
    available: event['available'] != false,
    active: event['active'] == true,
    callId: event['call_id']?.toString(),
    chatId: event['chat_id']?.toString(),
    state: (event['state'] ?? event['status'])?.toString(),
    role: event['role']?.toString(),
    expiresAt: DateTime.tryParse(event['expires_at']?.toString() ?? ''),
    mediaType: callMediaTypeFromRaw(event['media_type']),
    mediaOwner: event['media_owner'] == true,
  );
}

enum CallResyncDecision { ignore, converge, endStale, keepHealthyMedia }

CallResyncDecision decideCallResync({
  required VoiceCallSnapshot local,
  required ParsedCallStatus remote,
  required bool ownsMedia,
  required bool mediaHealthy,
}) {
  if (!remote.available) return CallResyncDecision.ignore;
  if (!remote.active) {
    if (local.phase == VoiceCallPhase.connected && ownsMedia && mediaHealthy) {
      return CallResyncDecision.keepHealthyMedia;
    }
    return local.isActive
        ? CallResyncDecision.endStale
        : CallResyncDecision.ignore;
  }
  if (!local.isActive) return CallResyncDecision.converge;
  if (remote.callId != local.callId) {
    return ownsMedia && mediaHealthy
        ? CallResyncDecision.keepHealthyMedia
        : CallResyncDecision.endStale;
  }
  return CallResyncDecision.converge;
}

/// 1-on-1 voice calls over WebRTC; signaling via global WebSocket.
class VoiceCallService {
  VoiceCallService._();
  static final VoiceCallService instance = VoiceCallService._();
  static const String _keepAliveOwner = 'dm-call';

  final StreamController<VoiceCallSnapshot> _stateController =
      StreamController<VoiceCallSnapshot>.broadcast();

  Stream<VoiceCallSnapshot> get stateStream => _stateController.stream;
  VoiceCallSnapshot _snapshot = const VoiceCallSnapshot();
  final CallEpoch _callEpoch = CallEpoch();

  StreamSubscription<dynamic>? _wsSub;
  String? _myUserId;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  List<Map<String, dynamic>>? _iceServers;
  DateTime? _iceExpiresAt;
  String _iceCredentialType = 'none';
  MicrophoneAccess? _lastMicAccess;
  MicrophoneAccess? _lastCameraAccess;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  static const int _maxPendingRemoteCandidates = 80;
  bool _remoteDescriptionSet = false;
  Timer? _connectingTimer;
  Timer? _outgoingTimer;
  Timer? _incomingTimer;
  Timer? _idleResetTimer;
  Timer? _resyncTimer;
  Future<void>? _peerConnectionSetupInFlight;
  Future<void>? _localAudioSetupInFlight;
  bool _webRtcInitialized = false;
  bool _hasTurnServer = false;

  /// После сбойного createPeerConnection повторный getUserMedia на Android падает (баг плагина).
  bool _webRtcMediaBroken = false;

  /// Этот клиент ведёт медиа-ногу звонка (invite/accept с этой вкладки/устройства).
  bool _ownsCallMedia = false;
  bool _usingFrontCamera = true;
  bool _desiredMuted = false;
  bool _desiredCameraOff = false;
  Future<void>? _sdpOpsInFlight;
  int _iceRestartAttempts = 0;
  static const int _maxIceRestartAttempts = 2;

  /// Peer-requested restart (отдельный бюджет от локального ICE failed).
  int _peerIceRestartHonored = 0;
  static const int _maxPeerIceRestartHonored = 1;
  bool _iceRestartInFlight = false;

  /// Пока true — игнорируем повторные ICE Failed (ждём Connected или restart timeout).
  bool _iceRestartPending = false;
  Timer? _iceRestartTimer;
  Timer? _iceDisconnectedGraceTimer;
  bool _loggedIcePathMetrics = false;

  /// Keep-alive acquired for connecting/connected media.
  bool _keepAliveHeld = false;

  /// Мы были offerer в текущей PC-сессии (нужно для iceRestart renegotiation).
  bool _isOfferer = false;

  /// Double-tap / concurrent accept guard.
  bool _acceptInFlight = false;
  Completer<bool>? _systemAcceptCompleter;
  int _resyncAttempts = 0;
  static const int _maxResyncAttempts = 20;
  int _resyncRequestSeq = 0;
  String? _pendingResyncRequestId;
  String? _pendingResyncCallId;
  bool _pendingResyncWasActive = false;

  /// UI speaker preference across minimize → re-expand (null = default).
  bool? _speakerOnPreferred;

  VoiceCallSnapshot get snapshot => _snapshot;
  MicrophoneAccess? get lastMicrophoneAccess => _lastMicAccess;
  MicrophoneAccess? get lastCameraAccess => _lastCameraAccess;

  /// Speaker preference for UI (survives minimize). Default: video → speaker.
  bool get preferredSpeakerOn => _speakerOnPreferred ?? _snapshot.isVideo;

  bool get isUsingFrontCamera => _usingFrontCamera;

  void setPreferredSpeakerOn(bool enabled) {
    _speakerOnPreferred = enabled;
  }

  void _beginCallGeneration(String callId) {
    _callEpoch.begin(callId);
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _resyncAttempts = 0;
    _pendingResyncRequestId = null;
    _pendingResyncCallId = null;
    _pendingResyncWasActive = false;
    _desiredMuted = false;
    _desiredCameraOff = false;
    _usingFrontCamera = true;
  }

  CallEpochToken? _captureSetupToken() {
    final token = _callEpoch.capture();
    if (token == null ||
        !_snapshot.isActive ||
        _snapshot.callId != token.callId) {
      return null;
    }
    return token;
  }

  bool _isSetupCurrent(
    CallEpochToken token, {
    RTCPeerConnection? peerConnection,
  }) {
    if (!_isGenerationCurrent(token) || !_snapshot.isActive) {
      return false;
    }
    return peerConnection == null || identical(_pc, peerConnection);
  }

  bool _isGenerationCurrent(CallEpochToken token) {
    return _callEpoch.isCurrent(token) && _snapshot.callId == token.callId;
  }

  void _requireCurrent(
    CallEpochToken token, {
    RTCPeerConnection? peerConnection,
  }) {
    if (!_isSetupCurrent(token, peerConnection: peerConnection)) {
      throw const _StaleCallSetup();
    }
  }

  Future<void> _disposeMediaStreamSafe(MediaStream? stream) async {
    try {
      await stream?.dispose();
    } catch (e) {
      if (kDebugMode) print('VoiceCall dispose stream: $e');
    }
  }

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
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _connectingTimer?.cancel();
    _connectingTimer = null;
    _outgoingTimer?.cancel();
    _outgoingTimer = null;
    _incomingTimer?.cancel();
    _incomingTimer = null;
    _lastMicAccess = null;
    _lastCameraAccess = null;
    _webRtcMediaBroken = false;
    _ownsCallMedia = false;
    _usingFrontCamera = true;
    _iceRestartAttempts = 0;
    _iceRestartInFlight = false;
    _peerIceRestartHonored = 0;
    _clearIceRestartPending();
    _isOfferer = false;
    _acceptInFlight = false;
    if (!(_systemAcceptCompleter?.isCompleted ?? true)) {
      _systemAcceptCompleter?.complete(false);
    }
    _systemAcceptCompleter = null;
    _resyncAttempts = 0;
    _pendingResyncRequestId = null;
    _pendingResyncCallId = null;
    _pendingResyncWasActive = false;
    _speakerOnPreferred = null;
    unawaited(_releaseKeepAlive());
    unawaited(_tearDownMedia());
    _emit(const VoiceCallSnapshot(phase: VoiceCallPhase.idle));
  }

  Future<bool> startOutgoingCall({
    required String chatId,
    required String peerUserId,
    required String peerLabel,
    CallMediaType mediaType = CallMediaType.audio,
  }) async {
    try {
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
      if (GroupVoiceCallService.instance.snapshot.isActive) {
        _emitFailed('Сначала завершите групповой звонок');
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
      // Камера: только best-effort request. Жёстко не блокируем —
      // на iOS диалог часто поднимает именно getUserMedia (см. CameraPermission).
      if (mediaType == CallMediaType.video) {
        await _requestCameraPermissionBestEffort();
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
      _beginCallGeneration(callId);
      _ownsCallMedia = true;
      _emit(
        VoiceCallSnapshot(
          phase: VoiceCallPhase.outgoing,
          callId: callId,
          chatId: chatId,
          peerUserId: peerUserId,
          peerLabel: peerLabel,
          mediaType: mediaType,
          statusMessage: mediaType == CallMediaType.video
              ? 'Видеовызов…'
              : 'Вызов…',
        ),
      );
      _startOutgoingTimeout();

      // Микрофон и PeerConnection — только после call_accept (см. _createAndSendOffer).
      unawaited(_preloadIceServers());

      final sent = _sendSignal({
        'type': 'call_invite',
        'call_id': callId,
        'chat_id': chatId,
        'media_type': mediaType == CallMediaType.video ? 'video' : 'audio',
      });
      if (!sent) {
        _cancelOutgoingTimeout();
        _ownsCallMedia = false;
        await _tearDownMedia();
        _emitFailed('Нет соединения с сервером');
        return false;
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall startOutgoingCall: $e\n$st');
      _cancelOutgoingTimeout();
      _ownsCallMedia = false;
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
    if (_snapshot.phase == VoiceCallPhase.ended ||
        _snapshot.phase == VoiceCallPhase.idle) {
      _emitFailed(message);
    }
  }

  Future<bool> _sendHangupBestEffort(String callId, String chatId) async {
    final payload = {
      'type': 'call_hangup',
      'call_id': callId,
      'chat_id': chatId,
    };
    return _sendSignalBestEffort(payload);
  }

  Future<bool> _sendSignalBestEffort(
    Map<String, dynamic> payload, {
    CallEpochToken? setupToken,
  }) async {
    if (setupToken != null && !_isSetupCurrent(setupToken)) return false;
    if (_sendSignal(payload)) return true;
    await WebSocketService.instance.connectIfNeeded();
    if (setupToken != null && !_isSetupCurrent(setupToken)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (setupToken != null && !_isSetupCurrent(setupToken)) return false;
    return _sendSignal(payload);
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
    final token = _captureSetupToken();
    if (token == null) return;
    try {
      await _loadIceServers(token);
    } catch (_) {}
  }

  Future<void> acceptIncoming() async {
    // Кнопка «Принять» в UI вызывает acceptIncoming через `unawaited(...)`,
    // т.е. любая внезапная ошибка (MissingPluginException, ошибка mic и т.д.)
    // молча терялась — пользователь видел, что «Принять» ничего не делает.
    // Ловим всё локально и переводим звонок в failed с понятным текстом.
    if (_acceptInFlight) return;
    _acceptInFlight = true;
    try {
      if (_snapshot.phase != VoiceCallPhase.incoming) return;
      final token = _captureSetupToken();
      final callId = _snapshot.callId;
      final chatId = _snapshot.chatId;
      if (token == null || callId == null || chatId == null) return;
      if (!WebRtcDeviceSupport.webCallsAllowed) {
        _emitFailed(WebRtcDeviceSupport.insecureWebContextMessage);
        await rejectIncoming(reason: 'media_error');
        return;
      }
      if (await WebRtcDeviceSupport.isUnsupportedSimulator()) {
        if (!_isSetupCurrent(token)) return;
        _emitFailed(WebRtcDeviceSupport.unsupportedSimulatorMessage);
        await rejectIncoming(reason: 'media_error');
        return;
      }
      if (!_isSetupCurrent(token)) return;

      await CallPlaybackPause.pauseBestEffort();
      if (!_isSetupCurrent(token)) return;

      if (!await _ensureMicrophonePermission(token)) {
        if (!_isGenerationCurrent(token)) return;
        await rejectIncoming(reason: 'no_mic');
        return;
      }
      if (!_isSetupCurrent(token)) return;
      if (_snapshot.isVideo) {
        await _requestCameraPermissionBestEffort(token);
        if (!_isSetupCurrent(token)) return;
      }

      // Тот же ранний контракт, что и в startOutgoingCall: если flutter_webrtc
      // не зарегистрирован, peer не должен узнать о принятии звонка.
      if (!await _ensureWebRtcReady(token)) {
        if (!_isGenerationCurrent(token)) return;
        await rejectIncoming(reason: 'media_error');
        return;
      }
      if (!_isSetupCurrent(token)) return;
      if (!await _ensureSignalingConnected()) {
        if (!_isGenerationCurrent(token)) return;
        await rejectIncoming(reason: 'media_error');
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
        return;
      }
      // После долгих await — звонок мог уже сорваться.
      if (_snapshot.phase != VoiceCallPhase.incoming ||
          !_isSetupCurrent(token)) {
        return;
      }

      _cancelIncomingTimeout();
      _emit(
        _snapshot.copyWith(
          phase: VoiceCallPhase.connecting,
          statusMessage: _connectingStatusHint(),
        ),
      );
      _startConnectingTimeout();
      _ownsCallMedia = true;
      final sent = _sendSignal({
        'type': 'call_accept',
        'call_id': callId,
        'chat_id': chatId,
      });
      if (!sent) {
        _cancelConnectingTimeout();
        _ownsCallMedia = false;
        await rejectIncoming(reason: 'media_error');
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
      }
    } on _StaleCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall acceptIncoming: $e\n$st');
      _cancelConnectingTimeout();
      // Если call_accept уже ушёл — нужен hangup, не только local failed.
      final acceptMayHaveSent =
          _ownsCallMedia || _snapshot.phase == VoiceCallPhase.connecting;
      if (acceptMayHaveSent) {
        await _finalizeFailedCall(
          'Не удалось принять звонок: ${_shortError(e)}',
        );
      } else {
        await _tearDownMedia();
        if (_snapshot.phase == VoiceCallPhase.incoming ||
            _snapshot.phase == VoiceCallPhase.connecting ||
            _snapshot.phase == VoiceCallPhase.failed) {
          await rejectIncoming(reason: 'media_error');
        }
        _emitFailed('Не удалось принять звонок: ${_shortError(e)}');
      }
    } finally {
      _acceptInFlight = false;
    }
  }

  /// CallKit answer path: atomically claim the server call first, then start
  /// media preparation without holding the native CXAnswerCallAction open for
  /// permission dialogs or WebRTC setup.
  Future<bool> acceptIncomingFromSystem() async {
    if (_acceptInFlight || _snapshot.phase != VoiceCallPhase.incoming) {
      return false;
    }
    _acceptInFlight = true;
    try {
      final token = _captureSetupToken();
      final callId = _snapshot.callId;
      final chatId = _snapshot.chatId;
      if (token == null || callId == null || chatId == null) return false;
      await bindUserIfNeeded();
      if (!await _ensureSignalingConnected() || !_isSetupCurrent(token)) {
        return false;
      }

      final completer = Completer<bool>();
      _systemAcceptCompleter = completer;
      _cancelIncomingTimeout();
      _ownsCallMedia = true;
      _emit(
        _snapshot.copyWith(
          phase: VoiceCallPhase.connecting,
          statusMessage: _connectingStatusHint(),
        ),
      );
      _startConnectingTimeout();
      if (!_sendSignal({
        'type': 'call_accept',
        'call_id': callId,
        'chat_id': chatId,
      })) {
        _systemAcceptCompleter = null;
        _ownsCallMedia = false;
        _cancelConnectingTimeout();
        return false;
      }

      final accepted = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
      if (!accepted || !_isSetupCurrent(token)) {
        _ownsCallMedia = false;
        _cancelConnectingTimeout();
        return false;
      }
      unawaited(_prepareSystemAnsweredMedia(token));
      return true;
    } catch (_) {
      _ownsCallMedia = false;
      _cancelConnectingTimeout();
      return false;
    } finally {
      _systemAcceptCompleter = null;
      _acceptInFlight = false;
    }
  }

  Future<void> _prepareSystemAnsweredMedia(CallEpochToken token) async {
    try {
      await CallPlaybackPause.pauseBestEffort();
      if (!_isSetupCurrent(token)) return;
      if (!await _ensureMicrophonePermission(token)) {
        if (_isGenerationCurrent(token)) {
          await _finalizeFailedCall('Нет доступа к микрофону');
        }
        return;
      }
      if (_snapshot.isVideo) {
        await _requestCameraPermissionBestEffort(token);
        if (!_isSetupCurrent(token)) return;
      }
      if (!await _ensureWebRtcReady(token) && _isGenerationCurrent(token)) {
        await _finalizeFailedCall('Не удалось запустить WebRTC');
      }
    } on _StaleCallSetup {
      return;
    } catch (error) {
      if (_isGenerationCurrent(token)) {
        await _finalizeFailedCall(
          'Не удалось подготовить звонок: ${_shortError(error)}',
        );
      }
    }
  }

  Future<void> rejectIncoming({String reason = 'declined'}) async {
    _completeSystemAccept(false);
    final phase = _snapshot.phase;
    // failed: после _emitFailed в accept (mic deny) всё ещё нужно слать call_reject.
    if (phase != VoiceCallPhase.incoming &&
        phase != VoiceCallPhase.connecting &&
        phase != VoiceCallPhase.failed) {
      return;
    }
    _cancelIncomingTimeout();
    final token = _callEpoch.capture();
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null) {
      final payload = {
        'type': 'call_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': reason,
      };
      if (!_sendSignal(payload)) {
        await WebSocketService.instance.connectIfNeeded();
        if (token != null && !_isGenerationCurrent(token)) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (token != null && !_isGenerationCurrent(token)) return;
        _sendSignal(payload);
      }
    }
    if (token != null && !_isGenerationCurrent(token)) return;
    await _tearDownMedia();
    final statusMessage =
        reason == 'no_mic' || reason == 'no_camera' || reason == 'media_error'
        ? (_snapshot.statusMessage ?? 'Не удалось принять звонок')
        : 'Отклонён';
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        callId: callId,
        chatId: chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        mediaType: _snapshot.mediaType,
        statusMessage: statusMessage,
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> hangUp() async {
    _completeSystemAccept(false);
    final token = _callEpoch.capture();
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null &&
        chatId != null &&
        (_snapshot.isActive || _ownsCallMedia)) {
      await _sendHangupBestEffort(callId, chatId);
    }
    if (token != null && !_isGenerationCurrent(token)) return;
    _ownsCallMedia = false;
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
    final token = _callEpoch.capture();
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null && _snapshot.isActive) {
      await _sendHangupBestEffort(callId, chatId);
    }
    if (token != null && !_isGenerationCurrent(token)) return;
    _emitFailed(message);
    await _tearDownMedia();
  }

  Future<void> toggleMute() => setMuted(!_desiredMuted);

  Future<void> setMuted(bool muted) async {
    _desiredMuted = muted;
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_desiredMuted;
      }
    }
    _emit(_snapshot.copyWith(isMuted: _desiredMuted));
  }

  Future<void> toggleCamera() async {
    if (!_snapshot.isVideo) return;
    _desiredCameraOff = !_desiredCameraOff;
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getVideoTracks()) {
        track.enabled = !_desiredCameraOff;
      }
    }
    _emit(_snapshot.copyWith(isCameraOff: _desiredCameraOff));
    _notifyCameraState();
  }

  Future<void> switchCamera() async {
    if (!_snapshot.isVideo || kIsWeb) return;
    final token = _captureSetupToken();
    if (token == null) return;
    final stream = _localStream;
    if (stream == null) return;
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      if (!_isSetupCurrent(token)) return;
      _usingFrontCamera = !_usingFrontCamera;
      _emit(_snapshot.copyWith(isUsingFrontCamera: _usingFrontCamera));
    } catch (e) {
      if (kDebugMode) print('VoiceCall switchCamera: $e');
    }
  }

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;

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
    CallMediaType mediaType = CallMediaType.audio,
    DateTime? expiresAt,
  }) {
    if (callId.isEmpty || chatId.isEmpty || peerUserId.isEmpty) return;
    unawaited(bindUserIfNeeded());
    unawaited(WebSocketService.instance.connectIfNeeded());

    if (_snapshot.isActive) {
      if (_snapshot.callId == callId) return;
      // Как WS busy: иначе caller звонит до 75s.
      _sendSignal({
        'type': 'call_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'busy',
      });
      return;
    }
    if (GroupVoiceCallService.instance.snapshot.isActive) {
      _sendSignal({
        'type': 'call_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'busy',
      });
      return;
    }

    unawaited(CallPlaybackPause.pauseBestEffort());

    _beginCallGeneration(callId);
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.incoming,
        callId: callId,
        chatId: chatId,
        peerUserId: peerUserId,
        peerLabel: peerLabel,
        mediaType: mediaType,
        statusMessage: mediaType == CallMediaType.video
            ? 'Входящий видеозвонок'
            : 'Входящий звонок',
      ),
    );
    _startIncomingTimeout(expiresAt: expiresAt);
    unawaited(_syncProvisionalIncoming(callId));
  }

  Future<void> _syncProvisionalIncoming(String callId) async {
    try {
      await bindUserIfNeeded();
      await WebSocketService.instance.connectIfNeeded();
      if (_snapshot.phase != VoiceCallPhase.incoming ||
          _snapshot.callId != callId) {
        return;
      }
      _sendCallResync();
    } catch (error) {
      if (kDebugMode) print('VoiceCall provisional status: $error');
    }
  }

  void _onWsEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type == '_ws_connected' || type == '_ws_reconnected') {
      _onWsReconnected();
      return;
    }
    if (type == null || !type.startsWith('call_')) return;

    switch (type) {
      case 'call_status':
        unawaited(_onCallStatus(event));
        break;
      case 'call_resume':
        _onPeerResume(event);
        break;
      case 'call_invite':
        _onInvite(event);
        break;
      case 'call_accept':
        _onAccept(event);
        break;
      case 'call_accept_ack':
        _onAcceptAck(event);
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
      case 'call_answered_elsewhere':
        _onAnsweredElsewhere(event);
        break;
      case 'call_media_update':
        _onMediaUpdate(event);
        break;
      case 'call_ice_restart':
        unawaited(_onIceRestartRequest(event));
        break;
    }
  }

  void _onWsReconnected() {
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _resyncAttempts = 0;
    _sendCallResync();
  }

  void _sendCallResync() {
    final callId = _snapshot.callId;
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_resyncRequestSeq}';
    _pendingResyncRequestId = requestId;
    _pendingResyncCallId = _snapshot.isActive ? callId : null;
    _pendingResyncWasActive = _snapshot.isActive;
    final payload = <String, dynamic>{
      'type': _snapshot.isActive && _ownsCallMedia
          ? 'call_resume'
          : 'call_status',
      'request_id': requestId,
      if (callId != null && callId.isNotEmpty) 'call_id': callId,
      if (_snapshot.chatId != null) 'chat_id': _snapshot.chatId,
    };
    if (!_sendSignal(payload)) {
      _scheduleCallResync();
    }
  }

  void _scheduleCallResync() {
    if (_resyncAttempts >= _maxResyncAttempts) {
      if (_snapshot.isActive && _ownsCallMedia && !_isIceOrPcHealthy()) {
        _ownsCallMedia = false;
        unawaited(_tearDownMedia());
        _emit(
          const VoiceCallSnapshot(
            phase: VoiceCallPhase.ended,
            statusMessage: 'Звонок активен на другом устройстве',
          ),
        );
        _scheduleIdleReset();
      }
      return;
    }
    _resyncTimer?.cancel();
    _resyncAttempts++;
    _resyncTimer = Timer(const Duration(seconds: 3), () {
      _resyncTimer = null;
      if (!WebSocketService.instance.isConnected) {
        _scheduleCallResync();
        return;
      }
      _sendCallResync();
    });
  }

  Future<void> _onCallStatus(Map event) async {
    final requestId = event['request_id']?.toString();
    if (requestId != null) {
      if (requestId != _pendingResyncRequestId) return;
      final expectedCallId = _pendingResyncCallId;
      final expectedActive = _pendingResyncWasActive;
      _pendingResyncRequestId = null;
      _pendingResyncCallId = null;
      _pendingResyncWasActive = false;
      if (expectedActive != _snapshot.isActive) return;
      if (expectedActive && expectedCallId != _snapshot.callId) return;
    }
    final remote = parseCallStatus(event);
    final decision = decideCallResync(
      local: _snapshot,
      remote: remote,
      ownsMedia: _ownsCallMedia,
      mediaHealthy: _isIceOrPcHealthy(),
    );
    if (decision == CallResyncDecision.ignore) return;
    if (decision == CallResyncDecision.keepHealthyMedia) {
      _scheduleCallResync();
      return;
    }
    if (decision == CallResyncDecision.endStale) {
      _ownsCallMedia = false;
      await _tearDownMedia();
      _emit(
        const VoiceCallSnapshot(
          phase: VoiceCallPhase.ended,
          statusMessage: 'Звонок больше не активен',
        ),
      );
      _scheduleIdleReset();
      return;
    }

    if (!remote.active) return;

    if (!_snapshot.isActive) {
      _resyncTimer?.cancel();
      _resyncTimer = null;
      _resyncAttempts = 0;
      if (remote.role == 'callee' && remote.state == 'ringing') {
        final callId = remote.callId;
        final chatId = remote.chatId;
        if (callId == null || chatId == null) return;
        _beginCallGeneration(callId);
        _ownsCallMedia = false;
        _emit(
          VoiceCallSnapshot(
            phase: VoiceCallPhase.incoming,
            callId: callId,
            chatId: chatId,
            peerUserId: '',
            peerLabel: 'Пользователь',
            mediaType: remote.mediaType,
            statusMessage: remote.mediaType == CallMediaType.video
                ? 'Входящий видеозвонок'
                : 'Входящий звонок',
          ),
        );
        _startIncomingTimeout(expiresAt: remote.expiresAt);
        unawaited(_preloadIceServers());
      }
      return;
    }
    if (remote.callId != _snapshot.callId) return;

    final explicitlyLostMedia =
        event.containsKey('media_owner') && remote.mediaOwner == false;
    if (explicitlyLostMedia && _ownsCallMedia) {
      _scheduleCallResync();
      return;
    }
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _resyncAttempts = 0;

    if (remote.state == 'accepted' &&
        remote.mediaOwner &&
        _ownsCallMedia &&
        _snapshot.phase == VoiceCallPhase.connected &&
        !_isIceOrPcHealthy()) {
      unawaited(_handleIceFailed(message: 'Переподключение медиа'));
    } else if (remote.state == 'ringing' &&
        _snapshot.phase == VoiceCallPhase.incoming) {
      _startIncomingTimeout(expiresAt: remote.expiresAt);
    } else if (remote.state == 'accepted' &&
        _snapshot.phase == VoiceCallPhase.outgoing &&
        _ownsCallMedia) {
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
      } on _StaleCallSetup {
        return;
      } catch (error) {
        if (kDebugMode) print('VoiceCall resume offer: $error');
      }
    } else if (remote.state == 'accepted' &&
        _snapshot.phase == VoiceCallPhase.incoming &&
        !_ownsCallMedia) {
      _onAnsweredElsewhere(event);
    }
  }

  void _onPeerResume(Map event) {
    if (!_matchesActiveCall(event) || !_ownsCallMedia) return;
    if (_snapshot.phase != VoiceCallPhase.connected) return;
    if (_isOfferer) {
      unawaited(_onIceRestartRequest(event));
      return;
    }
    if (_isIceOrPcHealthy()) return;
    unawaited(_handleIceFailed(message: 'Переподключение медиа'));
  }

  Future<void> _onIceRestartRequest(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (!_ownsCallMedia || !_isOfferer) return;
    if (!_snapshot.isActive) return;
    if (_iceRestartPending || _iceRestartInFlight) return;
    final token = _captureSetupToken();
    if (token == null) return;
    if (_peerIceRestartHonored >= _maxPeerIceRestartHonored) {
      // Не рвём живой звонок — просто игнорируем лишний peer restart.
      if (kDebugMode) print('VoiceCall: peer ice_restart ignored (budget)');
      return;
    }
    _peerIceRestartHonored++;
    _iceRestartPending = true;
    _emit(_snapshot.copyWith(statusMessage: 'Переподключение…'));
    _startIceRestartWatchdog();
    final ok = await _attemptIceRestart();
    if (!_isSetupCurrent(token)) return;
    if (!ok) {
      _clearIceRestartPending();
      await _finalizeFailedCall('Не удалось переподключить медиа');
    }
  }

  /// Peer сообщил, что ушёл на audio-only (нет камеры и т.п.).
  void _onMediaUpdate(Map event) {
    if (!_matchesActiveCall(event)) return;
    final update = parseCallMediaUpdate(event);
    final cameraOff = update.cameraOff;
    if (cameraOff != null && _snapshot.isVideo) {
      final remoteHasVideo =
          !cameraOff && (_remoteStream?.getVideoTracks().isNotEmpty ?? false);
      _emit(
        _snapshot.copyWith(
          isRemoteCameraOff: cameraOff,
          hasRemoteVideo: remoteHasVideo,
          statusMessage: cameraOff
              ? 'Камера собеседника выключена'
              : 'На связи',
        ),
      );
    }
    if (cameraOff == null &&
        update.mediaType == CallMediaType.audio &&
        _snapshot.isVideo) {
      _emit(
        _snapshot.copyWith(
          mediaType: CallMediaType.audio,
          isRemoteCameraOff: true,
          hasRemoteVideo: false,
          statusMessage: 'Только голос (без видео)',
        ),
      );
    }
  }

  void _notifyCameraUnavailable() {
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId == null || chatId == null) return;
    _sendSignal({
      'type': 'call_media_update',
      'call_id': callId,
      'chat_id': chatId,
      'media_type': 'video',
      'camera_off': true,
      'reason': 'no_camera',
    });
  }

  void _notifyCameraState() {
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId == null || chatId == null || !_snapshot.isVideo) return;
    _sendSignal({
      'type': 'call_media_update',
      'call_id': callId,
      'chat_id': chatId,
      'media_type': 'video',
      'camera_off': _desiredCameraOff,
    });
  }

  /// Другая вкладка/устройство того же аккаунта приняла входящий звонок.
  void _onAnsweredElsewhere(Map event) {
    if (!_matchesActiveCall(event)) return;
    if (!(_systemAcceptCompleter?.isCompleted ?? true)) {
      _systemAcceptCompleter?.complete(false);
      _ownsCallMedia = false;
    } else if (_ownsCallMedia) {
      return;
    }
    _cancelOutgoingTimeout();
    _cancelConnectingTimeout();
    unawaited(_tearDownMedia());
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        statusMessage: 'Звонок принят на другом устройстве',
      ),
    );
    _scheduleIdleReset();
  }

  void _onInvite(Map event) {
    final inviteCallId =
        event['call_id']?.toString() ?? event['callId']?.toString();
    final inviteChatId =
        event['chat_id']?.toString() ?? event['chatId']?.toString();

    if (GroupVoiceCallService.instance.snapshot.isActive) {
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

    if (_snapshot.isActive) {
      if (inviteCallId != null && inviteCallId == _snapshot.callId) {
        // Push мог прийти раньше без mediaType — подтягиваем video из WS.
        final mt = callMediaTypeFromRaw(
          event['media_type'] ?? event['mediaType'],
        );
        if (mt == CallMediaType.video && !_snapshot.isVideo) {
          _emit(
            _snapshot.copyWith(
              mediaType: mt,
              statusMessage: 'Входящий видеозвонок',
            ),
          );
        }
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
    unawaited(CallPlaybackPause.pauseBestEffort());
    final fromId = event['from_user_id']?.toString() ?? '';
    final fromEmail = event['from_user_email']?.toString() ?? 'Пользователь';
    final mediaType = callMediaTypeFromRaw(
      event['media_type'] ?? event['mediaType'],
    );
    final callId = event['call_id']?.toString();
    if (callId == null || callId.isEmpty) return;
    _beginCallGeneration(callId);
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.incoming,
        callId: callId,
        chatId: event['chat_id']?.toString(),
        peerUserId: fromId,
        peerLabel: fromEmail,
        mediaType: mediaType,
        statusMessage: mediaType == CallMediaType.video
            ? 'Входящий видеозвонок'
            : 'Входящий звонок',
      ),
    );
    _startIncomingTimeout();
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
    if (!_ownsCallMedia) return;
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
    } on _StaleCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall offer error: $e\n$st');
      // Под-вызов мог уже сам позвать _finalizeFailedCall с детальным
      // сообщением — не затираем его generic-текстом.
      final alreadyFailed =
          _snapshot.phase == VoiceCallPhase.failed ||
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

  void _onAcceptAck(Map event) {
    if (!_matchesActiveCall(event) || !_ownsCallMedia) return;
    _completeSystemAccept(true);
  }

  void _completeSystemAccept(bool accepted) {
    if (!(_systemAcceptCompleter?.isCompleted ?? true)) {
      _systemAcceptCompleter?.complete(accepted);
    }
  }

  void _onReject(Map event) {
    if (!_matchesActiveCall(event)) return;
    _completeSystemAccept(false);
    _cancelOutgoingTimeout();
    _tearDownMedia();
    final reason = event['reason']?.toString() ?? 'declined';
    final statusMessage = reason == 'busy'
        ? 'Абонент занят'
        : reason == 'no_mic' || reason == 'no_camera' || reason == 'media_error'
        ? 'Абонент не смог принять звонок'
        : 'Абонент отклонил';
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.ended,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        mediaType: _snapshot.mediaType,
        statusMessage: statusMessage,
      ),
    );
    _scheduleIdleReset();
  }

  void _onHangup(Map event) {
    if (!_matchesActiveCall(event)) return;
    _completeSystemAccept(false);
    // Свой echo после _finalizeFailedCall не должен затирать детальный failed.
    if (_snapshot.phase == VoiceCallPhase.failed) return;
    unawaited(_tearDownMedia());
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
    _completeSystemAccept(false);
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
    _completeSystemAccept(false);
    final operation = event['operation']?.toString();
    final resyncOperation =
        operation == 'call_status' || operation == 'call_resume';
    if (resyncOperation &&
        (code == 'realtime_unavailable' ||
            code == 'signaling_unavailable' ||
            code == 'rate_limited')) {
      _scheduleCallResync();
      return;
    }
    if (code == 'realtime_unavailable' || code == 'signaling_unavailable') {
      final healthyMedia =
          _ownsCallMedia &&
          (_snapshot.phase == VoiceCallPhase.connected ||
              _snapshot.phase == VoiceCallPhase.connecting) &&
          _isIceOrPcHealthy();
      if (healthyMedia) {
        _scheduleCallResync();
        return;
      }
    }
    // Trickle ICE burst не должен рвать живой звонок.
    if (code == 'rate_limited' &&
        (_snapshot.phase == VoiceCallPhase.connected ||
            _snapshot.phase == VoiceCallPhase.connecting ||
            _iceRestartPending)) {
      if (kDebugMode) print('VoiceCall: ignoring rate_limited during media');
      return;
    }
    _tearDownMedia();
    _emitFailed(_humanizeError(code));
  }

  Future<void> _onOffer(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (!_ownsCallMedia) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;

    Future<void> run() async {
      final desc = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      );
      if (desc.sdp == null || desc.sdp!.isEmpty) return;

      final isRenegotiation =
          _snapshot.phase == VoiceCallPhase.connected || _iceRestartPending;
      if (!isRenegotiation) {
        if (_snapshot.phase != VoiceCallPhase.connecting) {
          _emit(
            _snapshot.copyWith(
              phase: VoiceCallPhase.connecting,
              statusMessage: _connectingStatusHint(),
            ),
          );
        }
        _startConnectingTimeout();
      } else {
        _iceRestartPending = true;
        _emit(_snapshot.copyWith(statusMessage: 'Переподключение…'));
        _startIceRestartWatchdog();
      }

      await _createAndSendAnswer(desc);
      final token = _captureSetupToken();
      final pc = _pc;
      if (token == null || pc == null) throw const _StaleCallSetup();
      await _maybeMarkConnectedAfterSdp(token, pc);
    }

    final callIdAtQueue = _snapshot.callId;
    final tokenAtQueue = _captureSetupToken();
    if (tokenAtQueue == null) return;
    final prev = _sdpOpsInFlight;
    final done = Completer<void>();
    _sdpOpsInFlight = done.future;
    try {
      if (prev != null) await prev;
      // Callee: PC создаётся внутри _createAndSendAnswer — не требуем _pc != null.
      if (!_ownsCallMedia ||
          !_isSetupCurrent(tokenAtQueue) ||
          _snapshot.callId != callIdAtQueue) {
        return;
      }
      await run();
    } on _StaleCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall answer error: $e\n$st');
      if (!_isGenerationCurrent(tokenAtQueue) ||
          _snapshot.callId != callIdAtQueue) {
        return;
      }
      final alreadyFailed =
          _snapshot.phase == VoiceCallPhase.failed ||
          _snapshot.phase == VoiceCallPhase.ended ||
          _snapshot.phase == VoiceCallPhase.idle;
      if (!alreadyFailed) {
        await _finalizeFailedCall(
          'Ошибка согласования медиа: ${_shortError(e)}',
        );
      }
    } finally {
      if (!done.isCompleted) done.complete();
      if (identical(_sdpOpsInFlight, done.future)) {
        _sdpOpsInFlight = null;
      }
    }
  }

  Future<void> _onAnswer(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (!_ownsCallMedia) return;
    if (_pc == null) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;

    Future<void> run() async {
      final token = _captureSetupToken();
      final pc = _pc;
      if (token == null || pc == null) throw const _StaleCallSetup();
      final desc = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      );
      await _setRemoteDescription(desc, token, pc);
      await _maybeMarkConnectedAfterSdp(token, pc);
    }

    final callIdAtQueue = _snapshot.callId;
    final tokenAtQueue = _captureSetupToken();
    if (tokenAtQueue == null) return;
    final prev = _sdpOpsInFlight;
    final done = Completer<void>();
    _sdpOpsInFlight = done.future;
    try {
      if (prev != null) await prev;
      if (!_ownsCallMedia ||
          !_isSetupCurrent(tokenAtQueue) ||
          _snapshot.callId != callIdAtQueue ||
          _pc == null) {
        return;
      }
      await run();
    } on _StaleCallSetup {
      return;
    } catch (e) {
      if (kDebugMode) print('VoiceCall set answer error: $e');
      if (!_isGenerationCurrent(tokenAtQueue) ||
          _snapshot.callId != callIdAtQueue) {
        return;
      }
      final alreadyFailed =
          _snapshot.phase == VoiceCallPhase.failed ||
          _snapshot.phase == VoiceCallPhase.ended ||
          _snapshot.phase == VoiceCallPhase.idle;
      if (!alreadyFailed) {
        await _finalizeFailedCall('Ошибка ответа медиа: ${_shortError(e)}');
      }
    } finally {
      if (!done.isCompleted) done.complete();
      if (identical(_sdpOpsInFlight, done.future)) {
        _sdpOpsInFlight = null;
      }
    }
  }

  Future<void> _maybeMarkConnectedAfterSdp(
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    _requireCurrent(token, peerConnection: pc);
    try {
      final ice = await pc.getIceConnectionState();
      _requireCurrent(token, peerConnection: pc);
      final conn = await pc.getConnectionState();
      _requireCurrent(token, peerConnection: pc);
      final iceOk =
          ice == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          ice == RTCIceConnectionState.RTCIceConnectionStateCompleted;
      final connOk =
          conn == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      if (iceOk || connOk) {
        _markConnected();
      }
    } on _StaleCallSetup {
      rethrow;
    } catch (_) {}
  }

  Future<void> _onIce(Map event) async {
    if (!_matchesActiveCall(event)) return;
    if (!_ownsCallMedia) return;
    final candidate = event['candidate'];
    if (candidate is! Map) return;
    final token = _captureSetupToken();
    if (token == null) return;
    // Callee часто получает trickle ICE до createAnswer/PC — не дропаем.
    await _addRemoteIceCandidate(_iceCandidateFromMap(candidate), token);
  }

  bool _matchesActiveCall(Map event, {bool allowNoCallId = false}) {
    final eventCallId =
        event['call_id']?.toString() ?? event['callId']?.toString();
    final activeId = _snapshot.callId;
    if (activeId == null || activeId.isEmpty) {
      return allowNoCallId;
    }
    if (eventCallId == null || eventCallId.isEmpty) return allowNoCallId;
    return eventCallId == activeId;
  }

  String _connectingStatusHint() {
    if (!_hasTurnServer) {
      return 'Соединение… (без TURN часть сетей не соединится)';
    }
    return 'Соединение…';
  }

  /// Offerer (звонящий после call_accept): PC → микрофон[/камера] → offer.
  Future<void> _createAndSendOffer() async {
    final token = _captureSetupToken();
    if (token == null) throw const _StaleCallSetup();
    await _preparePeerConnectionShell(token);
    _requireCurrent(token);
    if (!await _ensureLocalMediaStream(token)) {
      if (!_isGenerationCurrent(token)) throw const _StaleCallSetup();
      throw StateError('local media unavailable');
    }
    _requireCurrent(token);
    final pc = _pc;
    if (pc == null) throw const _StaleCallSetup();
    await _attachLocalTracksToPeerConnection(token, pc);
    _requireCurrent(token, peerConnection: pc);

    final offer = await pc.createOffer(<String, dynamic>{
      if (_snapshot.isVideo) 'offerToReceiveVideo': true,
      'offerToReceiveAudio': true,
    });
    _requireCurrent(token, peerConnection: pc);
    await pc.setLocalDescription(offer);
    _requireCurrent(token, peerConnection: pc);
    _isOfferer = true;
    if (kDebugMode) {
      print('VoiceCall: offer created, sdp length=${offer.sdp?.length ?? 0}');
    }

    final sent = await _sendSignalBestEffort({
      'type': 'call_offer',
      'call_id': token.callId,
      'chat_id': _snapshot.chatId,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    }, setupToken: token);
    _requireCurrent(token, peerConnection: pc);
    if (!sent) {
      throw StateError('failed to send call_offer');
    }
  }

  /// Answerer: PC → remote offer → микрофон[/камера] → answer (unified-plan).
  Future<void> _createAndSendAnswer(RTCSessionDescription remoteOffer) async {
    final token = _captureSetupToken();
    if (token == null) throw const _StaleCallSetup();
    await _preparePeerConnectionShell(token);
    _requireCurrent(token);
    final pc = _pc;
    if (pc == null) throw const _StaleCallSetup();
    await _setRemoteDescription(remoteOffer, token, pc);
    _requireCurrent(token, peerConnection: pc);
    if (!await _ensureLocalMediaStream(token)) {
      if (!_isGenerationCurrent(token)) throw const _StaleCallSetup();
      throw StateError('local media unavailable');
    }
    await _attachLocalTracksToPeerConnection(token, pc);
    _requireCurrent(token, peerConnection: pc);

    final answer = await pc.createAnswer(<String, dynamic>{});
    _requireCurrent(token, peerConnection: pc);
    await pc.setLocalDescription(answer);
    _requireCurrent(token, peerConnection: pc);
    _isOfferer = false;
    if (kDebugMode) {
      print('VoiceCall: answer created, sdp length=${answer.sdp?.length ?? 0}');
    }

    final sent = await _sendSignalBestEffort({
      'type': 'call_answer',
      'call_id': token.callId,
      'chat_id': _snapshot.chatId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    }, setupToken: token);
    _requireCurrent(token, peerConnection: pc);
    if (!sent) {
      throw StateError('failed to send call_answer');
    }
  }

  Future<void> _ensureWebRtcInitialized() async {
    if (kIsWeb || _webRtcInitialized) return;
    await WebRTC.initialize(
      options: <String, dynamic>{
        'androidAudioConfiguration': AndroidAudioConfiguration.communication
            .toMap(),
      },
    );
    _webRtcInitialized = true;
  }

  /// Ранний sanity-check на доступность flutter_webrtc. На iOS release часто
  /// прилетает MissingPluginException, если pod-ы не подтянулись (та же
  /// причина, что у permission_handler). Хотим узнать до отправки сигнала, а
  /// не на половине offer/answer-handshake, когда peer уже думает «приняли».
  Future<bool> _ensureWebRtcReady([CallEpochToken? setupToken]) async {
    if (kIsWeb) return true;
    try {
      await _ensureWebRtcInitialized();
      if (setupToken != null && !_isGenerationCurrent(setupToken)) {
        return false;
      }
      return true;
    } catch (e, st) {
      if (setupToken != null && !_isGenerationCurrent(setupToken)) {
        return false;
      }
      if (kDebugMode) print('VoiceCall WebRTC not ready: $e\n$st');
      _emitFailed(
        'WebRTC недоступен в этой сборке. '
        'Пересоберите приложение из чистого состояния (pod install). '
        'Детали: ${_shortError(e)}',
      );
      return false;
    }
  }

  Future<bool> _ensureLocalMediaStream(CallEpochToken token) async {
    if (_webRtcMediaBroken) {
      _emitFailed(
        'Ошибка WebRTC. Полностью закройте приложение и откройте снова.',
      );
      return false;
    }
    if (!_isSetupCurrent(token)) return false;
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (_pc == null) {
      if (kDebugMode) print('VoiceCall getUserMedia: PeerConnection missing');
      return false;
    }

    if (_localAudioSetupInFlight != null) {
      await _localAudioSetupInFlight;
      return _isSetupCurrent(token) &&
          _localStream != null &&
          _localStream!.getAudioTracks().isNotEmpty;
    }

    final setup = _ensureLocalMediaStreamImpl(token);
    _localAudioSetupInFlight = setup;
    try {
      return await setup;
    } finally {
      if (identical(_localAudioSetupInFlight, setup)) {
        _localAudioSetupInFlight = null;
      }
    }
  }

  Future<bool> _ensureLocalMediaStreamImpl(CallEpochToken token) async {
    if (!_isSetupCurrent(token)) return false;
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }

    if (!await _ensureMicrophonePermission(token)) {
      if (_isGenerationCurrent(token)) {
        await _finalizeFailedCall(
          _snapshot.statusMessage ?? 'Нет доступа к микрофону',
        );
      }
      return false;
    }
    if (!_isSetupCurrent(token)) return false;
    if (_snapshot.isVideo) {
      await _requestCameraPermissionBestEffort(token);
      if (!_isSetupCurrent(token)) return false;
    }

    await _prepareAudioSessionForCall(token);
    if (!_isSetupCurrent(token)) return false;
    MediaStream? candidate;
    try {
      final wantVideo = _snapshot.isVideo;
      var fellBackToAudio = false;
      try {
        candidate = await adoptCallScopedResource<MediaStream>(
          resource: navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': wantVideo
                ? <String, dynamic>{
                    'facingMode': _usingFrontCamera ? 'user' : 'environment',
                    'width': 1280,
                    'height': 720,
                  }
                : false,
          }),
          token: token,
          isCurrent: _isSetupCurrent,
          dispose: _disposeMediaStreamSafe,
        );
        if (candidate == null) return false;
      } catch (videoErr) {
        if (!_isSetupCurrent(token)) return false;
        // iOS/Android: отказ камеры часто валит весь getUserMedia с video:true.
        // Для видеозвонка откатываемся на audio-only, чтобы разговор состоялся.
        if (!wantVideo) rethrow;
        if (kDebugMode) {
          print(
            'VoiceCall getUserMedia(video) failed, fallback audio: $videoErr',
          );
        }
        candidate = await adoptCallScopedResource<MediaStream>(
          resource: navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          }),
          token: token,
          isCurrent: _isSetupCurrent,
          dispose: _disposeMediaStreamSafe,
        );
        if (candidate == null) return false;
        fellBackToAudio = true;
        _lastCameraAccess = MicrophoneAccess.permanentlyDenied;
      }
      if (!_isSetupCurrent(token)) {
        await _disposeMediaStreamSafe(candidate);
        return false;
      }
      if (candidate.getAudioTracks().isEmpty) {
        await _disposeMediaStreamSafe(candidate);
        await _finalizeFailedCall('Не удалось запустить микрофон');
        return false;
      }
      if (wantVideo && candidate.getVideoTracks().isEmpty) {
        if (kDebugMode) {
          print('VoiceCall: no video tracks, continuing audio-only');
        }
        fellBackToAudio = true;
      }

      for (final track in candidate.getAudioTracks()) {
        track.enabled = !_desiredMuted;
      }
      for (final track in candidate.getVideoTracks()) {
        track.enabled = !_desiredCameraOff;
      }
      _requireCurrent(token);
      _localStream = candidate;

      if (fellBackToAudio) {
        _desiredCameraOff = true;
        _emit(
          _snapshot.copyWith(
            isCameraOff: true,
            isMuted: _desiredMuted,
            statusMessage: _snapshot.statusMessage?.contains('Камера') == true
                ? _snapshot.statusMessage
                : 'Камера недоступна — вы без видео',
          ),
        );
        _notifyCameraUnavailable();
        return true;
      }
      if (wantVideo) {
        _emit(
          _snapshot.copyWith(
            isMuted: _desiredMuted,
            isCameraOff: _desiredCameraOff,
            isUsingFrontCamera: _usingFrontCamera,
          ),
        );
        unawaited(_updateKeepAliveForLocalMedia());
      } else if (_snapshot.isMuted != _desiredMuted) {
        _emit(_snapshot.copyWith(isMuted: _desiredMuted));
      }
      return true;
    } catch (e) {
      await _disposeMediaStreamSafe(candidate);
      if (!_isGenerationCurrent(token)) return false;
      if (e is _StaleCallSetup) return false;
      if (kDebugMode) print('VoiceCall getUserMedia: $e');
      final err = e.toString().toLowerCase();
      if (err.contains('peerconnection') ||
          err.contains('transceivers') ||
          err.contains('nullpointer')) {
        _markWebRtcMediaBroken();
      }
      final notAllowed =
          err.contains('notallowed') ||
          err.contains('permission') ||
          err.contains('denied') ||
          err.contains('notauthorized');
      final msg = _webRtcMediaBroken
          ? 'Ошибка WebRTC. Полностью закройте приложение и откройте снова.'
          : notAllowed
          ? (kIsWeb
                ? 'Нет доступа к микрофону. Разрешите в настройках браузера.'
                : 'Нет доступа к микрофону. Разрешите в Настройках → Reollity → Микрофон.')
          : 'Не удалось запустить медиа: ${_shortError(e)}';
      await _finalizeFailedCall(msg);
      return false;
    }
  }

  Future<void> _preparePeerConnectionShell(CallEpochToken token) async {
    if (!_isSetupCurrent(token)) throw const _StaleCallSetup();
    if (_pc != null) return;

    if (_peerConnectionSetupInFlight != null) {
      await _peerConnectionSetupInFlight;
      _requireCurrent(token);
      return;
    }

    final setup = _preparePeerConnectionShellImpl(token);
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
        stunUrls = urls
            .map((e) => e.toString())
            .where((u) => u.startsWith('stun:'))
            .toList();
      } else {
        final u = urls?.toString() ?? '';
        stunUrls = u.startsWith('stun:') ? [u] : <String>[];
      }
      if (stunUrls.isEmpty) continue;
      out.add({'urls': stunUrls.length == 1 ? stunUrls.first : stunUrls});
    }
    return out;
  }

  Future<RTCPeerConnection> _createAlivePeerConnection(
    CallEpochToken token,
  ) async {
    if (_webRtcMediaBroken) {
      throw StateError('WebRTC media stack broken');
    }

    final full = await _loadIceServers(token);
    _requireCurrent(token);
    final stunOnly = _iceServersStunOnly(full);
    const defaults = WebRtcConfig.defaultIceServers;
    // Полный набор (со TURN) всегда первым — иначе Android мог «успешно»
    // создать PC на STUN-only и застрять за симметричным NAT.
    final attempts = buildIceServerAttempts(
      full: full,
      stunOnly: stunOnly,
      defaults: defaults,
    );

    Object? lastError;
    for (var i = 0; i < attempts.length; i++) {
      final servers = attempts[i];
      RTCPeerConnection? pc;
      try {
        await _ensureWebRtcInitialized();
        _requireCurrent(token);
        await _prepareAudioSessionForCall(token);
        _requireCurrent(token);

        pc = await adoptCallScopedResource<RTCPeerConnection>(
          resource: createPeerConnection(<String, dynamic>{
            'iceServers': servers,
            'sdpSemantics': 'unified-plan',
            'bundlePolicy': 'max-bundle',
            'rtcpMuxPolicy': 'require',
          }),
          token: token,
          isCurrent: _isSetupCurrent,
          dispose: _disposePeerConnectionSafe,
        );
        if (pc == null) throw const _StaleCallSetup();

        if (!await _isPeerConnectionAlive(pc)) {
          if (!_isSetupCurrent(token)) {
            await _disposePeerConnectionSafe(pc);
            throw const _StaleCallSetup();
          }
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
            _requireCurrent(token);
          }
          lastError = StateError('native PeerConnection null');
          continue;
        }

        _requireCurrent(token);
        if (kDebugMode) {
          print('VoiceCall: PeerConnection OK on attempt ${i + 1}');
        }
        return pc;
      } on _StaleCallSetup {
        await _disposePeerConnectionSafe(pc);
        rethrow;
      } catch (e) {
        lastError = e;
        await _disposePeerConnectionSafe(pc);
        _requireCurrent(token);
        if (kDebugMode) print('VoiceCall createPC attempt ${i + 1}: $e');
      }
    }

    _requireCurrent(token);
    _markWebRtcMediaBroken();
    throw lastError ?? StateError('PeerConnection unavailable');
  }

  Future<void> _handleIceFailed({String? message}) async {
    if (!_snapshot.isActive || !_ownsCallMedia) return;
    final token = _captureSetupToken();
    if (token == null) return;
    _clearIceDisconnectedGrace();
    if (_iceRestartPending || _iceRestartInFlight) return;
    if (_iceRestartAttempts < _maxIceRestartAttempts && _pc != null) {
      _iceRestartAttempts++;
      _iceRestartPending = true;
      if (kDebugMode) {
        print('VoiceCall: ICE failed, restart attempt $_iceRestartAttempts');
      }
      // Не переводим в connecting+35s — иначе здоровый restart убивает звонок.
      _cancelConnectingTimeout();
      _emit(_snapshot.copyWith(statusMessage: 'Переподключение…'));
      _startIceRestartWatchdog();
      final ok = await _attemptIceRestart();
      if (!_isSetupCurrent(token)) return;
      if (ok) return;
      _clearIceRestartPending();
    }
    await _finalizeFailedCall(
      message ??
          (_hasTurnServer
              ? 'Не удалось установить медиа-соединение (ICE)'
              : 'Не удалось соединиться. Нужен TURN на сервере (см. docs/VOICE_CALLS_COTURN.md)'),
    );
  }

  void _handleIceDisconnected() {
    if (!shouldStartIceDisconnectedGrace(
      callActive: _snapshot.isActive,
      ownsMedia: _ownsCallMedia,
      restartPending: _iceRestartPending || _iceRestartInFlight,
    )) {
      return;
    }
    if (_iceDisconnectedGraceTimer?.isActive == true) return;
    final token = _captureSetupToken();
    if (token == null) return;
    if (kDebugMode) print('VoiceCall: ICE disconnected, starting grace');
    _emit(_snapshot.copyWith(statusMessage: 'Слабая связь…'));
    _iceDisconnectedGraceTimer = Timer(
      iceDisconnectedGraceDuration(hasTurn: _hasTurnServer),
      () {
        if (!_isSetupCurrent(token)) return;
        if (_isIceOrPcHealthy(requireIce: true)) {
          _markConnected();
          return;
        }
        unawaited(_handleIceFailed(message: 'Соединение прервалось'));
      },
    );
  }

  void _clearIceDisconnectedGrace() {
    _iceDisconnectedGraceTimer?.cancel();
    _iceDisconnectedGraceTimer = null;
  }

  /// App resume / network flap: refresh TURN REST creds if needed, then probe ICE.
  Future<void> onNetworkOrAppResume() async {
    if (!_snapshot.isActive || !_ownsCallMedia) return;
    final token = _captureSetupToken();
    if (token == null) return;
    try {
      await _refreshIceCredentialsOnPeer(token, forceRefresh: false);
    } on _StaleCallSetup {
      return;
    } catch (_) {}
    if (!_isSetupCurrent(token)) return;
    if (_isIceOrPcHealthy(requireIce: true)) {
      _markConnected();
      return;
    }
    if (_snapshot.phase == VoiceCallPhase.connected ||
        _snapshot.phase == VoiceCallPhase.connecting) {
      unawaited(_handleIceFailed(message: 'Переподключение после смены сети'));
    }
  }

  /// Один раз пробуем ICE restart (offerer шлёт новый offer с iceRestart).
  Future<bool> _attemptIceRestart() async {
    if (_iceRestartInFlight) return false;
    final token = _captureSetupToken();
    final pc = _pc;
    if (token == null || pc == null || !_ownsCallMedia) return false;
    _iceRestartInFlight = true;
    try {
      // Time-limited TURN REST must land on the PC before restartIce.
      await _refreshIceCredentialsOnPeer(token, forceRefresh: true);
      _requireCurrent(token, peerConnection: pc);
      // Новое поколение ICE: не применяем кандидаты к старому remote SDP.
      _pendingRemoteCandidates.clear();
      _remoteDescriptionSet = false;
      try {
        await pc.restartIce();
        _requireCurrent(token, peerConnection: pc);
      } catch (e) {
        if (!_isSetupCurrent(token, peerConnection: pc)) return false;
        if (kDebugMode) print('VoiceCall restartIce: $e');
      }
      if (!_isOfferer) {
        final sent = _sendSignal({
          'type': 'call_ice_restart',
          'call_id': token.callId,
          'chat_id': _snapshot.chatId,
        });
        return sent;
      }
      final offer = await pc.createOffer(<String, dynamic>{
        'iceRestart': true,
        if (_snapshot.isVideo) 'offerToReceiveVideo': true,
        'offerToReceiveAudio': true,
      });
      _requireCurrent(token, peerConnection: pc);
      await pc.setLocalDescription(offer);
      _requireCurrent(token, peerConnection: pc);
      final sent = _sendSignal({
        'type': 'call_offer',
        'call_id': token.callId,
        'chat_id': _snapshot.chatId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      return sent;
    } on _StaleCallSetup {
      return false;
    } catch (e, st) {
      if (kDebugMode) print('VoiceCall ICE restart failed: $e\n$st');
      return false;
    } finally {
      if (_isGenerationCurrent(token)) {
        _iceRestartInFlight = false;
      }
    }
  }

  void _startIceRestartWatchdog() {
    _iceRestartTimer?.cancel();
    final token = _captureSetupToken();
    if (token == null) return;
    _iceRestartTimer = Timer(const Duration(seconds: 20), () {
      if (!_isSetupCurrent(token) || !_iceRestartPending) return;
      // Не смотрим на phase==connected — restart специально оставляет connected.
      unawaited(() async {
        if (!_isSetupCurrent(token)) return;
        if (_isIceOrPcHealthy()) {
          _markConnected();
          return;
        }
        if (!_isSetupCurrent(token)) return;
        await _finalizeFailedCall('Не удалось переподключить медиа за 20 с');
      }());
    });
  }

  void _clearIceRestartPending() {
    _iceRestartPending = false;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _clearIceDisconnectedGrace();
  }

  void _wirePeerConnectionHandlers(RTCPeerConnection pc, CallEpochToken token) {
    _requireCurrent(token);
    _pc = pc;
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_isSetupCurrent(token, peerConnection: pc) ||
          _snapshot.chatId == null) {
        return;
      }
      _sendSignal({
        'type': 'call_ice',
        'call_id': token.callId,
        'chat_id': _snapshot.chatId,
        'candidate': candidate.toMap(),
      });
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (!_isSetupCurrent(token, peerConnection: pc)) return;
      unawaited(_bindRemoteTrack(event, token, pc));
    };

    pc.onAddStream = (MediaStream stream) {
      if (!_isSetupCurrent(token, peerConnection: pc)) return;
      unawaited(_handleRemoteStream(stream, token, pc));
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (!_isSetupCurrent(token, peerConnection: pc)) return;
      if (kDebugMode) print('VoiceCall ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceRestartAttempts = 0;
        _peerIceRestartHonored = 0;
        _clearIceDisconnectedGrace();
        // Не снимаем pending до _markConnected — иначе early-return оставляет UI.
        _markConnected();
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _handleIceDisconnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        unawaited(_handleIceFailed());
      }
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (!_isSetupCurrent(token, peerConnection: pc)) return;
      if (kDebugMode) print('VoiceCall PC state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _iceRestartAttempts = 0;
        _peerIceRestartHonored = 0;
        _clearIceDisconnectedGrace();
        _markConnected();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_handleIceFailed(message: 'Соединение потеряно'));
      }
    };

    pc.onSignalingState = (RTCSignalingState state) {
      if (!_isSetupCurrent(token, peerConnection: pc)) return;
      if (kDebugMode) print('VoiceCall signaling: $state');
    };
  }

  Future<void> _preparePeerConnectionShellImpl(CallEpochToken token) async {
    if (!_isSetupCurrent(token)) throw const _StaleCallSetup();
    if (_pc != null) return;

    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();

    RTCPeerConnection? pc;
    try {
      pc = await _createAlivePeerConnection(token);
      _requireCurrent(token);
      _wirePeerConnectionHandlers(pc, token);
    } on _StaleCallSetup {
      await _disposePeerConnectionSafe(pc);
      rethrow;
    } catch (e) {
      await _disposePeerConnectionSafe(pc);
      if (!_isGenerationCurrent(token)) throw const _StaleCallSetup();
      await _tearDownMedia();
      rethrow;
    }
  }

  Future<void> _attachLocalTracksToPeerConnection(
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    _requireCurrent(token, peerConnection: pc);
    final stream = _localStream;
    if (stream == null || stream.getAudioTracks().isEmpty) {
      throw StateError('local audio stream missing');
    }

    final senders = await pc.getSenders();
    _requireCurrent(token, peerConnection: pc);
    final hasAudio = senders.any((s) => s.track?.kind == 'audio');
    final hasVideo = senders.any((s) => s.track?.kind == 'video');

    if (!hasAudio) {
      for (final track in stream.getAudioTracks()) {
        await pc.addTrack(track, stream);
        _requireCurrent(token, peerConnection: pc);
      }
    }
    // Видео опционально: если камеру отклонили, идём audio-only.
    if (_snapshot.isVideo && !hasVideo) {
      for (final track in stream.getVideoTracks()) {
        await pc.addTrack(track, stream);
        _requireCurrent(token, peerConnection: pc);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadIceServers(
    CallEpochToken token, {
    bool forceRefresh = false,
  }) async {
    _requireCurrent(token);
    if (!forceRefresh &&
        _iceServers != null &&
        IceServersPayload(
          iceServers: _iceServers!,
          expiresAt: _iceExpiresAt,
          credentialType: _iceCredentialType,
        ).isFresh()) {
      return _iceServers!;
    }
    try {
      final authToken = await StorageService.getToken();
      _requireCurrent(token);
      if (authToken == null || authToken.isEmpty) {
        _iceServers = WebRtcConfig.defaultIceServers;
        _iceExpiresAt = null;
        _iceCredentialType = 'none';
        _hasTurnServer = _detectTurnInServers(_iceServers!);
        return _iceServers!;
      }
      final response = await timedGet(
        Uri.parse('${ApiConfig.baseUrl}/calls/ice-servers'),
        headers: {'Authorization': 'Bearer $authToken'},
        timeout: const Duration(seconds: 8),
      );
      _requireCurrent(token);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map) {
          final payload = IceServersPayload.fromMap(body);
          if (payload.iceServers.isNotEmpty) {
            _iceServers = _normalizeIceServers(payload.iceServers);
            _iceExpiresAt = payload.expiresAt;
            _iceCredentialType = payload.credentialType;
            _hasTurnServer = payload.hasTurn || _detectTurnInServers(_iceServers!);
            if (kDebugMode) {
              print(
                'VoiceCall ICE servers: count=${_iceServers!.length}, '
                'hasTurn=$_hasTurnServer, type=$_iceCredentialType, '
                'expiresAt=$_iceExpiresAt',
              );
            }
            return _iceServers!;
          }
        }
      }
    } on _StaleCallSetup {
      rethrow;
    } catch (e) {
      if (kDebugMode) print('VoiceCall ICE load error: $e');
    }
    _requireCurrent(token);
    if (_iceServers != null && _iceServers!.isNotEmpty) {
      return _iceServers!;
    }
    _iceServers = WebRtcConfig.defaultIceServers;
    _iceExpiresAt = null;
    _iceCredentialType = 'none';
    _hasTurnServer = _detectTurnInServers(_iceServers!);
    return _iceServers!;
  }

  Future<void> _ensureFreshIceServers(
    CallEpochToken token, {
    required bool forceRefresh,
  }) async {
    final stale =
        forceRefresh ||
        !IceServersPayload(
          iceServers: _iceServers ?? const [],
          expiresAt: _iceExpiresAt,
          credentialType: _iceCredentialType,
        ).isFresh();
    if (!stale && _iceServers != null) return;
    await _loadIceServers(token, forceRefresh: true);
  }

  /// Fetch fresh TURN REST credentials and apply them to the live PC.
  /// Fetch alone is not enough — restartIce would keep the expired username.
  Future<void> _refreshIceCredentialsOnPeer(
    CallEpochToken token, {
    required bool forceRefresh,
  }) async {
    await _ensureFreshIceServers(token, forceRefresh: forceRefresh);
    _requireCurrent(token);
    final pc = _pc;
    final servers = _iceServers;
    if (pc == null || servers == null || servers.isEmpty) return;
    try {
      final current = Map<String, dynamic>.from(pc.getConfiguration);
      final next = mergeIceServersIntoPeerConfiguration(current, servers);
      await pc.setConfiguration(next);
      _requireCurrent(token, peerConnection: pc);
      if (kDebugMode) {
        print(
          'VoiceCall: applied ICE config '
          '(type=$_iceCredentialType, expiresAt=$_iceExpiresAt)',
        );
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall setConfiguration: $e');
    }
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

  Future<bool> _ensureMicrophonePermission([CallEpochToken? setupToken]) async {
    final access = await MicrophonePermission.ensure();
    if (setupToken != null && !_isGenerationCurrent(setupToken)) return false;
    _lastMicAccess = access;
    switch (access) {
      case MicrophoneAccess.granted:
        return true;
      case MicrophoneAccess.permanentlyDenied:
        _emitFailed(
          kIsWeb
              ? 'Нет доступа к микрофону. Разрешите микрофон для этого сайта '
                    'в настройках браузера (иконка замка в адресной строке).'
              : 'Нет доступа к микрофону. Разрешите в Настройках → Reollity → Микрофон.',
        );
        return false;
      case MicrophoneAccess.denied:
        _emitFailed('Нет доступа к микрофону');
        return false;
    }
  }

  Future<void> _requestCameraPermissionBestEffort([
    CallEpochToken? setupToken,
  ]) async {
    final access = await CameraPermission.ensure();
    if (setupToken != null && !_isGenerationCurrent(setupToken)) return;
    _lastCameraAccess = access;
    // permanentlyDenied на Android после явного отказа — подсказка в UI при ошибке getUserMedia.
  }

  Future<void> _prepareAudioSessionForCall(CallEpochToken token) async {
    if (kIsWeb) return;
    _requireCurrent(token);
    try {
      if (WebRTC.platformIsIOS) {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: preferredSpeakerOn,
        );
      } else if (WebRTC.platformIsAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall audio session: $e');
    }
    _requireCurrent(token);
  }

  Future<void> _bindRemoteTrack(
    RTCTrackEvent event,
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    if (!_isSetupCurrent(token, peerConnection: pc)) return;
    try {
      event.track.enabled = true;
    } catch (_) {}
    if (event.streams.isNotEmpty) {
      await _handleRemoteStream(event.streams.first, token, pc);
      return;
    }
    final kind = event.track.kind ?? 'media';
    final stream = await adoptCallScopedResource<MediaStream>(
      resource: createLocalMediaStream('remote-$kind-${token.callId}'),
      token: token,
      isCurrent: (candidate) => _isSetupCurrent(candidate, peerConnection: pc),
      dispose: _disposeMediaStreamSafe,
    );
    if (stream == null) return;
    await stream.addTrack(event.track);
    if (!_isSetupCurrent(token, peerConnection: pc)) {
      await _disposeMediaStreamSafe(stream);
      return;
    }
    await _handleRemoteStream(stream, token, pc);
  }

  Future<void> _handleRemoteStream(
    MediaStream stream,
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    if (!_isSetupCurrent(token, peerConnection: pc)) return;
    final hasAudio = stream.getAudioTracks().isNotEmpty;
    final hasVideo = stream.getVideoTracks().isNotEmpty;
    if (!hasAudio && !hasVideo) return;

    for (final track in stream.getAudioTracks()) {
      try {
        track.enabled = true;
      } catch (_) {}
    }
    for (final track in stream.getVideoTracks()) {
      try {
        track.enabled = true;
      } catch (_) {}
    }

    // Merge tracks into one remote stream when audio/video arrive separately.
    if (_remoteStream != null && !identical(_remoteStream, stream)) {
      try {
        for (final track in stream.getTracks()) {
          if (!_isSetupCurrent(token, peerConnection: pc)) return;
          final already = _remoteStream!.getTracks().any(
            (t) => t.id == track.id && t.kind == track.kind,
          );
          if (!already) {
            await _remoteStream!.addTrack(track);
            if (!_isSetupCurrent(token, peerConnection: pc)) return;
          }
        }
      } catch (e) {
        if (kDebugMode) print('VoiceCall merge remote stream: $e');
        if (!_isSetupCurrent(token, peerConnection: pc)) return;
        _remoteStream = stream;
      }
    } else {
      _remoteStream = stream;
    }

    if (!_isSetupCurrent(token, peerConnection: pc)) return;
    final remoteHasVideo =
        !_snapshot.isRemoteCameraOff &&
        _remoteStream!.getVideoTracks().isNotEmpty;
    if (remoteHasVideo != _snapshot.hasRemoteVideo) {
      _emit(_snapshot.copyWith(hasRemoteVideo: remoteHasVideo));
    }
    // Не помечаем connected по одному track: во время ICE restart
    // onTrack может прийти раньше Connected и сорвать watchdog.
    _markConnectedIfIceHealthy();
  }

  bool _isIceOrPcHealthy({bool requireIce = false}) {
    final pc = _pc;
    if (pc == null) return false;
    try {
      final ice = pc.iceConnectionState;
      final conn = pc.connectionState;
      final iceOk =
          ice == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          ice == RTCIceConnectionState.RTCIceConnectionStateCompleted;
      final connOk =
          conn == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      // Во время ICE restart connectionState часто остаётся connected —
      // требуем живой ICE, иначе ложное «На связи».
      if (requireIce || _iceRestartPending) return iceOk;
      return iceOk || connOk;
    } catch (_) {
      return false;
    }
  }

  void _markConnectedIfIceHealthy() {
    if (!_isIceOrPcHealthy()) return;
    _markConnected();
  }

  void _markConnected() {
    final wasRestarting = _iceRestartPending;
    if (_snapshot.phase == VoiceCallPhase.connected && !wasRestarting) {
      unawaited(_maybeLogIcePathMetrics());
      return;
    }
    // Во время restart требуем живой ICE — иначе «На связи» с мёртвым медиа.
    if (wasRestarting && !_isIceOrPcHealthy(requireIce: true)) return;
    _webRtcMediaBroken = false;
    _clearIceRestartPending();
    _iceRestartAttempts = 0;
    _peerIceRestartHonored = 0;
    _cancelConnectingTimeout();
    unawaited(_reassertCallAudioSession());
    unawaited(_ensureKeepAliveForMedia());
    unawaited(_maybeLogIcePathMetrics());
    _emit(
      _snapshot.copyWith(
        phase: VoiceCallPhase.connected,
        statusMessage: 'На связи',
      ),
    );
  }

  Future<void> _maybeLogIcePathMetrics() async {
    if (_loggedIcePathMetrics) return;
    final pc = _pc;
    if (pc == null) return;
    try {
      final stats = await pc.getStats();
      final reports = stats
          .map(
            (s) => <String, dynamic>{
              'id': s.id,
              'type': s.type,
              'values': s.values,
            },
          )
          .toList();
      final metrics = parseSelectedIcePathMetrics(reports);
      if (metrics == null) return;
      _loggedIcePathMetrics = true;
      // Coarse path type only — never SDP / candidate addresses.
      if (kDebugMode) {
        debugPrint('VoiceCall ICE path: ${metrics.toLogMap()}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('VoiceCall ICE metrics: $e');
    }
  }

  /// Подтверждаем режим «звонок». Маршрут earpiece/speaker — за UI (не форсим).
  Future<void> _reassertCallAudioSession() async {
    if (kIsWeb) return;
    try {
      if (WebRTC.platformIsIOS) {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: preferredSpeakerOn,
        );
      } else if (WebRTC.platformIsAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
        // Не вызываем setSpeakerphoneOn здесь — иначе затираем выбор пользователя.
      }
    } catch (e) {
      if (kDebugMode) print('VoiceCall reassert audio session: $e');
    }
  }

  void _startConnectingTimeout() {
    _connectingTimer?.cancel();
    final token = _captureSetupToken();
    if (token == null) return;
    _connectingTimer = Timer(const Duration(seconds: 35), () {
      if (!_isSetupCurrent(token) ||
          _snapshot.phase != VoiceCallPhase.connecting) {
        return;
      }
      _clearIceRestartPending();
      unawaited(
        _finalizeFailedCall(
          _hasTurnServer
              ? 'Не удалось соединиться за 35 с. Проверьте интернет и повторите.'
              : 'Не удалось соединиться. На сервере не настроен TURN — '
                    'эмулятор и телефон в разных сетях без него не соединятся. '
                    'См. docs/VOICE_CALLS_COTURN.md',
        ),
      );
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

  Future<void> _setRemoteDescription(
    RTCSessionDescription desc,
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    _requireCurrent(token, peerConnection: pc);
    await pc.setRemoteDescription(desc);
    _requireCurrent(token, peerConnection: pc);
    _remoteDescriptionSet = true;
    await _flushPendingIceCandidates(token, pc);
  }

  Future<void> _addRemoteIceCandidate(
    RTCIceCandidate candidate,
    CallEpochToken token,
  ) async {
    if (!_isSetupCurrent(token)) return;
    final pc = _pc;
    if (pc == null || !_remoteDescriptionSet) {
      // PC ещё нет (ранний trickle) или remote SDP не set — копим.
      if (_pendingRemoteCandidates.length >= _maxPendingRemoteCandidates) {
        _pendingRemoteCandidates.removeAt(0);
      }
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
      if (!_isSetupCurrent(token, peerConnection: pc)) return;
    } catch (e) {
      if (kDebugMode) print('VoiceCall ICE error: $e');
    }
  }

  Future<void> _flushPendingIceCandidates(
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    if (!_isSetupCurrent(token, peerConnection: pc) ||
        _pendingRemoteCandidates.isEmpty) {
      return;
    }
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await pc.addCandidate(candidate);
        _requireCurrent(token, peerConnection: pc);
      } on _StaleCallSetup {
        return;
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
    _cancelIncomingTimeout();
  }

  void _startOutgoingTimeout() {
    _outgoingTimer?.cancel();
    final token = _captureSetupToken();
    if (token == null) return;
    _outgoingTimer = Timer(const Duration(seconds: 60), () {
      if (!_isSetupCurrent(token) ||
          _snapshot.phase != VoiceCallPhase.outgoing) {
        return;
      }
      unawaited(_finalizeFailedCall('Нет ответа'));
    });
  }

  void _cancelOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = null;
  }

  void _startIncomingTimeout({DateTime? expiresAt}) {
    _incomingTimer?.cancel();
    final token = _captureSetupToken();
    if (token == null) return;
    // Чуть дольше серверного RINGING_STALE (75s) — даём hangup от sweep.
    var timeout = const Duration(seconds: 80);
    if (expiresAt != null) {
      final remaining =
          expiresAt.difference(DateTime.now()) + const Duration(seconds: 5);
      final milliseconds = remaining.inMilliseconds
          .clamp(1_000, 80_000)
          .toInt();
      timeout = Duration(milliseconds: milliseconds);
    }
    _incomingTimer = Timer(timeout, () {
      if (!_isSetupCurrent(token) ||
          _snapshot.phase != VoiceCallPhase.incoming) {
        return;
      }
      unawaited(rejectIncoming(reason: 'ringing_timeout'));
    });
  }

  void _cancelIncomingTimeout() {
    _incomingTimer?.cancel();
    _incomingTimer = null;
  }

  Future<void> _tearDownMedia() async {
    _callEpoch.invalidate();
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _resyncAttempts = 0;
    _pendingResyncRequestId = null;
    _pendingResyncCallId = null;
    _pendingResyncWasActive = false;
    _resetPeerConnectionState();
    _peerConnectionSetupInFlight = null;
    _localAudioSetupInFlight = null;
    _iceServers = null;
    _iceExpiresAt = null;
    _iceCredentialType = 'none';
    _hasTurnServer = false;
    _iceRestartAttempts = 0;
    _iceRestartInFlight = false;
    _peerIceRestartHonored = 0;
    _loggedIcePathMetrics = false;
    _clearIceRestartPending();
    _clearIceDisconnectedGrace();
    _isOfferer = false;
    _desiredMuted = false;
    _desiredCameraOff = false;
    _usingFrontCamera = true;
    // Detach synchronously. A new call may start while native dispose awaits.
    final pc = _pc;
    final localStream = _localStream;
    final remoteStream = _remoteStream;
    _pc = null;
    _localStream = null;
    _remoteStream = null;
    // Minimize → hangup: экран уже disposed и не сбросил speaker.
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }
    await _disposeMediaStreamSafe(localStream);
    await _disposeMediaStreamSafe(remoteStream);
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
    final wasActive = _snapshot.isActive;
    final prevPhase = _snapshot.phase;
    _snapshot = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
    // FGS только когда реально поднимаем медиа (mic уже запрошен).
    if (next.phase == VoiceCallPhase.connecting ||
        next.phase == VoiceCallPhase.connected) {
      if (prevPhase != VoiceCallPhase.connecting &&
          prevPhase != VoiceCallPhase.connected) {
        unawaited(_ensureKeepAliveForMedia());
      }
    }
    if (!next.isActive && wasActive) {
      _speakerOnPreferred = null;
      unawaited(_releaseKeepAlive());
    }
  }

  Future<void> _ensureKeepAliveForMedia() async {
    if (_keepAliveHeld) return;
    _keepAliveHeld = true;
    // Mic-only FGS: camera type на API 34+ требует runtime CAMERA до startForeground.
    await CallKeepAlive.acquire(owner: _keepAliveOwner, isVideo: false);
  }

  Future<void> _updateKeepAliveForLocalMedia() async {
    if (!_keepAliveHeld) return;
    final hasCamera = _localStream?.getVideoTracks().isNotEmpty ?? false;
    await CallKeepAlive.update(owner: _keepAliveOwner, isVideo: hasCamera);
  }

  Future<void> _releaseKeepAlive() async {
    if (!_keepAliveHeld) return;
    _keepAliveHeld = false;
    await CallKeepAlive.release(owner: _keepAliveOwner);
  }

  void _emitFailed(String message) {
    _emit(
      VoiceCallSnapshot(
        phase: VoiceCallPhase.failed,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        peerUserId: _snapshot.peerUserId,
        peerLabel: _snapshot.peerLabel,
        mediaType: _snapshot.mediaType,
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
        _ownsCallMedia = false;
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
      case 'signaling_unavailable':
      case 'realtime_unavailable':
        return 'Сервис звонков временно недоступен';
      default:
        return 'Не удалось выполнить звонок';
    }
  }
}

class _StaleCallSetup implements Exception {
  const _StaleCallSetup();
}
