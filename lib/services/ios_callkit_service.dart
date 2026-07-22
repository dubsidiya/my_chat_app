import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'group_voice_call_service.dart';
import 'push_device_service.dart';
import 'storage_service.dart';
import 'voice_call_service.dart';
import 'websocket_service.dart';

const String _iosCallKitMethodChannel = 'reollity/ios_callkit';
const String _iosCallKitEventChannel = 'reollity/ios_callkit_events';

enum IOSCallKind { direct, liveKitGroup, legacyGroup }

class IOSCallKitCall {
  final String callId;
  final String callUuid;
  final String chatId;
  final String fromUserId;
  final String fromLabel;
  final String chatName;
  final IOSCallKind kind;
  final bool hasVideo;
  final DateTime expiresAt;

  const IOSCallKitCall({
    required this.callId,
    required this.callUuid,
    required this.chatId,
    required this.fromUserId,
    required this.fromLabel,
    required this.chatName,
    required this.kind,
    required this.hasVideo,
    required this.expiresAt,
  });

  bool get isGroup => kind != IOSCallKind.direct;

  factory IOSCallKitCall.fromMap(Map<dynamic, dynamic> map) {
    String value(String key) => map[key]?.toString().trim() ?? '';
    final provider = value('provider').toLowerCase();
    final isGroup = map['isGroup'] == true || value('isGroup') == '1';
    final kind = !isGroup
        ? IOSCallKind.direct
        : provider == 'livekit'
        ? IOSCallKind.liveKitGroup
        : IOSCallKind.legacyGroup;
    final expiresAt =
        DateTime.tryParse(value('expiresAt'))?.toUtc() ??
        DateTime.now().toUtc().add(const Duration(seconds: 75));
    return IOSCallKitCall(
      callId: value('callId'),
      callUuid: value('callUuid').toLowerCase(),
      chatId: value('chatId'),
      fromUserId: value('fromUserId'),
      fromLabel: value('fromLabel'),
      chatName: value('chatName'),
      kind: kind,
      hasVideo: value('mediaType').toLowerCase() == 'video',
      expiresAt: expiresAt,
    );
  }

  bool get isValid =>
      callId.isNotEmpty &&
      callUuid.isNotEmpty &&
      chatId.isNotEmpty &&
      expiresAt.isAfter(
        DateTime.now().toUtc().subtract(const Duration(seconds: 2)),
      );
}

class IOSCallStatus {
  final bool? active;
  final String state;
  final String? callId;
  final String? callUuid;
  final String? role;
  final String? participantState;

  const IOSCallStatus({
    required this.active,
    required this.state,
    this.callId,
    this.callUuid,
    this.role,
    this.participantState,
  });

  factory IOSCallStatus.fromMap(Map<dynamic, dynamic> map) {
    final rawActive = map['active'];
    return IOSCallStatus(
      active: rawActive is bool ? rawActive : null,
      state: (map['state'] ?? map['status'] ?? 'unknown').toString(),
      callId: (map['call_id'] ?? map['callId'])?.toString(),
      callUuid: (map['callkit_uuid'] ?? map['callKitUuid'])?.toString(),
      role: map['role']?.toString(),
      participantState: (map['participant_state'] ?? map['participantState'])
          ?.toString(),
    );
  }

  bool permitsAnswer(IOSCallKitCall call) {
    if (active != true || callId != call.callId) return false;
    if (callUuid != null &&
        callUuid!.isNotEmpty &&
        callUuid!.toLowerCase() != call.callUuid) {
      return false;
    }
    if (call.kind == IOSCallKind.direct) {
      return role == 'callee' && state == 'ringing';
    }
    return role == 'participant' &&
        (participantState == null || participantState == 'invited');
  }

  String denialEndReason(IOSCallKitCall call) {
    if (active == true &&
        callId == call.callId &&
        (state == 'accepted' ||
            participantState == 'joined' ||
            participantState == 'disconnected')) {
      return 'answeredElsewhere';
    }
    return 'unanswered';
  }
}

abstract class IOSCallKitPlatform {
  Stream<Map<String, dynamic>> get events;

  Future<Map<String, dynamic>> drain();
  Future<Map<String, dynamic>> getRegistration();
  Future<bool> completeAnswer(String callUuid, bool success);
  Future<bool> reportConnected(String callUuid);
  Future<bool> reportEnd(String callUuid, String reason);
  Future<bool> syncMute(String callUuid, bool muted);
}

