import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/api_config.dart';
import '../config/webrtc_config.dart';
import '../models/group_call.dart';
import '../utils/call_epoch.dart';
import '../utils/call_keep_alive.dart';
import '../utils/call_playback_pause.dart';
import '../utils/camera_permission.dart';
import '../utils/microphone_permission.dart';
import '../utils/timed_http.dart';
import '../utils/webrtc_device_support.dart';
import '../utils/webrtc_ice_attempts.dart';
import '../utils/webrtc_ice_credentials.dart';
import 'storage_service.dart';
import 'livekit_group_call_session.dart';
import 'voice_call_service.dart';
import 'websocket_service.dart';

export '../models/group_call.dart';

/// Public group-call facade. A call is pinned to LiveKit (`lkcall_*`) or the
/// legacy mesh (`gcall_*`) before invitations and never switches mid-call.
class GroupVoiceCallService {
  GroupVoiceCallService._() : _liveKitSession = LiveKitGroupCallSession() {
    _listenToLiveKitSession();
  }

  GroupVoiceCallService.forTesting({
    required LiveKitGroupCallSession liveKitSession,
  }) : _liveKitSession = liveKitSession {
    _listenToLiveKitSession();
  }

  static final GroupVoiceCallService instance = GroupVoiceCallService._();
  static const String _keepAliveOwner = 'group-call';

  static const int maxParticipants = 4;

  final StreamController<GroupCallSnapshot> _stateController =
      StreamController<GroupCallSnapshot>.broadcast();
  final LiveKitGroupCallSession _liveKitSession;

  Stream<GroupCallSnapshot> get stateStream => _stateController.stream;
  GroupCallSnapshot _snapshot = const GroupCallSnapshot();
  final CallEpoch _callEpoch = CallEpoch();

