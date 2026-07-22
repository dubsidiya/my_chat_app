import 'dart:convert';

import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

class LiveKitGroupToken {
  final String serverUrl;
  final String participantToken;
  final String roomName;
  final String participantName;
  final DateTime? expiresAt;

  const LiveKitGroupToken({
    required this.serverUrl,
    required this.participantToken,
    required this.roomName,
    required this.participantName,
    this.expiresAt,
  });
}

class LiveKitGroupApiException implements Exception {
  final String code;
  final int? statusCode;

  const LiveKitGroupApiException(this.code, {this.statusCode});

  @override
  String toString() => 'LiveKitGroupApiException($code, $statusCode)';
}

abstract class LiveKitGroupTokenSource {
  Future<LiveKitGroupToken> fetchToken(String callId, {String? answerTicket});
}

class HttpLiveKitGroupTokenSource implements LiveKitGroupTokenSource {
  const HttpLiveKitGroupTokenSource();

  @override
  Future<LiveKitGroupToken> fetchToken(
    String callId, {
    String? answerTicket,
  }) async {
    final authToken = await StorageService.getToken();
    if (authToken == null || authToken.isEmpty) {
      throw const LiveKitGroupApiException('not_authenticated');
    }
    final response = await timedPost(
      Uri.parse('${ApiConfig.baseUrl}/calls/group/$callId/token'),
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      },
      body: jsonEncode({
        if (answerTicket != null && answerTicket.isNotEmpty)
          'answer_ticket': answerTicket,
      }),
      timeout: const Duration(seconds: 12),
    );
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (response.statusCode != 200) {
      throw LiveKitGroupApiException(
        body['error']?.toString() ?? 'token_request_failed',
        statusCode: response.statusCode,
      );
    }
    final serverUrl = body['server_url']?.toString() ?? '';
    final participantToken = body['participant_token']?.toString() ?? '';
    final roomName = body['room_name']?.toString() ?? '';
    if (serverUrl.isEmpty || participantToken.isEmpty || roomName.isEmpty) {
      throw const LiveKitGroupApiException('invalid_token_response');
    }
    return LiveKitGroupToken(
      serverUrl: serverUrl,
      participantToken: participantToken,
      roomName: roomName,
      participantName: body['participant_name']?.toString() ?? 'Участник',
      expiresAt: DateTime.tryParse(body['expires_at']?.toString() ?? ''),
    );
  }
}