class MethodChannelIOSCallKitPlatform implements IOSCallKitPlatform {
  static const MethodChannel _methods = MethodChannel(_iosCallKitMethodChannel);
  static const EventChannel _eventChannel = EventChannel(
    _iosCallKitEventChannel,
  );

  @override
  Stream<Map<String, dynamic>> get events => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  @override
  Future<Map<String, dynamic>> drain() async {
    final value = await _methods.invokeMapMethod<String, dynamic>('drain');
    return value ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> getRegistration() async {
    final value = await _methods.invokeMapMethod<String, dynamic>(
      'getRegistration',
    );
    return value ?? <String, dynamic>{};
  }

  @override
  Future<bool> completeAnswer(String callUuid, bool success) async =>
      await _methods.invokeMethod<bool>('completeAnswer', {
        'callUuid': callUuid,
        'success': success,
      }) ??
      false;

  @override
  Future<bool> reportConnected(String callUuid) async =>
      await _methods.invokeMethod<bool>('reportConnected', {
        'callUuid': callUuid,
      }) ??
      false;

  @override
  Future<bool> reportEnd(String callUuid, String reason) async =>
      await _methods.invokeMethod<bool>('reportEnd', {
        'callUuid': callUuid,
        'reason': reason,
      }) ??
      false;

  @override
  Future<bool> syncMute(String callUuid, bool muted) async =>
      await _methods.invokeMethod<bool>('syncMute', {
        'callUuid': callUuid,
        'muted': muted,
      }) ??
      false;
}

abstract class IOSCallStatusClient {
  Future<IOSCallStatus> fetch(String callId);
}

class HttpIOSCallStatusClient implements IOSCallStatusClient {
  @override
  Future<IOSCallStatus> fetch(String callId) async {
    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) {
      return const IOSCallStatus(active: null, state: 'unknown');
    }
    try {
      final response = await timedGet(
        Uri.parse(
          '${ApiConfig.baseUrl}/calls/status',
        ).replace(queryParameters: {'call_id': callId}),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode != 200) {
        return const IOSCallStatus(active: null, state: 'unknown');
      }
      final body = jsonDecode(response.body);
      return body is Map
          ? IOSCallStatus.fromMap(body)
          : const IOSCallStatus(active: null, state: 'unknown');
    } catch (_) {
      return const IOSCallStatus(active: null, state: 'unknown');
    }
  }
}

abstract class IOSCallActionHandler {
  Future<void> applyIncoming(IOSCallKitCall call);
  Future<bool> answer(IOSCallKitCall call);
  Future<void> end(IOSCallKitCall call, String reason);
  Future<void> setMuted(IOSCallKitCall call, bool muted);
}

class DefaultIOSCallActionHandler implements IOSCallActionHandler {
  @override
  Future<void> applyIncoming(IOSCallKitCall call) async {
    if (call.isGroup) {
      GroupVoiceCallService.instance.applyIncomingFromPush(
        callId: call.callId,
        chatId: call.chatId,
        chatName: call.chatName,
        fromUserId: call.fromUserId,
        fromLabel: call.fromLabel,
        expiresAt: call.expiresAt,
        transport: call.kind == IOSCallKind.liveKitGroup
            ? GroupCallTransport.livekit
            : GroupCallTransport.mesh,
        mediaType: call.hasVideo
            ? GroupCallMediaType.video
            : GroupCallMediaType.audio,
      );
      return;
    }
    VoiceCallService.instance.applyIncomingFromPush(
      callId: call.callId,
      chatId: call.chatId,
      peerUserId: call.fromUserId,
      peerLabel: call.fromLabel,
      mediaType: call.hasVideo ? CallMediaType.video : CallMediaType.audio,
      expiresAt: call.expiresAt,
    );
  }

  @override
  Future<bool> answer(IOSCallKitCall call) {
    if (call.isGroup) {
      return GroupVoiceCallService.instance.acceptIncomingFromSystem();
    }
    return VoiceCallService.instance.acceptIncomingFromSystem();
  }

