import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/voice_call_service.dart';

void main() {
  test('call status parser keeps participant-safe control fields', () {
    final status = parseCallStatus({
      'active': true,
      'call_id': 'call-1',
      'chat_id': '7',
      'state': 'accepted',
      'role': 'callee',
      'media_type': 'video',
      'media_owner': true,
      'expires_at': '2026-07-22T00:00:00.000Z',
    });

    expect(status.available, isTrue);
    expect(status.active, isTrue);
    expect(status.callId, 'call-1');
    expect(status.role, 'callee');
    expect(status.mediaType, CallMediaType.video);
    expect(status.mediaOwner, isTrue);
    expect(status.expiresAt, DateTime.utc(2026, 7, 22));
  });

  test('authoritative inactive status clears stale ringing UI', () {
    const local = VoiceCallSnapshot(
      phase: VoiceCallPhase.incoming,
      callId: 'call-1',
      chatId: '7',
    );
    const remote = ParsedCallStatus(available: true, active: false);

    expect(
      decideCallResync(
        local: local,
        remote: remote,
        ownsMedia: false,
        mediaHealthy: false,
      ),
      CallResyncDecision.endStale,
    );
  });

  test('healthy connected media survives stale control-plane status', () {
    const local = VoiceCallSnapshot(
      phase: VoiceCallPhase.connected,
      callId: 'call-1',
      chatId: '7',
    );
    const remote = ParsedCallStatus(available: true, active: false);

    expect(
      decideCallResync(
        local: local,
        remote: remote,
        ownsMedia: true,
        mediaHealthy: true,
      ),
      CallResyncDecision.keepHealthyMedia,
    );
  });

  test('unavailable status never tears down local call', () {
    const local = VoiceCallSnapshot(
      phase: VoiceCallPhase.connected,
      callId: 'call-1',
      chatId: '7',
    );
    const remote = ParsedCallStatus(available: false, active: false);

    expect(
      decideCallResync(
        local: local,
        remote: remote,
        ownsMedia: true,
        mediaHealthy: false,
      ),
      CallResyncDecision.ignore,
    );
  });

  test('missed ringing call can converge after reconnect', () {
    const local = VoiceCallSnapshot();
    const remote = ParsedCallStatus(
      available: true,
      active: true,
      callId: 'call-2',
      chatId: '8',
      state: 'ringing',
      role: 'callee',
    );

    expect(
      decideCallResync(
        local: local,
        remote: remote,
        ownsMedia: false,
        mediaHealthy: false,
      ),
      CallResyncDecision.converge,
    );
  });
}
