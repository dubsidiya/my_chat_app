import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

/// Глобальный WebSocket: один коннект на пользователя для списка чатов и экрана чата.
class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  WebSocketChannel? _channel;
  final StreamController<dynamic> _streamController =
      StreamController<dynamic>.broadcast();
  String? _currentToken;
  bool _connecting = false;
  bool _wasDisconnected = false;
  bool _hasConnectedOnce = false;
  bool _ready = false;
  Completer<void>? _readyCompleter;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  int _connectSeq = 0;
  static const String _reconnectedEventType = '_ws_reconnected';
  static const String _connectedEventType = '_ws_connected';

  Stream<dynamic> get stream => _streamController.stream;

  bool get isConnected => _channel != null && _ready;

  Future<String?> _fetchEphemeralWsToken(String accessToken) async {
    try {
      final response = await timedPost(
        Uri.parse('${ApiConfig.baseUrl}/auth/ws-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: '{}',
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final token = data is Map<String, dynamic>
          ? data['wsToken']?.toString()
          : null;
      if (token == null || token.isEmpty) return null;
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Подключиться, если ещё не подключены или токен изменился.
  Future<void> connectIfNeeded() async {
    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) return;
    if (_currentToken == token && _channel != null) {
      if (_ready) return;
      final pending = _readyCompleter;
      if (pending != null) {
        await pending.future.timeout(const Duration(seconds: 12));
      }
      return;
    }
    if (_connecting) {
      final pending = _readyCompleter;
      if (pending != null) {
        await pending.future.timeout(const Duration(seconds: 12));
      }
      return;
    }

    _connecting = true;
    try {
      _reconnectTimer?.cancel();
      _stopKeepAlive();
      if (_channel != null && _ready && _hasConnectedOnce) {
        _wasDisconnected = true;
      }
      _channel?.sink.close();
      _channel = null;
      _ready = false;
      _currentToken = token;
      final connectSeq = ++_connectSeq;
      final readyCompleter = Completer<void>();
      _readyCompleter = readyCompleter;

      final baseUrl = ApiConfig.baseUrl;
      final wsUrl = baseUrl.startsWith('https://')
          ? baseUrl.replaceFirst('https://', 'wss://')
          : baseUrl.replaceFirst('http://', 'ws://');

      // Web hotfix: часть браузерных/proxy окружений нестабильно обрабатывает длинный
      // custom subprotocol, из-за чего рвётся realtime и E2EE key exchange.
      // Используем эфемерный ws-token в query (не access token), TTL короткий.
      if (kIsWeb) {
        final wsToken = await _fetchEphemeralWsToken(token);
        final safeToken = wsToken != null && wsToken.isNotEmpty
            ? wsToken
            : token;
        _channel = WebSocketChannel.connect(
          Uri.parse('$wsUrl?token=$safeToken'),
        );
      } else {
        _channel = IOWebSocketChannel.connect(
          Uri.parse(wsUrl),
          headers: {'Authorization': 'Bearer $token'},
        );
      }

      void onDisconnect(
        WebSocketChannel disconnectedChannel,
        int disconnectedSeq,
      ) {
        if (_channel != disconnectedChannel || disconnectedSeq != _connectSeq) {
          return;
        }
        final hadChannel = _channel == disconnectedChannel;
        _channel = null;
        if (hadChannel) {
          _ready = false;
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(
              StateError('WebSocket disconnected before ready'),
            );
          }
          _stopKeepAlive();
          _wasDisconnected = _hasConnectedOnce;
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 2), () {
            connectIfNeeded();
          });
        }
      }

      final activeChannel = _channel!;
      activeChannel.stream.listen(
        (data) {
          try {
            final decoded = data is String ? jsonDecode(data) : data;
            var isReconnect = false;
            if (decoded is Map && decoded['type'] == 'ws_ready') {
              _ready = true;
              isReconnect = _wasDisconnected && _hasConnectedOnce;
              _hasConnectedOnce = true;
              _wasDisconnected = false;
              _startKeepAlive();
              if (!readyCompleter.isCompleted) {
                readyCompleter.complete();
              }
            }
            if (decoded is Map && decoded['type'] == 'ws_ready') {
              _streamController.add(<String, dynamic>{
                ...Map<String, dynamic>.from(decoded),
                'type': isReconnect
                    ? _reconnectedEventType
                    : _connectedEventType,
              });
            } else {
              _streamController.add(decoded);
            }
          } catch (e) {
            if (kDebugMode) print('WebSocketService decode error: $e');
          }
        },
        onError: (error) {
          if (kDebugMode) print('WebSocketService error: $error');
          onDisconnect(activeChannel, connectSeq);
        },
        onDone: () {
          if (kDebugMode) print('WebSocketService connection closed');
          onDisconnect(activeChannel, connectSeq);
        },
        cancelOnError: false,
      );
      await readyCompleter.future.timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) print('WebSocketService connect error: $e');
      _channel?.sink.close();
      _channel = null;
      _ready = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        connectIfNeeded();
      });
    } finally {
      _connecting = false;
    }
  }

  bool send(Map<String, dynamic> payload) {
    if (_channel == null || !_ready) return false;
    try {
      _channel!.sink.add(jsonEncode(payload));
      return true;
    } catch (e) {
      if (kDebugMode) print('WebSocketService send error: $e');
      return false;
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _stopKeepAlive();
    _channel?.sink.close();
    _channel = null;
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(StateError('WebSocket disconnected'));
    }
    _readyCompleter = null;
    _ready = false;
    _wasDisconnected = false;
    _hasConnectedOnce = false;
    _currentToken = null;
  }

  void _startKeepAlive() {
    if (kIsWeb) return;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_channel == null || !_ready) return;
      send(<String, dynamic>{'type': 'ws_ping'});
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }
}