  @override
  Future<void> end(IOSCallKitCall call, String reason) async {
    if (call.isGroup) {
      final snapshot = GroupVoiceCallService.instance.snapshot;
      if (snapshot.callId != call.callId) return;
      if (snapshot.phase == GroupCallPhase.incoming) {
        await GroupVoiceCallService.instance.rejectIncoming(
          reason: reason == 'localEnded' ? 'declined' : reason,
        );
      } else {
        await GroupVoiceCallService.instance.leave();
      }
      return;
    }
    final snapshot = VoiceCallService.instance.snapshot;
    if (snapshot.callId != call.callId) return;
    if (snapshot.phase == VoiceCallPhase.incoming) {
      await VoiceCallService.instance.rejectIncoming(
        reason: reason == 'localEnded' ? 'declined' : reason,
      );
    } else {
      await VoiceCallService.instance.hangUp();
    }
  }

  @override
  Future<void> setMuted(IOSCallKitCall call, bool muted) {
    return call.isGroup
        ? GroupVoiceCallService.instance.setMuted(muted)
        : VoiceCallService.instance.setMuted(muted);
  }
}

/// Orders native events, deduplicates cold-start replay and reconciles server
/// authority before any CallKit answer starts media.
class IOSCallKitService {
  static final IOSCallKitService instance = IOSCallKitService();

  final IOSCallKitPlatform platform;
  final IOSCallStatusClient statusClient;
  final IOSCallActionHandler actionHandler;
  final bool forceSupported;
  final bool observeCallServices;

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<VoiceCallSnapshot>? _voiceSubscription;
  StreamSubscription<GroupCallSnapshot>? _groupSubscription;
  Future<void> _operationTail = Future<void>.value();
  final Set<String> _seenEventIds = <String>{};
  final List<String> _eventIdOrder = <String>[];
  final Map<String, IOSCallKitCall> _reportedByCallId = {};
  final Set<String> _answering = <String>{};
  final Set<String> _connectedReported = <String>{};
  final Map<String, bool> _lastSyncedMute = {};
  final List<Map<String, dynamic>> _initialEventBuffer = [];
  bool _initialized = false;
  bool _bootstrapping = false;
  String? _voipToken;
  String? _voipEnvironment;
  String? _lastVoiceCallId;
  String? _lastGroupCallId;

  IOSCallKitService({
    IOSCallKitPlatform? platform,
    IOSCallStatusClient? statusClient,
    IOSCallActionHandler? actionHandler,
    this.forceSupported = false,
    this.observeCallServices = true,
  }) : platform = platform ?? MethodChannelIOSCallKitPlatform(),
       statusClient = statusClient ?? HttpIOSCallStatusClient(),
       actionHandler = actionHandler ?? DefaultIOSCallActionHandler();

  bool get isSupported =>
      forceSupported ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  String? get currentVoipToken => _voipToken;
  String? get currentVoipEnvironment => _voipEnvironment;

  bool ownsIncomingUI(String? callId) =>
      callId != null && _reportedByCallId.containsKey(callId);

