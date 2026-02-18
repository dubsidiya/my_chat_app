import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/api_config.dart';
import 'storage_service.dart';

/// Глобальный WebSocket: один коннект на пользователя для списка чатов и экрана чата.
class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  WebSocketChannel? _channel;
  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();
  String? _currentToken;
  bool _connecting = false;
  bool _wasDisconnected = false;
  static const String _reconnectedEventType = '_ws_reconnected';

  Stream<dynamic> get stream => _streamController.stream;

  bool get isConnected => _channel != null;

  /// Подключиться, если ещё не подключены или токен изменился.
  Future<void> connectIfNeeded() async {
    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) return;
    if (_currentToken == token && _channel != null) return;
    if (_connecting) return;

    _connecting = true;
    try {
      _channel?.sink.close();
      _channel = null;
      _currentToken = token;

      final baseUrl = ApiConfig.baseUrl;
      final wsUrl = baseUrl.replaceFirst(RegExp(r'^https?://'), 'wss://');

      if (kIsWeb) {
        _channel = WebSocketChannel.connect(
          Uri.parse('$wsUrl?token=$token'),
        );
      } else {
        _channel = IOWebSocketChannel.connect(
          Uri.parse(wsUrl),
          headers: {'Authorization': 'Bearer $token'},
        );
      }

      void onDisconnect() {
        final hadChannel = _channel != null;
        _channel = null;
        if (hadChannel) {
          _wasDisconnected = true;
          Future.delayed(const Duration(seconds: 2), () {
            connectIfNeeded();
          });
        }
      }

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = data is String ? jsonDecode(data) : data;
            _streamController.add(decoded);
          } catch (e) {
            if (kDebugMode) print('WebSocketService decode error: $e');
          }
        },
        onError: (error) {
          if (kDebugMode) print('WebSocketService error: $error');
          onDisconnect();
        },
        onDone: () {
          if (kDebugMode) print('WebSocketService connection closed');
          onDisconnect();
        },
        cancelOnError: false,
      );

      if (_wasDisconnected) {
        _wasDisconnected = false;
        _streamController.add(<String, dynamic>{'type': _reconnectedEventType});
      }
    } catch (e) {
      if (kDebugMode) print('WebSocketService connect error: $e');
      _channel = null;
      Future.delayed(const Duration(seconds: 3), () {
        connectIfNeeded();
      });
    } finally {
      _connecting = false;
    }
  }

  void send(Map<String, dynamic> payload) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) print('WebSocketService send error: $e');
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _currentToken = null;
  }
}
