import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

const String _installationIdStorageKey = 'push_installation_id_v1';
final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

String generateInstallationId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

abstract class InstallationIdStore {
  Future<String?> read();
  Future<void> write(String value);
}

class PlatformInstallationIdStore implements InstallationIdStore {
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  @override
  Future<String?> read() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_installationIdStorageKey);
    }
    return _secure.read(key: _installationIdStorageKey);
  }

  @override
  Future<void> write(String value) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_installationIdStorageKey, value);
      return;
    }
    await _secure.write(key: _installationIdStorageKey, value: value);
  }
}

class InstallationIdentity {
  final InstallationIdStore store;
  final String Function() createId;

  String? _cached;
  Future<String>? _inFlight;

  InstallationIdentity({
    InstallationIdStore? store,
    String Function()? createId,
  }) : store = store ?? PlatformInstallationIdStore(),
       createId = createId ?? generateInstallationId;

  Future<String> getOrCreate() {
    final cached = _cached;
    if (cached != null) return Future<String>.value(cached);
    final pending = _inFlight;
    if (pending != null) return pending;

    final future = _loadOrCreate();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<String> _loadOrCreate() async {
    final stored = (await store.read())?.trim().toLowerCase();
    if (stored != null && _uuidV4Pattern.hasMatch(stored)) {
      _cached = stored;
      return stored;
    }
    final created = createId().trim().toLowerCase();
    if (!_uuidV4Pattern.hasMatch(created)) {
      throw StateError('Installation ID factory returned an invalid UUID v4');
    }
    await store.write(created);
    _cached = created;
    return created;
  }
}

class PushDeviceTokens {
  final String? fcm;
  final String? apnsVoip;
  final String? apnsEnvironment;
  final bool includeFcm;
  final bool includeVoip;

  const PushDeviceTokens({
    this.fcm,
    this.apnsVoip,
    this.apnsEnvironment,
    this.includeFcm = false,
    this.includeVoip = false,
  });

  Map<String, dynamic> toJson() => {
    if (includeFcm) 'fcm': fcm,
    if (includeVoip) 'apnsVoip': apnsVoip,
    if (includeVoip) 'apnsEnvironment': apnsEnvironment,
  };
}

class PushDeviceTransportResponse {
  final int statusCode;
  final String body;

  const PushDeviceTransportResponse(this.statusCode, this.body);
}

abstract class PushDeviceTransport {
  Future<PushDeviceTransportResponse> upsert({
    required String authToken,
    required Map<String, dynamic> payload,
  });

