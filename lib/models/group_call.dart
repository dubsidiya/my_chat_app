enum GroupCallTransport { mesh, livekit }

enum GroupCallMediaType { audio, video }

enum GroupCallPhase {
  idle,
  incoming,
  outgoing,
  connecting,
  connected,
  reconnecting,
  ended,
  failed,
}

class GroupCallPeer {
  final String userId;
  final String label;
  final String state;
  final bool isLocal;
  final bool isSpeaking;
  final bool isMuted;
  final bool isCameraEnabled;
  final String connectionQuality;
  final Object? videoTrack;

  const GroupCallPeer({
    required this.userId,
    required this.label,
    required this.state,
    this.isLocal = false,
    this.isSpeaking = false,
    this.isMuted = true,
    this.isCameraEnabled = false,
    this.connectionQuality = 'unknown',
    this.videoTrack,
  });

  GroupCallPeer copyWith({
    String? label,
    String? state,
    bool? isLocal,
    bool? isSpeaking,
    bool? isMuted,
    bool? isCameraEnabled,
    String? connectionQuality,
    Object? videoTrack,
  }) {
    return GroupCallPeer(
      userId: userId,
      label: label ?? this.label,
      state: state ?? this.state,
      isLocal: isLocal ?? this.isLocal,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isMuted: isMuted ?? this.isMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      connectionQuality: connectionQuality ?? this.connectionQuality,
      videoTrack: videoTrack ?? this.videoTrack,
    );
  }
}

class GroupCallSnapshot {
  final GroupCallPhase phase;
  final GroupCallTransport transport;
  final GroupCallMediaType mediaType;
  final String? callId;
  final String? chatId;
  final String? chatName;
  final String? statusMessage;
  final String? disconnectReason;
  final bool isMuted;
  final bool isCameraEnabled;
  final bool isSpeakerOn;
  final bool isUsingFrontCamera;
  final bool webAudioBlocked;
  final DateTime? joinedAt;
  final List<GroupCallPeer> roster;

  const GroupCallSnapshot({
    this.phase = GroupCallPhase.idle,
    this.transport = GroupCallTransport.mesh,
    this.mediaType = GroupCallMediaType.audio,
    this.callId,
    this.chatId,
    this.chatName,
    this.statusMessage,
    this.disconnectReason,
    this.isMuted = false,
    this.isCameraEnabled = false,
    this.isSpeakerOn = true,
    this.isUsingFrontCamera = true,
    this.webAudioBlocked = false,
    this.joinedAt,
    this.roster = const [],
  });

  bool get isVideo => mediaType == GroupCallMediaType.video;

  bool get isActive =>
      phase == GroupCallPhase.incoming ||
      phase == GroupCallPhase.outgoing ||
      phase == GroupCallPhase.connecting ||
      phase == GroupCallPhase.connected ||
      phase == GroupCallPhase.reconnecting;

  GroupCallSnapshot copyWith({
    GroupCallPhase? phase,
    GroupCallTransport? transport,
    GroupCallMediaType? mediaType,
    String? callId,
    String? chatId,
    String? chatName,
    String? statusMessage,
    String? disconnectReason,
    bool? isMuted,
    bool? isCameraEnabled,
    bool? isSpeakerOn,
    bool? isUsingFrontCamera,
    bool? webAudioBlocked,
    DateTime? joinedAt,
    List<GroupCallPeer>? roster,
  }) {
    return GroupCallSnapshot(
      phase: phase ?? this.phase,
      transport: transport ?? this.transport,
      mediaType: mediaType ?? this.mediaType,
      callId: callId ?? this.callId,
      chatId: chatId ?? this.chatId,
      chatName: chatName ?? this.chatName,
      statusMessage: statusMessage ?? this.statusMessage,
      disconnectReason: disconnectReason ?? this.disconnectReason,
      isMuted: isMuted ?? this.isMuted,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isUsingFrontCamera: isUsingFrontCamera ?? this.isUsingFrontCamera,
      webAudioBlocked: webAudioBlocked ?? this.webAudioBlocked,
      joinedAt: joinedAt ?? this.joinedAt,
      roster: roster ?? this.roster,
    );
  }
}
