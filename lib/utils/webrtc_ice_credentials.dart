/// ICE credential payload from GET /calls/ice-servers (HMAC REST or static).
class IceServersPayload {
  final List<Map<String, dynamic>> iceServers;
  final int? ttlSeconds;
  final DateTime? expiresAt;
  final String credentialType;

  const IceServersPayload({
    required this.iceServers,
    this.ttlSeconds,
    this.expiresAt,
    this.credentialType = 'none',
  });

  bool get hasTurn =>
      credentialType == 'hmac' ||
      credentialType == 'static' ||
      iceServers.any(_entryHasTurn);

  bool isFresh({
    DateTime? now,
    Duration skew = const Duration(seconds: 90),
  }) {
    final expires = expiresAt;
    if (expires == null) return true;
    return expires.isAfter((now ?? DateTime.now().toUtc()).add(skew));
  }

  factory IceServersPayload.fromMap(Map<dynamic, dynamic> map) {
    final rawServers = map['iceServers'];
    final iceServers = rawServers is List
        ? rawServers
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    final ttlRaw = map['ttl'] ?? map['ttlSeconds'];
    final ttl = ttlRaw is num
        ? ttlRaw.toInt()
        : int.tryParse(ttlRaw?.toString() ?? '');
    final expiresAt =
        DateTime.tryParse(
          (map['expiresAt'] ?? map['expires_at'])?.toString() ?? '',
        )?.toUtc();
    return IceServersPayload(
      iceServers: iceServers,
      ttlSeconds: ttl,
      expiresAt: expiresAt,
      credentialType: (map['credentialType'] ?? map['credential_type'] ?? 'none')
          .toString(),
    );
  }

  static bool _entryHasTurn(Map<String, dynamic> entry) {
    final urls = entry['urls'];
    final list = urls is List
        ? urls.map((e) => e.toString())
        : [urls?.toString() ?? ''];
    return list.any(
      (url) => url.startsWith('turn:') || url.startsWith('turns:'),
    );
  }
}

/// Selected ICE pair summary — no SDP/ICE body, only coarse type + protocol.
class IcePathMetrics {
  final String localCandidateType;
  final String remoteCandidateType;
  final String? protocol;
  final bool usingRelay;

  const IcePathMetrics({
    required this.localCandidateType,
    required this.remoteCandidateType,
    this.protocol,
    required this.usingRelay,
  });

  Map<String, Object?> toLogMap() => {
    'localCandidateType': localCandidateType,
    'remoteCandidateType': remoteCandidateType,
    if (protocol != null) 'protocol': protocol,
    'usingRelay': usingRelay,
  };
}

/// Parse flutter_webrtc getStats() maps into a single selected-pair summary.
IcePathMetrics? parseSelectedIcePathMetrics(
  Iterable<Map<dynamic, dynamic>> reports,
) {
  final byId = <String, Map<dynamic, dynamic>>{};
  for (final report in reports) {
    final id = report['id']?.toString();
    if (id != null && id.isNotEmpty) byId[id] = report;
  }

  Map<dynamic, dynamic>? selectedPair;
  for (final report in reports) {
    final type = report['type']?.toString();
    if (type != 'candidate-pair' && type != 'transport') continue;
    final values = report['values'] is Map
        ? Map<dynamic, dynamic>.from(report['values'] as Map)
        : report;
    final state = (values['state'] ?? report['state'])?.toString();
    final selected =
        values['selected'] == true ||
        report['selected'] == true ||
        values['nominated'] == true;
    if (type == 'candidate-pair' &&
        (selected || state == 'succeeded' || state == 'in-progress')) {
      selectedPair = {...report, ...values};
      if (selected || state == 'succeeded') break;
    }
  }
  if (selectedPair == null) return null;

  String candidateType(String? id) {
    if (id == null || id.isEmpty) return 'unknown';
    final report = byId[id];
    if (report == null) return 'unknown';
    final values = report['values'] is Map
        ? Map<dynamic, dynamic>.from(report['values'] as Map)
        : report;
    return (values['candidateType'] ??
            values['candidate_type'] ??
            report['candidateType'] ??
            'unknown')
        .toString();
  }

  final localId =
      (selectedPair['localCandidateId'] ?? selectedPair['localCandidateId'])
          ?.toString();
  final remoteId = selectedPair['remoteCandidateId']?.toString();
  final localType = candidateType(localId);
  final remoteType = candidateType(remoteId);
  final protocol = (selectedPair['protocol'] ?? selectedPair['networkType'])
      ?.toString();
  final usingRelay = localType == 'relay' || remoteType == 'relay';
  return IcePathMetrics(
    localCandidateType: localType,
    remoteCandidateType: remoteType,
    protocol: protocol,
    usingRelay: usingRelay,
  );
}

/// Disconnected grace: wait before treating ICE drop as failure.
bool shouldStartIceDisconnectedGrace({
  required bool callActive,
  required bool ownsMedia,
  required bool restartPending,
}) {
  return callActive && ownsMedia && !restartPending;
}

Duration iceDisconnectedGraceDuration({bool hasTurn = true}) =>
    hasTurn ? const Duration(seconds: 8) : const Duration(seconds: 5);

/// Merge freshly minted TURN REST credentials into an existing PC config.
Map<String, dynamic> mergeIceServersIntoPeerConfiguration(
  Map<String, dynamic> currentConfiguration,
  List<Map<String, dynamic>> iceServers,
) {
  return <String, dynamic>{
    ...currentConfiguration,
    'iceServers': iceServers,
  };
}