  Future<PushDeviceTransportResponse> delete({
    required String authToken,
    required String installationId,
  });
}

class HttpPushDeviceTransport implements PushDeviceTransport {
  @override
  Future<PushDeviceTransportResponse> upsert({
    required String authToken,
    required Map<String, dynamic> payload,
  }) async {
    final response = await timedPut(
      Uri.parse('${ApiConfig.baseUrl}/auth/push-devices/current'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(payload),
    );
    return PushDeviceTransportResponse(response.statusCode, response.body);
  }

  @override
  Future<PushDeviceTransportResponse> delete({
    required String authToken,
    required String installationId,
  }) async {
    final response = await timedDelete(
      Uri.parse('${ApiConfig.baseUrl}/auth/push-devices/current'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({'installationId': installationId}),
    );
    return PushDeviceTransportResponse(response.statusCode, response.body);
  }
}

class PushDeviceSyncResult {
  final bool accepted;
  final int statusCode;
  final String? installationId;

  const PushDeviceSyncResult({
    required this.accepted,
    required this.statusCode,
    this.installationId,
  });

  factory PushDeviceSyncResult.parse(PushDeviceTransportResponse response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return PushDeviceSyncResult(
        accepted: false,
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode == 204 || response.body.trim().isEmpty) {
      return PushDeviceSyncResult(
        accepted: true,
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      final installationId = decoded is Map
          ? decoded['installationId']?.toString()
          : null;
      return PushDeviceSyncResult(
        accepted: installationId != null && installationId.isNotEmpty,
        statusCode: response.statusCode,
        installationId: installationId,
      );
    } catch (_) {
      return PushDeviceSyncResult(
        accepted: false,
        statusCode: response.statusCode,
      );
    }
  }
}

String pushPlatformName(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'unknown';
  }
}

class PushDeviceSyncService {
  static final PushDeviceSyncService instance = PushDeviceSyncService();

  final InstallationIdentity identity;
  final PushDeviceTransport transport;
  final Future<String?> Function() authTokenProvider;
  final Future<String> Function() appVersionProvider;
  final String Function() platformProvider;

  Future<void> _operationTail = Future<void>.value();
  String? _deregisteredAuthToken;
  String? _knownVoipToken;
  String? _knownVoipEnvironment;

  PushDeviceSyncService({
    InstallationIdentity? identity,
    PushDeviceTransport? transport,
    Future<String?> Function()? authTokenProvider,
    Future<String> Function()? appVersionProvider,
    String Function()? platformProvider,
  }) : identity = identity ?? InstallationIdentity(),
       transport = transport ?? HttpPushDeviceTransport(),
       authTokenProvider = authTokenProvider ?? StorageService.getToken,
       appVersionProvider = appVersionProvider ?? _defaultAppVersion,
       platformProvider =
           platformProvider ??
           (() => kIsWeb ? 'web' : pushPlatformName(defaultTargetPlatform));

  static Future<String> _defaultAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    return build.isEmpty ? info.version : '${info.version}+$build';
  }

  Future<PushDeviceSyncResult?> syncNormalToken(String? fcmToken) {
    final normalized = fcmToken?.trim();
    if (normalized == null || normalized.isEmpty) {
      return Future<PushDeviceSyncResult?>.value(null);
    }
    return syncTokens(PushDeviceTokens(fcm: normalized, includeFcm: true));
  }

  Future<PushDeviceSyncResult?> syncVoipToken(
    String? token,
    String? environment,
  ) {
    final normalizedToken = token?.trim();
    final normalizedEnvironment = environment?.trim().toLowerCase();
    if (normalizedToken != null &&
        normalizedToken.isNotEmpty &&
        normalizedEnvironment != 'development' &&
        normalizedEnvironment != 'production') {
      return Future<PushDeviceSyncResult?>.error(
        ArgumentError.value(
          environment,
          'environment',
          'Invalid APNs environment',
        ),
      );
    }
    return syncTokens(
      PushDeviceTokens(
        apnsVoip: normalizedToken == null || normalizedToken.isEmpty
            ? null
            : normalizedToken,
        apnsEnvironment: normalizedToken == null || normalizedToken.isEmpty
            ? null
            : normalizedEnvironment,
        includeVoip: true,
      ),
    );
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

  Future<PushDeviceSyncResult?> syncTokens(PushDeviceTokens tokens) {
    return _enqueue(() => _syncTokens(tokens));
  }

  Future<PushDeviceSyncResult?> _syncTokens(PushDeviceTokens tokens) async {
    if (!tokens.includeFcm && !tokens.includeVoip) return null;
    if (tokens.includeVoip) {
      _knownVoipToken = tokens.apnsVoip;
      _knownVoipEnvironment = tokens.apnsEnvironment;
    }
    final authToken = await authTokenProvider();
    if (authToken == null || authToken.isEmpty) return null;
    if (_deregisteredAuthToken == authToken) return null;
    if (_deregisteredAuthToken != null) _deregisteredAuthToken = null;

    final installationId = await identity.getOrCreate();
    final payload = <String, dynamic>{
      'installationId': installationId,
      'platform': platformProvider(),
      'tokens': tokens.toJson(),
      'capabilities':
          <String, dynamic>{
              'normalPush': true,
              'callPayloadVersion': 2,
              'callReconciliation': true,
              'livekitGroupCalls': true,
              'livekitGroupProtocolVersion': 2,
            }
            ..['voipPush'] =
                _knownVoipToken != null &&
                _knownVoipToken!.isNotEmpty &&
                _knownVoipEnvironment != null,
      'appVersion': await appVersionProvider(),
    };
    final response = await transport.upsert(
      authToken: authToken,
      payload: payload,
    );
    return PushDeviceSyncResult.parse(response);
  }

  Future<bool> deregister() {
    return _enqueue(_deregister);
  }

  Future<bool> _deregister() async {
    final authToken = await authTokenProvider();
    if (authToken == null || authToken.isEmpty) return false;
    // Prevent a late token-refresh callback from re-registering this same
    // logged-out session after the DELETE has been queued.
    _deregisteredAuthToken = authToken;
    final installationId = await identity.getOrCreate();
    final response = await transport.delete(
      authToken: authToken,
      installationId: installationId,
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
