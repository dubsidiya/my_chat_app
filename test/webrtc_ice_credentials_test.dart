import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/webrtc_ice_credentials.dart';

void main() {
  test('IceServersPayload parses HMAC expiry and freshness skew', () {
    final now = DateTime.utc(2026, 7, 22, 12);
    final payload = IceServersPayload.fromMap({
      'iceServers': [
        {
          'urls': ['turn:example:3478'],
          'username': '1:u',
          'credential': 'x',
        },
      ],
      'ttl': 3600,
      'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String(),
      'credentialType': 'hmac',
    });
    expect(payload.hasTurn, isTrue);
    expect(payload.credentialType, 'hmac');
    expect(payload.isFresh(now: now), isTrue);
    expect(
      payload.isFresh(now: now.add(const Duration(minutes: 29))),
      isFalse,
    );
  });

  test('parseSelectedIcePathMetrics prefers nominated relay pair', () {
    final metrics = parseSelectedIcePathMetrics([
      {
        'id': 'L1',
        'type': 'local-candidate',
        'values': {'candidateType': 'relay', 'protocol': 'udp'},
      },
      {
        'id': 'R1',
        'type': 'remote-candidate',
        'values': {'candidateType': 'srflx'},
      },
      {
        'id': 'P1',
        'type': 'candidate-pair',
        'values': {
          'state': 'succeeded',
          'selected': true,
          'localCandidateId': 'L1',
          'remoteCandidateId': 'R1',
          'protocol': 'udp',
        },
      },
    ]);
    expect(metrics, isNotNull);
    expect(metrics!.usingRelay, isTrue);
    expect(metrics.localCandidateType, 'relay');
    expect(metrics.remoteCandidateType, 'srflx');
    expect(metrics.protocol, 'udp');
  });

  test('disconnected grace only starts for owned active media', () {
    expect(
      shouldStartIceDisconnectedGrace(
        callActive: true,
        ownsMedia: true,
        restartPending: false,
      ),
      isTrue,
    );
    expect(
      shouldStartIceDisconnectedGrace(
        callActive: true,
        ownsMedia: true,
        restartPending: true,
      ),
      isFalse,
    );
    expect(
      iceDisconnectedGraceDuration(hasTurn: true),
      const Duration(seconds: 8),
    );
  });

  test('mergeIceServersIntoPeerConfiguration replaces iceServers only', () {
    final merged = mergeIceServersIntoPeerConfiguration(
      {
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:old'},
        ],
      },
      [
        {
          'urls': ['turn:new'],
          'username': '1:u',
          'credential': 'x',
        },
      ],
    );
    expect(merged['sdpSemantics'], 'unified-plan');
    expect((merged['iceServers'] as List).first['urls'], ['turn:new']);
  });
}
