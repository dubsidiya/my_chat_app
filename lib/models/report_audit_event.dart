class ReportAuditEvent {
  final int id;
  final int? userId;
  final String eventType;
  final String? userEmail;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  ReportAuditEvent({
    required this.id,
    this.userId,
    required this.eventType,
    this.userEmail,
    this.payload,
    required this.createdAt,
  });

  factory ReportAuditEvent.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    Map<String, dynamic>? payload;
    if (payloadRaw is Map) {
      payload = payloadRaw.map((k, v) => MapEntry(k.toString(), v));
    }
    return ReportAuditEvent(
      id: json['id'] is int ? json['id'] as int : int.parse(json['id'].toString()),
      userId: json['user_id'] == null ? null : int.tryParse(json['user_id'].toString()),
      eventType: (json['event_type'] ?? '').toString(),
      userEmail: json['user_email']?.toString(),
      payload: payload,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
