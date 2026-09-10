import '../utils/date_parse.dart';

class ReportAuditEvent {
  final int id;
  final int? userId;
  final String eventType;
  final String? userEmail;
  final Map<String, dynamic>? payload;

  /// Момент события (UTC), разобранный через [parseServerInstant].
  /// Если метка отсутствует/не парсится — epoch(0) и [hasCreatedAt] == false;
  /// UI показывает «время неизвестно» вместо 01.01.1970 (L23).
  ///
  /// Поле оставлено non-nullable намеренно: `ReportAuditEvent.createdAt`
  /// напрямую (без null-guard) используется в out-of-scope
  /// `nagavisor_screen.dart`. Признак «нет времени» вынесен в [hasCreatedAt],
  /// чтобы не ломать этот экран и не выходить за рамки разрешённых файлов.
  final DateTime createdAt;
  final bool hasCreatedAt;

  ReportAuditEvent({
    required this.id,
    this.userId,
    required this.eventType,
    this.userEmail,
    this.payload,
    required this.createdAt,
    this.hasCreatedAt = true,
  });

  static DateTime? _parseCreatedAt(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    try {
      return parseServerInstant(s);
    } catch (_) {
      return null;
    }
  }

  factory ReportAuditEvent.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    Map<String, dynamic>? payload;
    if (payloadRaw is Map) {
      payload = payloadRaw.map((k, v) => MapEntry(k.toString(), v));
    }
    final parsedCreatedAt = _parseCreatedAt(json['created_at']);
    return ReportAuditEvent(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      userId: json['user_id'] == null ? null : int.tryParse(json['user_id'].toString()),
      eventType: (json['event_type'] ?? '').toString(),
      userEmail: json['user_email']?.toString(),
      payload: payload,
      createdAt: parsedCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      hasCreatedAt: parsedCreatedAt != null,
    );
  }
}
