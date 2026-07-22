import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/services/push_device_service.dart';

const _installationId = '123e4567-e89b-42d3-a456-426614174000';

class _MemoryInstallationIdStore implements InstallationIdStore {
  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
    writes++;
  }
}

class _FakeTransport implements PushDeviceTransport {
  String? upsertAuthToken;
  Map<String, dynamic>? upsertPayload;
  String? deletedInstallationId;
  int upsertCalls = 0;

  @override
  Future<PushDeviceTransportResponse> upsert({
    required String authToken,
    required Map<String, dynamic> payload,
  }) async {
    upsertCalls++;
    upsertAuthToken = authToken;
    upsertPayload = payload;
    return const PushDeviceTransportResponse(
      200,
      '{"installationId":"123e4567-e89b-42d3-a456-426614174000"}',
    );
  }

  @override
  Future<PushDeviceTransportResponse> delete({
    required String authToken,
    required String installationId,
  }) async {
    deletedInstallationId = installationId;
    return const PushDeviceTransportResponse(204, '');
  }
}

void main() {
  test('installation UUID is stable across service instances', () async {
    final store = _MemoryInstallationIdStore();
    var generated = 0;
    String createId() {
      generated++;
      return _installationId;
    }

    final first = InstallationIdentity(store: store, createId: createId);
    expect(await first.getOrCreate(), _installationId);
    expect(await first.getOrCreate(), _installationId);
    expect(generated, 1);
    expect(store.writes, 1);

    final afterRestart = InstallationIdentity(store: store, createId: createId);
    expect(await afterRestart.getOrCreate(), _installationId);
    expect(generated, 1);
    expect(store.writes, 1);
  });

  test('generated installation identity is UUID v4', () {
    expect(
      generateInstallationId(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test(
    'device sync builds future-compatible payload and parses response',
    () async {
      final store = _MemoryInstallationIdStore()..value = _installationId;
      final transport = _FakeTransport();
      final service = PushDeviceSyncService(
        identity: InstallationIdentity(store: store),
        transport: transport,
        authTokenProvider: () async => 'jwt',
        appVersionProvider: () async => '1.0.0+4',
        platformProvider: () => 'ios',
      );

      final result = await service.syncNormalToken(' normal-fcm-token ');

      expect(result?.accepted, isTrue);
      expect(result?.installationId, _installationId);
      expect(transport.upsertAuthToken, 'jwt');
      expect(transport.upsertPayload?['installationId'], _installationId);
      expect(transport.upsertPayload?['platform'], 'ios');
      expect(
        (transport.upsertPayload?['tokens'] as Map)['fcm'],
        'normal-fcm-token',
      );
      expect(
        (transport.upsertPayload?['capabilities'] as Map)['voipPush'],
        isFalse,
      );
      expect(
        (transport.upsertPayload?['capabilities']
            as Map)['livekitGroupProtocolVersion'],
        2,
      );
      expect(transport.upsertPayload?['appVersion'], '1.0.0+4');

      expect(await service.deregister(), isTrue);
      expect(transport.deletedInstallationId, _installationId);
    },
  );

  test('sync response rejects malformed success body', () {
    final malformed = PushDeviceSyncResult.parse(
      const PushDeviceTransportResponse(200, '{"ok":true}'),
    );
    expect(malformed.accepted, isFalse);
    expect(malformed.statusCode, 200);

    final unavailable = PushDeviceSyncResult.parse(
      const PushDeviceTransportResponse(503, '{"message":"later"}'),
    );
    expect(unavailable.accepted, isFalse);
    expect(unavailable.statusCode, 503);
  });

  test(
    'VoIP token sync carries environment, capability and invalidation',
    () async {
      final store = _MemoryInstallationIdStore()..value = _installationId;
      final transport = _FakeTransport();
      final service = PushDeviceSyncService(
        identity: InstallationIdentity(store: store),
        transport: transport,
        authTokenProvider: () async => 'jwt',
        appVersionProvider: () async => '1.0.0+4',
        platformProvider: () => 'ios',
      );

      await service.syncVoipToken(' voip-token ', 'development');
      expect(
        (transport.upsertPayload?['tokens'] as Map)['apnsVoip'],
        'voip-token',
      );
      expect(
        (transport.upsertPayload?['tokens'] as Map)['apnsEnvironment'],
        'development',
      );
      expect(
        (transport.upsertPayload?['capabilities'] as Map)['voipPush'],
        isTrue,
      );

      await service.syncVoipToken(null, null);
      expect(
        (transport.upsertPayload?['tokens'] as Map).containsKey('apnsVoip'),
        isTrue,
      );
      expect((transport.upsertPayload?['tokens'] as Map)['apnsVoip'], isNull);
      expect(
        (transport.upsertPayload?['capabilities'] as Map)['voipPush'],
        isFalse,
      );
    },
  );

  test(
    'logout is ordered after sync and blocks late old-session refresh',
    () async {
      final store = _MemoryInstallationIdStore()..value = _installationId;
      final transport = _FakeTransport();
      var authToken = 'old-jwt';
      final service = PushDeviceSyncService(
        identity: InstallationIdentity(store: store),
        transport: transport,
        authTokenProvider: () async => authToken,
        appVersionProvider: () async => '1.0.0+4',
        platformProvider: () => 'android',
      );

      final firstSync = service.syncNormalToken('normal-fcm-token');
      final deregister = service.deregister();
      expect((await firstSync)?.accepted, isTrue);
      expect(await deregister, isTrue);

      expect(await service.syncNormalToken('late-refresh-token'), isNull);
      expect(transport.upsertCalls, 1);

      authToken = 'new-account-jwt';
      expect(
        (await service.syncNormalToken('new-account-fcm-token'))?.accepted,
        isTrue,
      );
      expect(transport.upsertCalls, 2);
    },
  );
}