  StreamSubscription<dynamic>? _wsSub;
  StreamSubscription<LiveKitSessionState>? _liveKitStateSub;
  String? _myUserId;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};
  final Set<String> _remoteDescReady = {};
  final Set<String> _offeredTo = {};
  final Map<String, int> _peerIceRestarts = {};
  final Map<String, Future<RTCPeerConnection>> _peerConnectionSetups = {};
  static const int _maxPeerIceRestarts = 1;
  List<Map<String, dynamic>>? _iceServers;
  DateTime? _iceExpiresAt;
  String _iceCredentialType = 'none';
  bool _webRtcInitialized = false;
  MicrophoneAccess? _lastMicAccess;
  Timer? _idleResetTimer;
  Timer? _outgoingTimer;
  Timer? _joinAckTimer;
  Timer? _incomingTimer;
  bool _keepAliveHeld = false;
  bool _acceptInFlight = false;
  Future<bool>? _localAudioSetupInFlight;
  bool? _speakerOnPreferred;
  bool _desiredMuted = false;
  Completer<bool>? _systemJoinCompleter;
  _PendingLiveKitCall? _pendingLiveKitCall;
  Future<void>? _liveKitTeardownFuture;
  bool _ignoreLiveKitStates = false;

  GroupCallSnapshot get snapshot => _snapshot;
  MicrophoneAccess? get lastMicrophoneAccess => _lastMicAccess;
  MediaStream? remoteStreamFor(String userId) => _remoteStreams[userId];

  bool get preferredSpeakerOn => _speakerOnPreferred ?? true;

  void _listenToLiveKitSession() {
    _liveKitStateSub?.cancel();
    _liveKitStateSub = _liveKitSession.states.listen((state) {
      if (_ignoreLiveKitStates) return;
      if (_snapshot.transport != GroupCallTransport.livekit) return;
      final sessionIds = state.participants.map((peer) => peer.userId).toSet();
      final controlOnly = _snapshot.roster.where(
        (peer) => !sessionIds.contains(peer.userId),
      );
      _emit(
        _snapshot.copyWith(
          phase: state.phase,
          mediaType: state.cameraFallback
              ? GroupCallMediaType.audio
              : _snapshot.mediaType,
          statusMessage: state.statusMessage,
          disconnectReason: state.disconnectReason,
          isMuted: state.isMuted,
          isCameraEnabled: state.isCameraEnabled,
          isSpeakerOn: state.isSpeakerOn,
          webAudioBlocked: state.webAudioBlocked,
          joinedAt:
              state.phase == GroupCallPhase.connected &&
                  _snapshot.joinedAt == null
              ? DateTime.now()
              : _snapshot.joinedAt,
          roster: [...state.participants, ...controlOnly],
        ),
      );
      if (_keepAliveHeld) {
        unawaited(
          CallKeepAlive.update(
            owner: _keepAliveOwner,
            isVideo: state.isCameraEnabled,
          ),
        );
      }
    });
  }

  void setPreferredSpeakerOn(bool enabled) {
    if (_speakerOnPreferred == enabled && _snapshot.isSpeakerOn == enabled) {
      return;
    }
    _speakerOnPreferred = enabled;
    if (_snapshot.transport == GroupCallTransport.livekit &&
        _snapshot.isActive) {
      unawaited(_liveKitSession.setSpeakerOn(enabled));
      _emit(_snapshot.copyWith(isSpeakerOn: enabled));
    }
  }

  void _beginCallGeneration(String callId) {
    _callEpoch.begin(callId);
    _desiredMuted = false;
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

  bool _isGenerationCurrent(CallEpochToken token) {
    return _callEpoch.isCurrent(token) && _snapshot.callId == token.callId;
  }

  bool _isSetupCurrent(
    CallEpochToken token, {
    String? peerId,
    RTCPeerConnection? peerConnection,
  }) {
    if (!_isGenerationCurrent(token) || !_snapshot.isActive) return false;
    if (peerId != null && peerConnection != null) {
      return identical(_pcs[peerId], peerConnection);
    }
    return true;
  }

  void _requireCurrent(
    CallEpochToken token, {
    String? peerId,
    RTCPeerConnection? peerConnection,
  }) {
    if (!_isSetupCurrent(
      token,
      peerId: peerId,
      peerConnection: peerConnection,
    )) {
      throw const _StaleGroupCallSetup();
    }
  }

  Future<void> _disposeStreamSafe(MediaStream? stream) async {
    try {
      await stream?.dispose();
    } catch (e) {
      if (kDebugMode) print('GroupCall dispose stream: $e');
    }
  }

  Future<void> _disposePeerConnectionSafe(
    RTCPeerConnection? pc, {
    bool delay = true,
  }) async {
    try {
      await pc?.dispose();
    } catch (_) {}
    if (delay && pc != null && !kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
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
    _outgoingTimer?.cancel();
    _joinAckTimer?.cancel();
    _incomingTimer?.cancel();
    _idleResetTimer = null;
    _outgoingTimer = null;
    _joinAckTimer = null;
    _incomingTimer = null;
    _acceptInFlight = false;
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(false);
    }
    _systemJoinCompleter = null;
    _speakerOnPreferred = null;
    _pendingLiveKitCall = null;
    unawaited(_tearDownLiveKit());
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
    GroupCallMediaType mediaType = GroupCallMediaType.audio,
  }) async {
    try {
      if (VoiceCallService.instance.snapshot.isActive) {
        _emitFailed('Сначала завершите личный звонок');
        return false;
      }
      if (_snapshot.isActive) {
        _emitFailed('Звонок уже идёт');
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
      await bindUserIfNeeded();
      if (_myUserId == null) {
        _emitFailed('Не удалось начать звонок. Перезайдите в приложение.');
        return false;
      }
      await CallPlaybackPause.pauseBestEffort();
      if (!await _ensureMicrophonePermission()) {
        _emitFailed('Нет доступа к микрофону');
        return false;
      }
      var enableCamera = false;
      if (mediaType == GroupCallMediaType.video) {
        enableCamera =
            await CameraPermission.ensure() == MicrophoneAccess.granted;
      }
      if (!await _ensureSignalingConnected()) {
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
        return false;
      }

      String? appVersion;
      try {
        appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}
      final pendingId = 'lk-pending-${DateTime.now().microsecondsSinceEpoch}';
      _beginCallGeneration(pendingId);
      _pendingLiveKitCall = _PendingLiveKitCall(
        chatId: chatId,
        chatName: chatName,
        mediaType: mediaType,
        enableCamera: enableCamera,
      );
      _emit(
        GroupCallSnapshot(
          phase: GroupCallPhase.outgoing,
          transport: GroupCallTransport.livekit,
          mediaType: mediaType,
          callId: pendingId,
          chatId: chatId,
          chatName: chatName,
          statusMessage: 'Выбираем соединение…',
          isSpeakerOn: preferredSpeakerOn,
          roster: [
            GroupCallPeer(
              userId: _myUserId!,
              label: 'Вы',
              state: 'joined',
              isLocal: true,
              isMuted: false,
            ),
          ],
        ),
      );
      _startOutgoingTimeout();
      final sent = _send({
        'type': 'lkcall_create',
        'chat_id': chatId,
        'protocol_version': 2,
        if (appVersion != null) 'app_version': appVersion,
        'initial_media_type': mediaType.name,
      });
      if (!sent) return _fallbackPendingLiveKitToMesh();
      return true;
    } catch (e, st) {
      if (kDebugMode) print('GroupCall transport selection: $e\n$st');
      return _fallbackPendingLiveKitToMesh();
    }
  }

  Future<bool> _fallbackPendingLiveKitToMesh() async {
    final pending = _pendingLiveKitCall;
    if (pending == null) return false;
    _pendingLiveKitCall = null;
    _cancelOutgoingTimeout();
    _callEpoch.invalidate();
    _emit(const GroupCallSnapshot(phase: GroupCallPhase.idle));
    return _startLegacyGroupCall(
      chatId: pending.chatId,
      chatName: pending.chatName,
    );
  }

  Future<bool> _startLegacyGroupCall({
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
      if (!await _ensureMicrophonePermission()) {
        _emitFailed('Нет доступа к микрофону');
        return false;
      }
      if (!await _ensureWebRtcReady()) return false;
      if (!await _ensureSignalingConnected()) {
        _emitFailed('Нет соединения с сервером. Проверьте интернет.');
        return false;
      }

      final callId = _newCallId();
      _beginCallGeneration(callId);
      _emit(
        GroupCallSnapshot(
          phase: GroupCallPhase.outgoing,
          transport: GroupCallTransport.mesh,
          mediaType: GroupCallMediaType.audio,
          callId: callId,
          chatId: chatId,
          chatName: chatName,
          statusMessage: 'Создаём звонок…',
          roster: [
            GroupCallPeer(userId: _myUserId!, label: 'Вы', state: 'joined'),
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

  Future<void> acceptIncoming({bool withVideo = false}) async {
    if (_snapshot.transport == GroupCallTransport.livekit) {
      return _acceptLiveKitIncoming(withVideo: withVideo);
    }
    return _acceptLegacyIncoming();
  }

  /// Claims the server-side invitation before LiveKit requests credentials.
  /// CallKit uses this path so only the WebSocket connection that won the
  /// atomic join receives the answer ticket.
  Future<bool> acceptIncomingFromSystem() async {
    if (_snapshot.transport != GroupCallTransport.livekit) {
      await acceptIncoming();
      return _snapshot.phase == GroupCallPhase.connecting ||
          _snapshot.phase == GroupCallPhase.connected;
    }
    if (_acceptInFlight || _snapshot.phase != GroupCallPhase.incoming) {
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
      _pendingLiveKitCall = _PendingLiveKitCall(
        chatId: chatId,
        chatName: _snapshot.chatName ?? 'Группа',
        mediaType: _snapshot.mediaType,
        // A system answer starts audio-only; video can be enabled from the app.
        enableCamera: false,
      );
      _cancelIncomingTimeout();
      _emit(
        _snapshot.copyWith(
          phase: GroupCallPhase.connecting,
          statusMessage: 'Подключение…',
        ),
      );
      _startJoinAckTimeout();
      final completer = Completer<bool>();
      _systemJoinCompleter = completer;
      if (!_send({
        'type': 'lkcall_join',
        'call_id': callId,
        'chat_id': chatId,
        'protocol_version': 2,
      })) {
        _systemJoinCompleter = null;
        _cancelJoinAckTimeout();
        return false;
      }
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      _systemJoinCompleter = null;
      _acceptInFlight = false;
    }
  }

  Future<void> _acceptLiveKitIncoming({required bool withVideo}) async {
    if (_acceptInFlight || _snapshot.phase != GroupCallPhase.incoming) return;
    _acceptInFlight = true;
    try {
      if (VoiceCallService.instance.snapshot.isActive) {
        await rejectIncoming(reason: 'busy');
        _emitFailed('Сначала завершите личный звонок');
        return;
      }
      final token = _captureSetupToken();
      final callId = _snapshot.callId;
      final chatId = _snapshot.chatId;
      if (token == null || callId == null || chatId == null) return;
      await CallPlaybackPause.pauseBestEffort();
      if (!_isSetupCurrent(token)) return;
      if (!await _ensureMicrophonePermission(token)) {
        if (_isGenerationCurrent(token)) {
          await rejectIncoming(reason: 'no_mic');
          _emitFailed('Нет доступа к микрофону');
        }
        return;
      }
      var enableCamera = false;
      if (withVideo) {
        enableCamera =
            await CameraPermission.ensure() == MicrophoneAccess.granted;
        if (!_isSetupCurrent(token)) return;
      }
      final pending = _pendingLiveKitCall;
      _pendingLiveKitCall = _PendingLiveKitCall(
        chatId: chatId,
        chatName: _snapshot.chatName ?? pending?.chatName ?? 'Группа',
        mediaType: _snapshot.mediaType,
        enableCamera: enableCamera,
      );
      _cancelIncomingTimeout();
      _emit(
        _snapshot.copyWith(
          phase: GroupCallPhase.connecting,
          statusMessage: 'Подключение…',
        ),
      );
      _startJoinAckTimeout();
      if (!_send({
        'type': 'lkcall_join',
        'call_id': callId,
        'chat_id': chatId,
        'protocol_version': 2,
      })) {
        _cancelJoinAckTimeout();
        await rejectIncoming(reason: 'media_error');
        _emitFailed('Нет соединения с сервером');
      }
    } catch (e, st) {
      if (kDebugMode) print('LiveKit group accept: $e\n$st');
      if (_snapshot.isActive) {
        await rejectIncoming(reason: 'media_error');
      }
      _emitFailed('Не удалось присоединиться');
    } finally {
      _acceptInFlight = false;
    }
  }

  Future<void> _acceptLegacyIncoming() async {
    if (_acceptInFlight) return;
    _acceptInFlight = true;
    try {
      if (_snapshot.phase != GroupCallPhase.incoming) return;
      final token = _captureSetupToken();
      final callId = _snapshot.callId;
      final chatId = _snapshot.chatId;
      if (token == null || callId == null || chatId == null) return;
      if (VoiceCallService.instance.snapshot.isActive) {
        await rejectIncoming(reason: 'busy');
        _emitFailed('Сначала завершите личный звонок');
        return;
      }
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
        _emitFailed('Нет доступа к микрофону');
        await rejectIncoming(reason: 'no_mic');
        return;
      }
      if (!_isSetupCurrent(token)) return;
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
      if (_snapshot.phase != GroupCallPhase.incoming ||
          !_isSetupCurrent(token)) {
        return;
      }

      _emit(
        _snapshot.copyWith(
          phase: GroupCallPhase.connecting,
          statusMessage: 'Подключение…',
        ),
      );
      _cancelIncomingTimeout();
      _startJoinAckTimeout();
      final sent = _send({
        'type': 'gcall_join',
        'call_id': callId,
        'chat_id': chatId,
      });
      if (!sent) {
        _cancelJoinAckTimeout();
        await rejectIncoming(reason: 'media_error');
        _emitFailed('Нет соединения с сервером');
      }
    } on _StaleGroupCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('GroupCall accept: $e\n$st');
      _cancelJoinAckTimeout();
      // Если gcall_join уже ушёл — leave, иначе reject.
      final joinMayHaveSent = _snapshot.phase == GroupCallPhase.connecting;
      if (joinMayHaveSent) {
        await leave(statusMessage: 'Не удалось присоединиться');
      } else {
        await _tearDownAll();
        if (_snapshot.phase == GroupCallPhase.incoming ||
            _snapshot.phase == GroupCallPhase.connecting ||
            _snapshot.phase == GroupCallPhase.failed) {
          await rejectIncoming(reason: 'media_error');
        }
        _emitFailed('Не удалось присоединиться');
      }
    } finally {
      _acceptInFlight = false;
    }
  }

  Future<void> rejectIncoming({String reason = 'declined'}) async {
    if (_snapshot.transport == GroupCallTransport.livekit) {
      return _rejectLiveKitIncoming(reason);
    }
    // failed: после _emitFailed в accept всё ещё нужно слать gcall_reject.
    if (_snapshot.phase != GroupCallPhase.incoming &&
        _snapshot.phase != GroupCallPhase.connecting &&
        _snapshot.phase != GroupCallPhase.failed) {
      return;
    }
    _cancelJoinAckTimeout();
    _cancelIncomingTimeout();
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

  Future<void> _rejectLiveKitIncoming(String reason) async {
    if (_snapshot.phase != GroupCallPhase.incoming &&
        _snapshot.phase != GroupCallPhase.connecting &&
        _snapshot.phase != GroupCallPhase.failed) {
      return;
    }
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(false);
    }
    _cancelJoinAckTimeout();
    _cancelIncomingTimeout();
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null) {
      _send({
        'type': 'lkcall_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': reason,
      });
    }
    await _tearDownLiveKit();
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        transport: GroupCallTransport.livekit,
        mediaType: _snapshot.mediaType,
        callId: callId,
        chatId: chatId,
        chatName: _snapshot.chatName,
        statusMessage: 'Отклонён',
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> leave({String? statusMessage}) async {
    if (_snapshot.transport == GroupCallTransport.livekit) {
      return _leaveLiveKit(statusMessage: statusMessage);
    }
    _cancelJoinAckTimeout();
    _cancelOutgoingTimeout();
    final token = _callEpoch.capture();
    final callId = _snapshot.callId;
    final chatId = _snapshot.chatId;
    if (callId != null && chatId != null && _snapshot.isActive) {
      var sent = _send({
        'type': 'gcall_leave',
        'call_id': callId,
        'chat_id': chatId,
      });
      if (!sent) {
        await WebSocketService.instance.connectIfNeeded();
        if (token != null && !_isGenerationCurrent(token)) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (token != null && !_isGenerationCurrent(token)) return;
        sent = _send({
          'type': 'gcall_leave',
          'call_id': callId,
          'chat_id': chatId,
        });
      }
    }
    if (token != null && !_isGenerationCurrent(token)) return;
    await _tearDownAll();
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        statusMessage: statusMessage ?? 'Вы вышли',
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> _leaveLiveKit({String? statusMessage}) async {
    _cancelJoinAckTimeout();
    _cancelOutgoingTimeout();
    final callId = _snapshot.callId;
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(false);
    }
    final chatId = _snapshot.chatId;
    if (callId != null &&
        chatId != null &&
        _snapshot.isActive &&
        !callId.startsWith('lk-pending-')) {
      _send({
        'type': 'lkcall_leave',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'left',
      });
    }
    await _tearDownLiveKit();
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        transport: GroupCallTransport.livekit,
        mediaType: _snapshot.mediaType,
        statusMessage: statusMessage ?? 'Вы вышли',
      ),
    );
    _scheduleIdleReset();
  }

  Future<void> abortActiveCall(String message) async {
    if (!_snapshot.isActive) return;
    await leave(statusMessage: message);
  }

  Future<void> shutdownForAccountChange() async {
    if (_snapshot.isActive) {
      await leave(statusMessage: 'Звонок завершён');
    }
    reset();
    await Future.wait<void>([_tearDownLiveKit(), _tearDownAll()]);
  }

  Future<void> toggleMute() => setMuted(!_desiredMuted);

  Future<void> setMuted(bool muted) async {
    _desiredMuted = muted;
    if (_snapshot.transport == GroupCallTransport.livekit) {
      await _liveKitSession.setMuted(_desiredMuted);
      _emit(_snapshot.copyWith(isMuted: _desiredMuted));
      return;
    }
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_desiredMuted;
      }
    }
    _emit(_snapshot.copyWith(isMuted: _desiredMuted));
  }

  Future<bool> toggleCamera() async {
    if (_snapshot.transport != GroupCallTransport.livekit) return false;
    final enable = !_snapshot.isCameraEnabled;
    if (enable) {
      final access = await CameraPermission.ensure();
      if (access != MicrophoneAccess.granted) return false;
    }
    final changed = await _liveKitSession.setCameraEnabled(enable);
    if (changed) {
      _emit(
        _snapshot.copyWith(
          isCameraEnabled: enable,
          mediaType: enable ? GroupCallMediaType.video : _snapshot.mediaType,
        ),
      );
      if (_keepAliveHeld) {
        unawaited(
          CallKeepAlive.update(owner: _keepAliveOwner, isVideo: enable),
        );
      }
    }
    return changed;
  }

  Future<void> switchCamera() async {
    if (_snapshot.transport != GroupCallTransport.livekit ||
        !_snapshot.isCameraEnabled) {
      return;
    }
    await _liveKitSession.switchCamera();
    _emit(
      _snapshot.copyWith(isUsingFrontCamera: !_snapshot.isUsingFrontCamera),
    );
  }

  Future<void> recoverWebAudio() => _liveKitSession.recoverWebAudio();

  void applyIncomingFromPush({
    required String callId,
    required String chatId,
    required String chatName,
    required String fromUserId,
    required String fromLabel,
    DateTime? expiresAt,
    GroupCallTransport transport = GroupCallTransport.mesh,
    GroupCallMediaType mediaType = GroupCallMediaType.audio,
  }) {
    if (callId.isEmpty || chatId.isEmpty) return;
    unawaited(bindUserIfNeeded());
    unawaited(WebSocketService.instance.connectIfNeeded());
    if (_snapshot.isActive) {
      if (_snapshot.callId == callId && _snapshot.transport == transport) {
        return;
      }
      _send({
        'type': transport == GroupCallTransport.livekit
            ? 'lkcall_reject'
            : 'gcall_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'busy',
      });
      return;
    }
    if (VoiceCallService.instance.snapshot.isActive) {
      _send({
        'type': transport == GroupCallTransport.livekit
            ? 'lkcall_reject'
            : 'gcall_reject',
        'call_id': callId,
        'chat_id': chatId,
        'reason': 'busy',
      });
      return;
    }

    unawaited(CallPlaybackPause.pauseBestEffort());

    _beginCallGeneration(callId);
    if (transport == GroupCallTransport.livekit) {
      _pendingLiveKitCall = _PendingLiveKitCall(
        chatId: chatId,
        chatName: chatName,
        mediaType: mediaType,
        enableCamera: false,
      );
    }
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.incoming,
        transport: transport,
        mediaType: mediaType,
        callId: callId,
        chatId: chatId,
        chatName: chatName.isNotEmpty ? chatName : 'Группа',
        statusMessage: mediaType == GroupCallMediaType.video
            ? 'Входящий групповой видеозвонок'
            : 'Входящий групповой звонок',
        roster: [
          GroupCallPeer(
            userId: fromUserId,
            label: fromLabel.isNotEmpty ? fromLabel : 'Участник',
            state: 'joined',
          ),
        ],
      ),
    );
    _startIncomingTimeout(expiresAt: expiresAt);
  }

  void _onWsEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type == null) return;
    if (type.startsWith('lkcall_')) {
      _onLiveKitWsEvent(event);
      return;
    }
    if (!type.startsWith('gcall_')) return;

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
      case 'gcall_ice_restart':
        unawaited(_onPeerIceRestartRequest(event));
        break;
      case 'gcall_error':
        _onError(event);
        break;
    }
  }

  void _onLiveKitWsEvent(Map event) {
    final type = event['type']?.toString();
    switch (type) {
      case 'lkcall_use_mesh':
        if (_snapshot.transport == GroupCallTransport.livekit &&
            _snapshot.phase == GroupCallPhase.outgoing) {
          unawaited(_fallbackPendingLiveKitToMesh());
        }
        break;
      case 'lkcall_created':
        unawaited(_onLiveKitCreated(event));
        break;
      case 'lkcall_invite':
        _onLiveKitInvite(event);
        break;
      case 'lkcall_joined':
        unawaited(_onLiveKitJoined(event));
        break;
      case 'lkcall_answered_elsewhere':
        unawaited(_onLiveKitAnsweredElsewhere(event));
        break;
      case 'lkcall_peer_status':
        _onLiveKitPeerStatus(event);
        break;
      case 'lkcall_ended':
        unawaited(_onLiveKitEnded(event));
        break;
      case 'lkcall_error':
        _onLiveKitError(event);
        break;
    }
  }

  Future<void> _onLiveKitCreated(Map event) async {
    if (_snapshot.transport != GroupCallTransport.livekit ||
        _snapshot.phase != GroupCallPhase.outgoing) {
      return;
    }
    final callId = event['call_id']?.toString() ?? '';
    if (callId.isEmpty) return;
    final pending = _pendingLiveKitCall;
    if (pending == null) return;
    _cancelOutgoingTimeout();
    _beginCallGeneration(callId);
    _emit(
      _snapshot.copyWith(
        phase: GroupCallPhase.connecting,
        callId: callId,
        chatId: event['chat_id']?.toString() ?? pending.chatId,
        chatName: event['chat_name']?.toString() ?? pending.chatName,
        statusMessage: 'Подключение…',
        roster: _parseRoster(event),
      ),
    );
    await _connectLiveKit(callId, enableCamera: pending.enableCamera);
  }

  Future<void> _onLiveKitJoined(Map event) async {
    if (_snapshot.transport != GroupCallTransport.livekit ||
        _snapshot.phase != GroupCallPhase.connecting ||
        !_matchesActive(event)) {
      return;
    }
    _cancelJoinAckTimeout();
    final callId = _snapshot.callId;
    final pending = _pendingLiveKitCall;
    if (callId == null || pending == null) return;
    _emit(_snapshot.copyWith(roster: _parseRoster(event)));
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(true);
    }
    await _connectLiveKit(
      callId,
      enableCamera: pending.enableCamera,
      answerTicket: event['answer_ticket']?.toString(),
    );
  }

  Future<void> _connectLiveKit(
    String callId, {
    required bool enableCamera,
    String? answerTicket,
  }) async {
    final token = _captureSetupToken();
    if (token == null) return;
    final connected = await _liveKitSession.connect(
      callId: callId,
      enableCamera: enableCamera,
      speakerOn: preferredSpeakerOn,
      answerTicket: answerTicket,
    );
    if (!_isGenerationCurrent(token)) return;
    if (!connected) {
      _send({
        'type': 'lkcall_leave',
        'call_id': callId,
        'chat_id': _snapshot.chatId,
        'reason': 'media_error',
      });
      _emitFailed('Не удалось подключиться к групповому звонку');
    }
  }

  Future<void> _onLiveKitAnsweredElsewhere(Map event) async {
    if (_snapshot.transport != GroupCallTransport.livekit ||
        !_matchesActive(event)) {
      return;
    }
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(false);
    }
    _cancelJoinAckTimeout();
    _cancelIncomingTimeout();
    await _tearDownLiveKit();
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        transport: GroupCallTransport.livekit,
        mediaType: _snapshot.mediaType,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        chatName: _snapshot.chatName,
        statusMessage: 'Звонок принят на другом устройстве',
      ),
    );
    _scheduleIdleReset();
  }

  void _onLiveKitInvite(Map event) {
    final callId = event['call_id']?.toString() ?? '';
    final chatId = event['chat_id']?.toString() ?? '';
    if (callId.isEmpty || chatId.isEmpty) return;
    if (_snapshot.isActive && _snapshot.callId == callId) {
      _emit(_snapshot.copyWith(roster: _parseRoster(event)));
      return;
    }
    final mediaType = event['initial_media_type']?.toString() == 'video'
        ? GroupCallMediaType.video
        : GroupCallMediaType.audio;
    applyIncomingFromPush(
      callId: callId,
      chatId: chatId,
      chatName: event['chat_name']?.toString() ?? 'Группа',
      fromUserId: event['from_user_id']?.toString() ?? '',
      fromLabel: event['from_label']?.toString() ?? '',
      expiresAt: DateTime.tryParse(event['expires_at']?.toString() ?? ''),
      transport: GroupCallTransport.livekit,
      mediaType: mediaType,
    );
    if (_snapshot.callId == callId) {
      _emit(_snapshot.copyWith(roster: _parseRoster(event)));
    }
  }

  void _onLiveKitPeerStatus(Map event) {
    if (_snapshot.transport != GroupCallTransport.livekit ||
        !_matchesActive(event)) {
      return;
    }
    final controlRoster = _parseRoster(event);
    final mediaPeers = {
      for (final peer in _snapshot.roster.where(
        (peer) => peer.state == 'joined' && peer.videoTrack != null,
      ))
        peer.userId: peer,
    };
    _emit(
      _snapshot.copyWith(
        roster: controlRoster
            .map((peer) => mediaPeers[peer.userId] ?? peer)
            .toList(),
      ),
    );
  }

  Future<void> _onLiveKitEnded(Map event) async {
    if (_snapshot.transport != GroupCallTransport.livekit ||
        !_matchesActive(event)) {
      return;
    }
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(false);
    }
    await _tearDownLiveKit();
    final reason = event['reason']?.toString() ?? '';
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.ended,
        transport: GroupCallTransport.livekit,
        mediaType: _snapshot.mediaType,
        statusMessage: reason == 'no_answer'
            ? 'Никто не ответил'
            : 'Звонок завершён',
      ),
    );
    _scheduleIdleReset();
  }

  void _onLiveKitError(Map event) {
    final code = event['code']?.toString() ?? 'error';
    if (_snapshot.transport != GroupCallTransport.livekit) return;
    if (!(_systemJoinCompleter?.isCompleted ?? true)) {
      _systemJoinCompleter?.complete(false);
    }
    if (_snapshot.phase == GroupCallPhase.outgoing &&
        _pendingLiveKitCall != null &&
        (code == 'livekit_unavailable' ||
            code == 'room_create_failed' ||
            code == 'unsupported_protocol')) {
      unawaited(_fallbackPendingLiveKitToMesh());
      return;
    }
    final eventCallId = event['call_id']?.toString();
    final activeCallId = _snapshot.callId;
    if (eventCallId != null &&
        activeCallId != null &&
        !activeCallId.startsWith('lk-pending-') &&
        eventCallId != activeCallId) {
      return;
    }
    _cancelOutgoingTimeout();
    _cancelJoinAckTimeout();
    unawaited(_tearDownLiveKit());
    _emitFailed(_humanize(code));
  }

  void _onInvite(Map event) {
    final callId = event['call_id']?.toString() ?? '';
    final chatId = event['chat_id']?.toString() ?? '';
    if (callId.isEmpty || chatId.isEmpty) return;

    unawaited(CallPlaybackPause.pauseBestEffort());

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
    _beginCallGeneration(callId);
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
    _startIncomingTimeout();
    unawaited(_preloadIceServers());
  }

  void _onCreated(Map event) {
    if (!_matchesActive(event) && _snapshot.phase != GroupCallPhase.outgoing) {
      return;
    }
    _cancelOutgoingTimeout();
    final roster = _parseRoster(event);
    final resolvedCallId = event['call_id']?.toString() ?? _snapshot.callId;
    if (resolvedCallId != null &&
        resolvedCallId.isNotEmpty &&
        resolvedCallId != _snapshot.callId) {
      _beginCallGeneration(resolvedCallId);
    }
    _emit(
      _snapshot.copyWith(
        phase: GroupCallPhase.connected,
        callId: resolvedCallId,
        chatId: event['chat_id']?.toString() ?? _snapshot.chatId,
        chatName: event['chat_name']?.toString() ?? _snapshot.chatName,
        statusMessage: 'Ожидание участников…',
        roster: roster,
      ),
    );
    final token = _captureSetupToken();
    if (token == null) return;
    unawaited(() async {
      if (!await _ensureLocalAudio(token)) {
        if (!_isGenerationCurrent(token)) return;
        await leave(statusMessage: 'Не удалось запустить микрофон');
        return;
      }
      for (final p in roster) {
        if (!_isSetupCurrent(token)) return;
        if (p.state != 'joined') continue;
        if (p.userId == _myUserId) continue;
        if (_pcs.containsKey(p.userId) && _offeredTo.contains(p.userId)) {
          continue;
        }
        await _createAndSendOfferTo(p.userId, token);
      }
    }());
  }

  Future<void> _onJoined(Map event) async {
    if (!_matchesActive(event) &&
        _snapshot.phase != GroupCallPhase.connecting) {
      return;
    }
    _cancelJoinAckTimeout();
    _cancelOutgoingTimeout();
    final roster = _parseRoster(event);
    _emit(
      _snapshot.copyWith(
        phase: GroupCallPhase.connected,
        statusMessage: 'На связи',
        roster: roster,
      ),
    );
    final token = _captureSetupToken();
    if (token == null) return;
    if (!await _ensureLocalAudio(token)) {
      if (!_isGenerationCurrent(token)) return;
      await leave(statusMessage: 'Не удалось запустить микрофон');
      return;
    }
    // Late joiner must offer to existing peers with higher id (mesh edge).
    final me = _myUserId;
    if (me == null) return;
    for (final p in roster) {
      if (!_isSetupCurrent(token)) return;
      if (p.state != 'joined') continue;
      if (p.userId == me) continue;
      if (me.compareTo(p.userId) > 0) continue;
      if (_pcs.containsKey(p.userId) && _offeredTo.contains(p.userId)) {
        continue;
      }
      await _createAndSendOfferTo(p.userId, token);
    }
  }

  Future<void> _onPeerJoined(Map event) async {
    if (!_matchesActive(event)) return;
    // peer_joined может прийти пока host ещё в outgoing.
    if (!_snapshot.isActive) return;
    final token = _captureSetupToken();
    if (token == null) return;
    _emit(_snapshot.copyWith(roster: _parseRoster(event)));
    final peerId =
        event['user_id']?.toString() ?? event['from_user_id']?.toString() ?? '';
    if (peerId.isEmpty || peerId == _myUserId) return;
    if (!await _ensureLocalAudio(token)) {
      if (!_isGenerationCurrent(token)) return;
      await leave(statusMessage: 'Не удалось запустить микрофон');
      return;
    }
    // Детерминированный offerer — избегаем glare при mesh join.
    final me = _myUserId;
    if (me == null || me.compareTo(peerId) > 0) return;
    await _createAndSendOfferTo(peerId, token);
  }

  Future<void> _onPeerLeft(Map event) async {
    if (!_matchesActive(event)) return;
    final token = _captureSetupToken();
    if (token == null) return;
    final peerId = event['from_user_id']?.toString() ?? '';
    if (peerId.isNotEmpty && peerId != 'system' && peerId != _myUserId) {
      await _disposePeer(peerId);
    }
    if (!_isSetupCurrent(token)) return;
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
    if (!_matchesActive(event)) return;
    await _tearDownAll();
    final reason = event['reason']?.toString() ?? '';
    final msg = reason == 'no_answer' || reason == 'ringing_timeout'
        ? 'Никто не ответил'
        : reason == 'empty'
        ? 'Звонок завершён'
        : 'Звонок завершён';
    _emit(GroupCallSnapshot(phase: GroupCallPhase.ended, statusMessage: msg));
    _scheduleIdleReset();
  }

  Future<void> _onOffer(Map event) async {
    if (!_matchesActive(event)) return;
    final token = _captureSetupToken();
    if (token == null) return;
    final fromId = event['from_user_id']?.toString() ?? '';
    if (fromId.isEmpty || fromId == _myUserId) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;

    if (!await _ensureLocalAudio(token)) return;
    if (!_isSetupCurrent(token)) return;
    final stream = _localStream;
    if (stream == null || stream.getAudioTracks().isEmpty) return;

    // Re-offer после ICE recover: сбрасываем старый PC на этом edge.
    if (_pcs.containsKey(fromId)) {
      await _disposePeer(fromId);
      if (!_isSetupCurrent(token)) return;
    }

    RTCPeerConnection? pc;
    try {
      pc = await _ensurePeerConnection(fromId, token);
      _requireCurrent(token, peerId: fromId, peerConnection: pc);
      final desc = RTCSessionDescription(
        sdpMap['sdp']?.toString() ?? '',
        sdpMap['type']?.toString() ?? '',
      );
      await pc.setRemoteDescription(desc);
      _requireCurrent(token, peerId: fromId, peerConnection: pc);
      _remoteDescReady.add(fromId);
      await _flushIce(fromId, token, pc);

      for (final track in stream.getAudioTracks()) {
        final senders = await pc.getSenders();
        _requireCurrent(token, peerId: fromId, peerConnection: pc);
        if (!senders.any((s) => s.track?.kind == 'audio')) {
          await pc.addTrack(track, stream);
          _requireCurrent(token, peerId: fromId, peerConnection: pc);
        }
      }

      final answer = await pc.createAnswer(<String, dynamic>{});
      _requireCurrent(token, peerId: fromId, peerConnection: pc);
      await pc.setLocalDescription(answer);
      _requireCurrent(token, peerId: fromId, peerConnection: pc);
      _send({
        'type': 'gcall_answer',
        'call_id': token.callId,
        'chat_id': _snapshot.chatId,
        'to_user_id': fromId,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
    } on _StaleGroupCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('GroupCall answer to $fromId: $e\n$st');
      if (_isGenerationCurrent(token)) {
        await _disposePeer(fromId, expectedPeerConnection: pc);
      }
    }
  }

  Future<void> _onAnswer(Map event) async {
    if (!_matchesActive(event)) return;
    final token = _captureSetupToken();
    if (token == null) return;
    final fromId = event['from_user_id']?.toString() ?? '';
    if (fromId.isEmpty) return;
    final pc = _pcs[fromId];
    if (pc == null) return;
    final sdpMap = event['sdp'];
    if (sdpMap is! Map) return;
    try {
      await pc.setRemoteDescription(
        RTCSessionDescription(
          sdpMap['sdp']?.toString() ?? '',
          sdpMap['type']?.toString() ?? '',
        ),
      );
      _requireCurrent(token, peerId: fromId, peerConnection: pc);
      _remoteDescReady.add(fromId);
      await _flushIce(fromId, token, pc);
    } on _StaleGroupCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('GroupCall set answer from $fromId: $e\n$st');
      if (_isGenerationCurrent(token)) {
        await _disposePeer(fromId, expectedPeerConnection: pc);
      }
    }
  }

  Future<void> _onIce(Map event) async {
    if (!_matchesActive(event)) return;
    final token = _captureSetupToken();
    if (token == null) return;
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
      if (!_isSetupCurrent(token)) return;
      (_pendingIce[fromId] ??= []).add(ice);
      return;
    }
    final pc = _pcs[fromId];
    if (pc == null) return;
    try {
      await pc.addCandidate(ice);
      if (!_isSetupCurrent(token, peerId: fromId, peerConnection: pc)) {
        return;
      }
    } catch (e) {
      if (kDebugMode) print('GroupCall ICE: $e');
    }
  }

  void _onError(Map event) {
    final code = event['code']?.toString() ?? 'error';
    final errCallId = event['call_id']?.toString();
    final errChat = event['chat_id']?.toString();
    // Trickle ICE burst не должен рвать живой групповой звонок.
    if (code == 'rate_limited' &&
        (_snapshot.phase == GroupCallPhase.connected ||
            _snapshot.phase == GroupCallPhase.connecting)) {
      if (kDebugMode) print('GroupCall: ignoring rate_limited during media');
      return;
    }
    // chat_call_active: сервер шлёт call_id уже активного звонка, не наш local id.
    if (code == 'chat_call_active') {
      if (errChat != null &&
          _snapshot.chatId != null &&
          errChat != _snapshot.chatId) {
        return;
      }
    } else if (_snapshot.isActive &&
        errCallId != null &&
        errCallId != _snapshot.callId) {
      return;
    }
    _cancelOutgoingTimeout();
    _cancelJoinAckTimeout();
    unawaited(_tearDownAll());
    _emitFailed(_humanize(code));
  }

  Future<void> _createAndSendOfferTo(
    String peerId,
    CallEpochToken token,
  ) async {
    if (!_isSetupCurrent(token)) return;
    if (_pcs.containsKey(peerId) && _offeredTo.contains(peerId)) return;
    if (!await _ensureLocalAudio(token)) return;
    if (!_isSetupCurrent(token)) return;
    final stream = _localStream;
    if (stream == null || stream.getAudioTracks().isEmpty) return;

    RTCPeerConnection? pc;
    try {
      // Если PC создали, но offer не ушёл — не оставляем zombie.
      if (_pcs.containsKey(peerId) && !_offeredTo.contains(peerId)) {
        await _disposePeer(peerId);
        _requireCurrent(token);
      }
      pc = await _ensurePeerConnection(peerId, token);
      _requireCurrent(token, peerId: peerId, peerConnection: pc);
      for (final track in stream.getAudioTracks()) {
        final senders = await pc.getSenders();
        _requireCurrent(token, peerId: peerId, peerConnection: pc);
        if (!senders.any((s) => s.track?.kind == 'audio')) {
          await pc.addTrack(track, stream);
          _requireCurrent(token, peerId: peerId, peerConnection: pc);
        }
      }
      final offer = await pc.createOffer(<String, dynamic>{
        'offerToReceiveAudio': true,
      });
      _requireCurrent(token, peerId: peerId, peerConnection: pc);
      await pc.setLocalDescription(offer);
      _requireCurrent(token, peerId: peerId, peerConnection: pc);
      final sent = _send({
        'type': 'gcall_offer',
        'call_id': token.callId,
        'chat_id': _snapshot.chatId,
        'to_user_id': peerId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      if (!sent) {
        await _disposePeer(peerId, expectedPeerConnection: pc);
        return;
      }
      _requireCurrent(token, peerId: peerId, peerConnection: pc);
      _offeredTo.add(peerId);
    } on _StaleGroupCallSetup {
      return;
    } catch (e, st) {
      if (kDebugMode) print('GroupCall offer to $peerId: $e\n$st');
      if (_isGenerationCurrent(token)) {
        await _disposePeer(peerId, expectedPeerConnection: pc);
      }
    }
  }

  Future<void> _recoverPeerConnection(
    String peerId,
    CallEpochToken token,
    RTCPeerConnection failedPeerConnection,
  ) async {
    if (!_isSetupCurrent(
      token,
      peerId: peerId,
      peerConnection: failedPeerConnection,
    )) {
      return;
    }
    final restarts = _peerIceRestarts[peerId] ?? 0;
    if (restarts >= _maxPeerIceRestarts) {
      if (kDebugMode) {
        print('GroupCall: ICE failed for $peerId, no more restarts');
      }
      await _disposePeer(peerId, expectedPeerConnection: failedPeerConnection);
      return;
    }
    _peerIceRestarts[peerId] = restarts + 1;
    final stillJoined = _snapshot.roster.any(
      (p) => p.userId == peerId && p.state == 'joined',
    );
    final me = _myUserId;
    // Только детерминированный offerer — иначе glare (оба шлют offer).
    final shouldOffer = me != null && me.compareTo(peerId) < 0;
    await _disposePeer(peerId, expectedPeerConnection: failedPeerConnection);
    if (!_isSetupCurrent(token)) return;
    if (!stillJoined || me == null) return;
    if (!shouldOffer) {
      // Answerer просит offerer'а пересоздать offer.
      _send({
        'type': 'gcall_ice_restart',
        'call_id': token.callId,
        'chat_id': _snapshot.chatId,
        'to_user_id': peerId,
      });
      return;
    }
    if (kDebugMode) {
      print('GroupCall: re-offer to $peerId after ICE fail');
    }
    await _createAndSendOfferTo(peerId, token);
  }

  Future<void> _onPeerIceRestartRequest(Map event) async {
    if (!_matchesActive(event)) return;
    final token = _captureSetupToken();
    if (token == null) return;
    final fromId = event['from_user_id']?.toString();
    if (fromId == null || fromId.isEmpty) return;
    final me = _myUserId;
    // Только offerer (меньший id) отвечает re-offer'ом.
    if (me == null || me.compareTo(fromId) >= 0) return;
    if (kDebugMode) {
      print('GroupCall: peer $fromId requested ICE restart, re-offering');
    }
    await _disposePeer(fromId);
    if (!_isSetupCurrent(token)) return;
    await _createAndSendOfferTo(fromId, token);
  }

  Future<RTCPeerConnection> _ensurePeerConnection(
    String peerId,
    CallEpochToken token,
  ) async {
    _requireCurrent(token);
    final existing = _pcs[peerId];
    if (existing != null) return existing;

    final inFlight = _peerConnectionSetups[peerId];
    if (inFlight != null) {
      final pc = await inFlight;
      _requireCurrent(token, peerId: peerId, peerConnection: pc);
      return pc;
    }

    final setup = _createPeerConnectionForPeer(peerId, token);
    _peerConnectionSetups[peerId] = setup;
    try {
      return await setup;
    } finally {
      if (identical(_peerConnectionSetups[peerId], setup)) {
        _peerConnectionSetups.remove(peerId);
      }
    }
  }

  Future<RTCPeerConnection> _createPeerConnectionForPeer(
    String peerId,
    CallEpochToken token,
  ) async {
    _requireCurrent(token);
    final full = await _loadIceServers(token);
    _requireCurrent(token);
    final stunOnly = full.where((s) {
      final urls = s['urls'];
      final list = urls is List
          ? urls.map((e) => e.toString()).toList()
          : [urls?.toString() ?? ''];
      return list.any((u) => u.startsWith('stun:'));
    }).toList();
    final attempts = buildIceServerAttempts(
      full: full,
      stunOnly: stunOnly,
      defaults: WebRtcConfig.defaultIceServers,
    );
    await _ensureWebRtcInitialized();
    _requireCurrent(token);
    RTCPeerConnection? pc;
    Object? lastError;
    for (final servers in attempts) {
      try {
        pc = await adoptCallScopedResource<RTCPeerConnection>(
          resource: createPeerConnection(<String, dynamic>{
            'iceServers': servers,
            'sdpSemantics': 'unified-plan',
            'bundlePolicy': 'max-bundle',
            'rtcpMuxPolicy': 'require',
          }),
          token: token,
          isCurrent: _isSetupCurrent,
          dispose: (candidate) =>
              _disposePeerConnectionSafe(candidate, delay: false),
        );
        if (pc == null) throw const _StaleGroupCallSetup();
        break;
      } on _StaleGroupCallSetup {
        await _disposePeerConnectionSafe(pc, delay: false);
        rethrow;
      } catch (e) {
        lastError = e;
        await _disposePeerConnectionSafe(pc);
        pc = null;
        _requireCurrent(token);
        if (kDebugMode) print('GroupCall createPC: $e');
        if (!kIsWeb) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          _requireCurrent(token);
        }
      }
    }
    if (pc == null) {
      throw lastError ?? StateError('PeerConnection unavailable');
    }
    final readyPc = pc;

    _requireCurrent(token);
    final concurrentlyCreated = _pcs[peerId];
    if (concurrentlyCreated != null) {
      await _disposePeerConnectionSafe(readyPc);
      return concurrentlyCreated;
    }
    _pcs[peerId] = readyPc;

    readyPc.onIceCandidate = (RTCIceCandidate candidate) {
      if (!_isSetupCurrent(token, peerId: peerId, peerConnection: readyPc)) {
        return;
      }
      _send({
        'type': 'gcall_ice',
        'call_id': token.callId,
        'chat_id': _snapshot.chatId,
        'to_user_id': peerId,
        'candidate': candidate.toMap(),
      });
    };

    readyPc.onTrack = (RTCTrackEvent event) {
      if (!_isSetupCurrent(token, peerId: peerId, peerConnection: readyPc)) {
        return;
      }
      if (event.track.kind != 'audio') return;
      try {
        event.track.enabled = true;
      } catch (_) {}
      if (event.streams.isNotEmpty) {
        _remoteStreams[peerId] = event.streams.first;
      }
      // Не «На связи» по одному track — только при живом ICE (как DM).
    };

    readyPc.onIceConnectionState = (RTCIceConnectionState state) {
      if (!_isSetupCurrent(token, peerId: peerId, peerConnection: readyPc)) {
        return;
      }
      if (kDebugMode) print('GroupCall ICE[$peerId]: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _peerIceRestarts[peerId] = 0;
        if (_snapshot.phase != GroupCallPhase.connected && _snapshot.isActive) {
          _emit(
            _snapshot.copyWith(
              phase: GroupCallPhase.connected,
              statusMessage: 'На связи',
            ),
          );
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        unawaited(_recoverPeerConnection(peerId, token, readyPc));
      }
    };

    return readyPc;
  }

  Future<void> _flushIce(
    String peerId,
    CallEpochToken token,
    RTCPeerConnection pc,
  ) async {
    _requireCurrent(token, peerId: peerId, peerConnection: pc);
    final pending = _pendingIce.remove(peerId);
    if (pending == null) return;
    for (final c in pending) {
      try {
        await pc.addCandidate(c);
        _requireCurrent(token, peerId: peerId, peerConnection: pc);
      } on _StaleGroupCallSetup {
        return;
      } catch (_) {}
    }
  }

  Future<void> _disposePeer(
    String peerId, {
    RTCPeerConnection? expectedPeerConnection,
  }) async {
    final current = _pcs[peerId];
    if (expectedPeerConnection != null &&
        !identical(current, expectedPeerConnection)) {
      return;
    }
    _pendingIce.remove(peerId);
    _remoteDescReady.remove(peerId);
    _remoteStreams.remove(peerId);
    _offeredTo.remove(peerId);
    final pc = _pcs.remove(peerId);
    await _disposePeerConnectionSafe(pc);
  }

  Future<bool> _ensureLocalAudio(CallEpochToken token) async {
    if (!_isSetupCurrent(token)) return false;
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (_localAudioSetupInFlight != null) {
      await _localAudioSetupInFlight;
      return _isSetupCurrent(token) &&
          _localStream != null &&
          _localStream!.getAudioTracks().isNotEmpty;
    }
    final setup = _ensureLocalAudioImpl(token);
    _localAudioSetupInFlight = setup;
    try {
      return await setup;
    } finally {
      if (identical(_localAudioSetupInFlight, setup)) {
        _localAudioSetupInFlight = null;
      }
    }
  }

  Future<bool> _ensureLocalAudioImpl(CallEpochToken token) async {
    if (!_isSetupCurrent(token)) return false;
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      return true;
    }
    if (!await _ensureMicrophonePermission(token)) return false;
    if (!_isSetupCurrent(token)) return false;
    MediaStream? candidate;
    try {
      await _prepareAudioSession(token);
      _requireCurrent(token);
      candidate = await adoptCallScopedResource<MediaStream>(
        resource: navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        }),
        token: token,
        isCurrent: _isSetupCurrent,
        dispose: _disposeStreamSafe,
      );
      if (candidate == null) return false;
      if (candidate.getAudioTracks().isEmpty) {
        await _disposeStreamSafe(candidate);
        return false;
      }
      for (final track in candidate.getAudioTracks()) {
        track.enabled = !_desiredMuted;
      }
      _requireCurrent(token);
      _localStream = candidate;
      if (_snapshot.isMuted != _desiredMuted) {
        _emit(_snapshot.copyWith(isMuted: _desiredMuted));
      }
      return true;
    } on _StaleGroupCallSetup {
      await _disposeStreamSafe(candidate);
      return false;
    } catch (e) {
      await _disposeStreamSafe(candidate);
      if (!_isGenerationCurrent(token)) return false;
      if (kDebugMode) print('GroupCall getUserMedia: $e');
      return false;
    }
  }

  Future<void> _prepareAudioSession(CallEpochToken token) async {
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
        // Не форсим speaker — иначе затираем UI toggle при re-GUM.
      }
    } catch (e) {
      if (kDebugMode) print('GroupCall audio session: $e');
    }
    _requireCurrent(token);
  }

  Future<bool> _ensureMicrophonePermission([CallEpochToken? setupToken]) async {
    final access = await MicrophonePermission.ensure();
    if (setupToken != null && !_isGenerationCurrent(setupToken)) return false;
    _lastMicAccess = access;
    return access == MicrophoneAccess.granted;
  }

  Future<bool> _ensureWebRtcReady([CallEpochToken? setupToken]) async {
    if (kIsWeb) return true;
    try {
      await _ensureWebRtcInitialized();
      if (setupToken != null && !_isGenerationCurrent(setupToken)) {
        return false;
      }
      return true;
    } catch (e) {
      if (setupToken != null && !_isGenerationCurrent(setupToken)) {
        return false;
      }
      _emitFailed('WebRTC недоступен в этой сборке');
      return false;
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
    final setupToken = _captureSetupToken();
    if (setupToken == null) return;
    try {
      await _loadIceServers(setupToken);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadIceServers(
    CallEpochToken setupToken, {
    bool forceRefresh = false,
  }) async {
    _requireCurrent(setupToken);
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
      _requireCurrent(setupToken);
      if (authToken == null || authToken.isEmpty) {
        _iceServers = WebRtcConfig.defaultIceServers;
        _iceExpiresAt = null;
        _iceCredentialType = 'none';
        return _iceServers!;
      }
      final response = await timedGet(
        Uri.parse('${ApiConfig.baseUrl}/calls/ice-servers'),
        headers: {'Authorization': 'Bearer $authToken'},
        timeout: const Duration(seconds: 8),
      );
      _requireCurrent(setupToken);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map) {
          final payload = IceServersPayload.fromMap(body);
          if (payload.iceServers.isNotEmpty) {
            _iceServers = payload.iceServers;
            _iceExpiresAt = payload.expiresAt;
            _iceCredentialType = payload.credentialType;
            return _iceServers!;
          }
        }
      }
    } on _StaleGroupCallSetup {
      rethrow;
    } catch (e) {
      if (kDebugMode) print('GroupCall ICE: $e');
    }
    _requireCurrent(setupToken);
    if (_iceServers != null && _iceServers!.isNotEmpty) {
      return _iceServers!;
    }
    _iceServers = WebRtcConfig.defaultIceServers;
    _iceExpiresAt = null;
    _iceCredentialType = 'none';
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
      final email =
          item['label']?.toString() ?? item['email']?.toString() ?? '';
      final state = item['state']?.toString() ?? 'ringing';
      out.add(
        GroupCallPeer(
          userId: id,
          label: id == _myUserId
              ? 'Вы'
              : (email.isNotEmpty ? email : 'Участник'),
          state: state,
          isLocal: id == _myUserId,
          isMuted: state != 'joined',
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
    if (eventCallId == null || eventCallId.isEmpty) return allowMissing;
    return eventCallId == activeId;
  }

  Future<void> _tearDownLiveKit() {
    final existing = _liveKitTeardownFuture;
    if (existing != null) return existing;
    _callEpoch.invalidate();
    _cancelOutgoingTimeout();
    _cancelJoinAckTimeout();
    _cancelIncomingTimeout();
    _pendingLiveKitCall = null;
    _desiredMuted = false;
    _ignoreLiveKitStates = true;
    final future = _liveKitSession.disconnect();
    _liveKitTeardownFuture = future;
    return future.whenComplete(() {
      _ignoreLiveKitStates = false;
      if (identical(_liveKitTeardownFuture, future)) {
        _liveKitTeardownFuture = null;
      }
    });
  }

  Future<void> _tearDownAll() async {
    _callEpoch.invalidate();
    _cancelOutgoingTimeout();
    _cancelJoinAckTimeout();
    _cancelIncomingTimeout();
    _localAudioSetupInFlight = null;
    _peerConnectionSetups.clear();
    _desiredMuted = false;
    // Detach synchronously so an old native dispose cannot clear a new call.
    final localStream = _localStream;
    final peerConnections = Map<String, RTCPeerConnection>.from(_pcs);
    _localStream = null;
    _pcs.clear();
    _iceServers = null;
    _iceExpiresAt = null;
    _iceCredentialType = 'none';
    _pendingIce.clear();
    _remoteDescReady.clear();
    _remoteStreams.clear();
    _offeredTo.clear();
    _peerIceRestarts.clear();
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }
    await _disposeStreamSafe(localStream);
    for (final pc in peerConnections.values) {
      await _disposePeerConnectionSafe(pc);
    }
  }

  bool _send(Map<String, dynamic> payload) {
    return WebSocketService.instance.send(payload);
  }

  String _newCallId() {
    final r = Random();
    return 'g-${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
  }

  void _emit(GroupCallSnapshot next) {
    final wasActive = _snapshot.isActive;
    final prevPhase = _snapshot.phase;
    _snapshot = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
    if (next.phase == GroupCallPhase.connecting ||
        next.phase == GroupCallPhase.connected) {
      if (prevPhase != GroupCallPhase.connecting &&
          prevPhase != GroupCallPhase.connected) {
        unawaited(_ensureKeepAliveForMedia());
      }
    }
    if (!next.isActive && wasActive) {
      _speakerOnPreferred = null;
      if (_keepAliveHeld) {
        unawaited(_releaseKeepAlive());
      }
    }
  }

  Future<void> _ensureKeepAliveForMedia() async {
    if (_keepAliveHeld) return;
    _keepAliveHeld = true;
    await CallKeepAlive.acquire(
      owner: _keepAliveOwner,
      isVideo: _snapshot.isCameraEnabled,
    );
  }

  Future<void> _releaseKeepAlive() async {
    if (!_keepAliveHeld) return;
    _keepAliveHeld = false;
    await CallKeepAlive.release(owner: _keepAliveOwner);
  }

  void _emitFailed(String message) {
    _emit(
      GroupCallSnapshot(
        phase: GroupCallPhase.failed,
        transport: _snapshot.transport,
        mediaType: _snapshot.mediaType,
        callId: _snapshot.callId,
        chatId: _snapshot.chatId,
        chatName: _snapshot.chatName,
        statusMessage: message,
        isMuted: _snapshot.isMuted,
        isCameraEnabled: _snapshot.isCameraEnabled,
        isSpeakerOn: _snapshot.isSpeakerOn,
        webAudioBlocked: _snapshot.webAudioBlocked,
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
    final token = _captureSetupToken();
    if (token == null) return;
    _outgoingTimer = Timer(const Duration(seconds: 45), () {
      if (!_isSetupCurrent(token) ||
          _snapshot.phase != GroupCallPhase.outgoing) {
        return;
      }
      if (_snapshot.transport == GroupCallTransport.livekit &&
          _pendingLiveKitCall != null) {
        _pendingLiveKitCall = null;
        _callEpoch.invalidate();
        _emitFailed('Нет ответа от сервера');
        return;
      }
      unawaited(leave(statusMessage: 'Нет ответа от сервера'));
    });
  }

  void _cancelOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = null;
  }

  void _startJoinAckTimeout() {
    _joinAckTimer?.cancel();
    final token = _captureSetupToken();
    if (token == null) return;
    _joinAckTimer = Timer(const Duration(seconds: 35), () {
      if (!_isSetupCurrent(token) ||
          _snapshot.phase != GroupCallPhase.connecting) {
        return;
      }
      unawaited(leave(statusMessage: 'Нет ответа от сервера'));
    });
  }

  void _cancelJoinAckTimeout() {
    _joinAckTimer?.cancel();
    _joinAckTimer = null;
  }

  void _startIncomingTimeout({DateTime? expiresAt}) {
    _incomingTimer?.cancel();
    final token = _captureSetupToken();
    if (token == null) return;
    var timeout = const Duration(seconds: 80);
    if (expiresAt != null) {
      final remaining =
          expiresAt.difference(DateTime.now()) + const Duration(seconds: 5);
      timeout = Duration(
        milliseconds: remaining.inMilliseconds.clamp(1000, 80000).toInt(),
      );
    }
    _incomingTimer = Timer(timeout, () {
      if (!_isSetupCurrent(token) ||
          _snapshot.phase != GroupCallPhase.incoming) {
        return;
      }
      unawaited(rejectIncoming(reason: 'ringing_timeout'));
    });
  }

  void _cancelIncomingTimeout() {
    _incomingTimer?.cancel();
    _incomingTimer = null;
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
      case 'call_ended':
      case 'call_expired':
        return 'Звонок уже завершён';
      case 'room_create_failed':
      case 'livekit_unavailable':
        return 'Видеосервер временно недоступен';
      default:
        return 'Не удалось выполнить групповой звонок';
    }
  }
}

class _PendingLiveKitCall {
  final String chatId;
  final String chatName;
  final GroupCallMediaType mediaType;
  final bool enableCamera;

  const _PendingLiveKitCall({
    required this.chatId,
    required this.chatName,
    required this.mediaType,
    required this.enableCamera,
  });
}

class _StaleGroupCallSetup implements Exception {
  const _StaleGroupCallSetup();
}