  Future<void> initialize() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    _bootstrapping = true;
    // Subscribe before invoking drain so events emitted during engine attach
    // cannot overtake persisted cold-start events.
    _eventSubscription = platform.events.listen((event) {
      if (_bootstrapping) {
        _initialEventBuffer.add(event);
      } else {
        unawaited(_enqueue(() => _handleEvent(event)));
      }
    }, onError: (_) {});
    if (observeCallServices) {
      _voiceSubscription = VoiceCallService.instance.stateStream.listen(
        (snapshot) => _enqueue(() => _observeVoice(snapshot)),
      );
      _groupSubscription = GroupVoiceCallService.instance.stateStream.listen(
        (snapshot) => _enqueue(() => _observeGroup(snapshot)),
      );
    }
    try {
      final drained = await platform.drain();
      await _applyRegistration(
        drained['registration'] is Map
            ? Map<String, dynamic>.from(drained['registration'] as Map)
            : const <String, dynamic>{},
      );
      unawaited(syncVoipRegistration());
      final calls = drained['calls'];
      if (calls is List) {
        for (final value in calls) {
          if (value is! Map) continue;
          final callMap = value['call'];
          if (callMap is! Map) continue;
          final call = IOSCallKitCall.fromMap(callMap);
          if (!call.isValid) continue;
          await _registerIncoming(call);
          if (value['state']?.toString() == 'answerRequested') {
            await _handleAnswer(call);
          }
        }
      }
      final events = drained['events'];
      if (events is List) {
        for (final event in events) {
          if (event is Map) {
            await _handleEvent(Map<String, dynamic>.from(event));
          }
        }
      }
      for (final event in List<Map<String, dynamic>>.from(
        _initialEventBuffer,
      )) {
        await _handleEvent(event);
      }
      _initialEventBuffer.clear();
      _bootstrapping = false;
    } on MissingPluginException {
      _initialized = false;
      _bootstrapping = false;
    } catch (error) {
      _bootstrapping = false;
      if (kDebugMode) {
        print('IOSCallKitService initialization failed: $error');
      }
    }
  }

  Future<void> syncVoipRegistration() async {
    if (!isSupported) return;
    if (_voipEnvironment == null) {
      try {
        await _applyRegistration(await platform.getRegistration());
      } catch (_) {
        return;
      }
    }
    try {
      await PushDeviceSyncService.instance.syncVoipToken(
        _voipToken,
        _voipToken == null ? null : _voipEnvironment,
      );
    } catch (_) {
      if (kDebugMode) {
        print('IOSCallKitService: VoIP device sync failed');
      }
    }
  }

  /// Normal APNs/FCM reconciliation is allowed to close CallKit, but VoIP push
  /// is reserved strictly for new invitations.
  Future<void> handleReconciliationPush(Map<String, dynamic> data) async {
    if (!isSupported) return;
    final callId =
        data['callId']?.toString() ?? data['call_id']?.toString() ?? '';
    if (callId.isEmpty) return;
    final dm = VoiceCallService.instance.snapshot;
    final group = GroupVoiceCallService.instance.snapshot;
    final winningLocally =
        (dm.callId == callId &&
            (dm.phase == VoiceCallPhase.connecting ||
                dm.phase == VoiceCallPhase.connected)) ||
        (group.callId == callId &&
            (group.phase == GroupCallPhase.connecting ||
                group.phase == GroupCallPhase.connected ||
                group.phase == GroupCallPhase.reconnecting));
    if (winningLocally) return;

    final known = _reportedByCallId[callId];
    final callUuid =
        known?.callUuid ??
        data['callKitUuid']?.toString() ??
        data['callkit_uuid']?.toString();
    if (callUuid == null || callUuid.isEmpty) return;
    final reason = data['reason']?.toString() == 'answered_elsewhere'
        ? 'answeredElsewhere'
        : 'remoteEnded';
    try {
      await platform.reportEnd(callUuid, reason);
    } catch (_) {}
    if (known != null) _forget(known);
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    final eventId = event['eventId']?.toString();
    if (eventId != null && eventId.isNotEmpty) {
      if (_seenEventIds.contains(eventId)) return;
      _seenEventIds.add(eventId);
      _eventIdOrder.add(eventId);
      if (_eventIdOrder.length > 256) {
        _seenEventIds.remove(_eventIdOrder.removeAt(0));
      }
    }
    final type = event['type']?.toString();
    if (type == 'voipTokenUpdated') {
      await _applyRegistration(event);
      unawaited(syncVoipRegistration());
      return;
    }
    if (type == 'voipTokenInvalidated') {
      _voipToken = null;
      _voipEnvironment = event['environment']?.toString();
      unawaited(syncVoipRegistration());
      return;
    }
    final callMap = event['call'];
    if (callMap is! Map) return;
    final call = IOSCallKitCall.fromMap(callMap);
    if (!call.isValid && type != 'endRequested' && type != 'callEnded') {
      await platform.reportEnd(call.callUuid, 'unanswered');
      return;
    }
    switch (type) {
      case 'incomingReported':
      case 'duplicateIgnored':
        await _registerIncoming(call);
        break;
      case 'answerRequested':
        await _registerIncoming(call);
        await _handleAnswer(call);
        break;
      case 'endRequested':
      case 'providerReset':
        await actionHandler.end(
          call,
          event['reason']?.toString() ?? 'localEnded',
        );
        _forget(call);
        break;
      case 'muteRequested':
        await actionHandler.setMuted(call, event['muted'] == true);
        break;
      case 'actionTimedOut':
        await actionHandler.end(call, 'unanswered');
        _forget(call);
        break;
    }
  }

  Future<void> _applyRegistration(Map<String, dynamic> registration) async {
    final token = registration['token']?.toString().trim();
    _voipToken = token == null || token.isEmpty ? null : token;
    final environment = registration['environment']?.toString().trim();
    _voipEnvironment =
        environment == 'development' || environment == 'production'
        ? environment
        : null;
  }

  Future<void> _registerIncoming(IOSCallKitCall call) async {
    final existing = _reportedByCallId[call.callId];
    if (existing?.callUuid == call.callUuid) return;
    _reportedByCallId[call.callId] = call;
    await actionHandler.applyIncoming(call);
  }

  Future<void> _handleAnswer(IOSCallKitCall call) async {
    if (!_answering.add(call.callUuid)) return;
    try {
      await WebSocketService.instance.connectIfNeeded();
      final status = await statusClient.fetch(call.callId);
      if (!status.permitsAnswer(call)) {
        await platform.completeAnswer(call.callUuid, false);
        await platform.reportEnd(call.callUuid, status.denialEndReason(call));
        await actionHandler.end(call, status.denialEndReason(call));
        _forget(call);
        return;
      }
      final accepted = await actionHandler.answer(call);
      await platform.completeAnswer(call.callUuid, accepted);
      if (!accepted) {
        await platform.reportEnd(call.callUuid, 'answeredElsewhere');
        _forget(call);
      }
    } catch (_) {
      await platform.completeAnswer(call.callUuid, false);
      await platform.reportEnd(call.callUuid, 'failed');
      await actionHandler.end(call, 'failed');
      _forget(call);
    } finally {
      _answering.remove(call.callUuid);
    }
  }

  Future<void> _observeVoice(VoiceCallSnapshot snapshot) async {
    if (snapshot.callId != null) _lastVoiceCallId = snapshot.callId;
    final callId = snapshot.callId ?? _lastVoiceCallId;
    final call = callId == null ? null : _reportedByCallId[callId];
    if (call == null || call.isGroup) return;
    if (snapshot.phase == VoiceCallPhase.connected) {
      await _reportConnected(call);
    }
    await _syncMute(call, snapshot.isMuted);
    if (snapshot.phase == VoiceCallPhase.ended ||
        snapshot.phase == VoiceCallPhase.failed) {
      await _reportServiceEnd(
        call,
        snapshot.statusMessage?.contains('другом устройстве') == true
            ? 'answeredElsewhere'
            : snapshot.phase == VoiceCallPhase.failed
            ? 'failed'
            : snapshot.statusMessage == 'Отклонён'
            ? 'declined'
            : snapshot.statusMessage == 'Завершён'
            ? 'localEnded'
            : 'remoteEnded',
      );
    }
  }

  Future<void> _observeGroup(GroupCallSnapshot snapshot) async {
    if (snapshot.callId != null) _lastGroupCallId = snapshot.callId;
    final callId = snapshot.callId ?? _lastGroupCallId;
    final call = callId == null ? null : _reportedByCallId[callId];
    if (call == null || !call.isGroup) return;
    if (snapshot.phase == GroupCallPhase.connected) {
      await _reportConnected(call);
    }
    await _syncMute(call, snapshot.isMuted);
    if (snapshot.phase == GroupCallPhase.ended ||
        snapshot.phase == GroupCallPhase.failed) {
      await _reportServiceEnd(
        call,
        snapshot.statusMessage?.contains('другом устройстве') == true
            ? 'answeredElsewhere'
            : snapshot.phase == GroupCallPhase.failed
            ? 'failed'
            : snapshot.statusMessage == 'Отклонён'
            ? 'declined'
            : snapshot.statusMessage == 'Вы вышли'
            ? 'localEnded'
            : 'remoteEnded',
      );
    }
  }

  Future<void> _reportConnected(IOSCallKitCall call) async {
    if (!_connectedReported.add(call.callUuid)) return;
    await platform.reportConnected(call.callUuid);
  }

  Future<void> _syncMute(IOSCallKitCall call, bool muted) async {
    if (_lastSyncedMute[call.callUuid] == muted) return;
    _lastSyncedMute[call.callUuid] = muted;
    await platform.syncMute(call.callUuid, muted);
  }

  Future<void> _reportServiceEnd(IOSCallKitCall call, String reason) async {
    await platform.reportEnd(call.callUuid, reason);
    _forget(call);
  }

  void _forget(IOSCallKitCall call) {
    if (_reportedByCallId[call.callId]?.callUuid == call.callUuid) {
      _reportedByCallId.remove(call.callId);
    }
    if (_lastVoiceCallId == call.callId) _lastVoiceCallId = null;
    if (_lastGroupCallId == call.callId) _lastGroupCallId = null;
    _connectedReported.remove(call.callUuid);
    _lastSyncedMute.remove(call.callUuid);
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _voiceSubscription?.cancel();
    await _groupSubscription?.cancel();
    _eventSubscription = null;
    _voiceSubscription = null;
    _groupSubscription = null;
  }
}
