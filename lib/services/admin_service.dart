import 'dart:convert';
import 'dart:typed_data';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';
import '../models/report_author_option.dart';
import '../models/teacher_schedule_heatmap.dart';
import '../models/teacher_schedule_overview.dart';
import '../models/teacher_placement_plan.dart';

/// Ошибка админ/бухгалтерского API с сохранённым HTTP-статусом.
/// Позволяет экранам ветвиться по коду (401/403), а не по тексту сообщения.
class AdminApiException implements Exception {
  final String message;
  final int? statusCode;
  const AdminApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

// ── Типизированный разбор бухгалтерской выгрузки (см. аудит M47) ─────────────
double _accDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _accInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

int? _accStudentId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v > 0 ? v : null;
  if (v is num) {
    final i = v.toInt();
    return i > 0 ? i : null;
  }
  final i = int.tryParse(v.toString());
  return (i != null && i > 0) ? i : null;
}

Map<String, dynamic> _accMap(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

List<dynamic> _accList(dynamic v) => v is List ? v : const [];

class AccountingExport {
  final AccountingTotals totals;
  final List<AccountingTeacherAgg> teachers;
  final Set<int> bankTransferStudentIds;
  final List<AccountingTreeTeacher> tree;

  const AccountingExport({
    required this.totals,
    required this.teachers,
    required this.bankTransferStudentIds,
    required this.tree,
  });

  factory AccountingExport.fromJson(Map<String, dynamic> json) {
    final bankIds = _accList(json['students'])
        .map(_accMap)
        .where((m) => m['payByBankTransfer'] == true)
        .map((m) => _accStudentId(m['id']))
        .whereType<int>()
        .toSet();
    return AccountingExport(
      totals: AccountingTotals.fromJson(_accMap(json['totals'])),
      teachers: _accList(json['teachers'])
          .map((e) => AccountingTeacherAgg.fromJson(_accMap(e)))
          .toList(),
      bankTransferStudentIds: bankIds,
      tree: _accList(json['tree'])
          .map((e) => AccountingTreeTeacher.fromJson(_accMap(e)))
          .toList(),
    );
  }
}

class AccountingTotals {
  final int lessonsCount;
  final double lessonsAmount;
  final double paidAmount;
  final double unpaidAmount;
  final int missedCount;
  final int makeupCount;
  final int cancelSameDayCount;
  final int cancelSameDayFreeCount;
  final int cancelSameDayPaidCount;
  final int makeupPendingCount;

  const AccountingTotals({
    required this.lessonsCount,
    required this.lessonsAmount,
    required this.paidAmount,
    required this.unpaidAmount,
    required this.missedCount,
    required this.makeupCount,
    required this.cancelSameDayCount,
    required this.cancelSameDayFreeCount,
    required this.cancelSameDayPaidCount,
    required this.makeupPendingCount,
  });

  factory AccountingTotals.fromJson(Map<String, dynamic> json) => AccountingTotals(
        lessonsCount: _accInt(json['lessonsCount']),
        lessonsAmount: _accDouble(json['lessonsAmount']),
        paidAmount: _accDouble(json['paidAmount']),
        unpaidAmount: _accDouble(json['unpaidAmount']),
        missedCount: _accInt(json['missedCount']),
        makeupCount: _accInt(json['makeupCount']),
        cancelSameDayCount: _accInt(json['cancelSameDayCount']),
        cancelSameDayFreeCount: _accInt(json['cancelSameDayFreeCount']),
        cancelSameDayPaidCount: _accInt(json['cancelSameDayPaidCount']),
        makeupPendingCount: _accInt(json['makeupPendingCount']),
      );
}

class AccountingTeacherAgg {
  final String teacherUsername;
  final int lessonsCount;
  final double amount;
  final double paidAmount;
  final double unpaidAmount;

  const AccountingTeacherAgg({
    required this.teacherUsername,
    required this.lessonsCount,
    required this.amount,
    required this.paidAmount,
    required this.unpaidAmount,
  });

  factory AccountingTeacherAgg.fromJson(Map<String, dynamic> json) =>
      AccountingTeacherAgg(
        teacherUsername: (json['teacherUsername'] ?? '').toString(),
        lessonsCount: _accInt(json['lessonsCount']),
        amount: _accDouble(json['amount']),
        paidAmount: _accDouble(json['paidAmount']),
        unpaidAmount: _accDouble(json['unpaidAmount']),
      );
}

class AccountingTreeTeacher {
  final String teacherUsername;
  final List<AccountingTreeStudent> students;

  const AccountingTreeTeacher({
    required this.teacherUsername,
    required this.students,
  });

  factory AccountingTreeTeacher.fromJson(Map<String, dynamic> json) =>
      AccountingTreeTeacher(
        teacherUsername: (json['teacherUsername'] ?? '').toString(),
        students: _accList(json['students'])
            .map((e) => AccountingTreeStudent.fromJson(_accMap(e)))
            .toList(),
      );
}

class AccountingTreeStudent {
  final int? studentId;
  final String studentName;
  final double walletDebt;
  final double walletPrepaid;
  final List<AccountingLesson> lessons;

  const AccountingTreeStudent({
    required this.studentId,
    required this.studentName,
    required this.walletDebt,
    required this.walletPrepaid,
    required this.lessons,
  });

  factory AccountingTreeStudent.fromJson(Map<String, dynamic> json) =>
      AccountingTreeStudent(
        studentId: _accStudentId(json['studentId']),
        studentName: (json['studentName'] ?? '').toString(),
        walletDebt:
            _accDouble(json['walletDebtAsOfTo'] ?? json['overallDebtAsOfTo']),
        walletPrepaid: _accDouble(
            json['walletPrepaidAsOfTo'] ?? json['overallPrepaidAsOfTo']),
        lessons: _accList(json['lessons'])
            .map((e) => AccountingLesson.fromJson(_accMap(e)))
            .toList(),
      );
}

class AccountingLesson {
  final String lessonDate;
  final String lessonTime;
  final double price;
  final double paidAmount;
  final double unpaidAmount;
  final bool isPaid;
  final bool isChargeable;
  final String status;
  final String originLessonDate;

  const AccountingLesson({
    required this.lessonDate,
    required this.lessonTime,
    required this.price,
    required this.paidAmount,
    required this.unpaidAmount,
    required this.isPaid,
    required this.isChargeable,
    required this.status,
    required this.originLessonDate,
  });

  factory AccountingLesson.fromJson(Map<String, dynamic> json) => AccountingLesson(
        lessonDate: (json['lessonDate'] ?? '').toString(),
        lessonTime: (json['lessonTime'] ?? '').toString(),
        price: _accDouble(json['price']),
        paidAmount: _accDouble(json['paidAmount']),
        unpaidAmount: _accDouble(json['unpaidAmount']),
        isPaid: json['isPaid'] == true,
        isChargeable: json['isChargeable'] == true,
        status: (json['status'] ?? 'attended').toString(),
        originLessonDate: (json['originLessonDate'] ?? '').toString(),
      );

  /// Занятие, не влияющее на долг (пропуск / бесплатная отмена в день).
  bool get isNonBillable =>
      status == 'missed' || (status == 'cancel_same_day' && !isChargeable);

  /// Занятие, формирующее долг за период (учитываемое и неоплаченное).
  bool get countsAsPeriodDebt => !isNonBillable && !isPaid;
}

class AdminService {
  final String baseUrl = ApiConfig.baseUrl;

  /// Сбросить пароль пользователя (только суперпользователь)
  Future<void> resetUserPassword(String username, String newPassword) async {
    final headers = await _getAuthHeaders();
    final response = await timedPost(
      Uri.parse('$baseUrl/admin/reset-user-password'),
      headers: headers,
      body: jsonEncode({'username': username.trim(), 'newPassword': newPassword}),
    );
    if (response.statusCode == 200) return;
    final body = _tryDecodeJson(utf8.decode(response.bodyBytes));
    throw Exception(body?['message'] ?? 'Ошибка сброса пароля (${response.statusCode})');
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    if (body.isEmpty) return null;
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.cast<String, dynamic>();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Разбирает JSON-ответ ошибки в текст сообщения, если он есть.
  String? _messageFromBody(Map<String, dynamic>? body) {
    final msg = body?['message'];
    if (msg == null) return null;
    final s = msg.toString().trim();
    return s.isEmpty ? null : s;
  }

  Future<AccountingExport> exportAccountingJson({
    required String from, // YYYY-MM-DD
    required String to, // YYYY-MM-DD
    bool bankTransferOnly = false,
  }) async {
    final headers = await _getAuthHeaders();
    final bank = bankTransferOnly ? '&bank_transfer_only=true' : '';
    final uri = Uri.parse('$baseUrl/admin/accounting/export?from=$from&to=$to&format=json$bank');
    final response = await timedGet(uri, headers: headers);

    final bodyText = utf8.decode(response.bodyBytes);
    final body = _tryDecodeJson(bodyText);

    if (response.statusCode == 200) {
      if (body == null) {
        throw const AdminApiException(
          'Сервер вернул не-JSON (возможно, 404/HTML). Проверь деплой бэкенда.',
        );
      }
      return AccountingExport.fromJson(body);
    }

    final msg = _messageFromBody(body);
    if (msg != null) {
      throw AdminApiException(msg, statusCode: response.statusCode);
    }

    // Часто это 404 от прокси/необновленного сервера, отдающий HTML
    final snippet = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = snippet.length > 180 ? '${snippet.substring(0, 180)}…' : snippet;
    throw AdminApiException(
      'Не удалось получить выгрузку. Ответ: $short',
      statusCode: response.statusCode,
    );
  }

  Future<String> exportAccountingCsv({
    required String from, // YYYY-MM-DD
    required String to, // YYYY-MM-DD
    bool bankTransferOnly = false,
  }) async {
    final headers = await _getAuthHeaders();
    final bank = bankTransferOnly ? '&bank_transfer_only=true' : '';
    final uri = Uri.parse('$baseUrl/admin/accounting/export?from=$from&to=$to&format=csv$bank');
    final response = await timedGet(uri, headers: headers);

    if (response.statusCode == 200) {
      return utf8.decode(response.bodyBytes);
    }

    final body = _tryDecodeJson(utf8.decode(response.bodyBytes));
    throw AdminApiException(
      _messageFromBody(body) ?? 'Не удалось получить CSV',
      statusCode: response.statusCode,
    );
  }

  /// Красивая выписка для бухгалтерии в формате XLSX (Excel).
  /// Возвращает байты файла; экран сам решает, сохранить или предложить браузеру.
  Future<Uint8List> exportAccountingXlsxBytes({
    required String from, // YYYY-MM-DD
    required String to, // YYYY-MM-DD
    bool bankTransferOnly = false,
  }) async {
    final headers = await _getAuthHeaders();
    final bank = bankTransferOnly ? '&bank_transfer_only=true' : '';
    final uri = Uri.parse('$baseUrl/admin/accounting/export-xlsx?from=$from&to=$to$bank');
    final response = await timedGet(uri, headers: headers);

    if (response.statusCode == 200) {
      return Uint8List.fromList(response.bodyBytes);
    }

    final body = _tryDecodeJson(utf8.decode(response.bodyBytes));
    throw AdminApiException(
      _messageFromBody(body) ?? 'Не удалось получить Excel-выгрузку',
      statusCode: response.statusCode,
    );
  }

  static String _dateToIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Преподаватели с занятиями в периоде (суперпользователь).
  Future<List<ReportAuthorOption>> getTeacherScheduleTeachers({
    required DateTime from,
    required DateTime to,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule/teachers?from=${_dateToIso(from)}&to=${_dateToIso(to)}',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 20));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return [];
      final list = decoded['teachers'];
      if (list is! List) return [];
      final out = <ReportAuthorOption>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          out.add(
            ReportAuthorOption.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        } catch (_) {}
      }
      return out;
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(
      _extractMessage(response, 'Не удалось загрузить преподавателей'),
    );
  }

  /// Теплокарта: день недели × время (суперпользователь).
  Future<TeacherScheduleHeatmap> getTeacherScheduleHeatmap({
    required DateTime from,
    required DateTime to,
    required int teacherId,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule?from=${_dateToIso(from)}&to=${_dateToIso(to)}&teacher_id=$teacherId',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 25));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return TeacherScheduleHeatmap.fromJson(decoded);
      }
      if (decoded is Map) {
        return TeacherScheduleHeatmap.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить график'));
  }

  /// Планировщик: куда поставить ребёнка по дням/времени (1–5 преподавателей, суперпользователь).
  Future<TeacherPlacementPlan> getTeacherPlacementPlan({
    required DateTime from,
    required DateTime to,
    required List<int> teacherIds,
  }) async {
    if (teacherIds.isEmpty) {
      throw Exception('Выберите хотя бы одного преподавателя');
    }
    if (teacherIds.length > 5) {
      throw Exception('Не более 5 преподавателей');
    }
    final headers = await _getAuthHeaders();
    final ids = teacherIds.join(',');
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule/placement?from=${_dateToIso(from)}&to=${_dateToIso(to)}&teacher_ids=$ids',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 40));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return TeacherPlacementPlan.fromJson(decoded);
      }
      if (decoded is Map) {
        return TeacherPlacementPlan.fromJson(decoded.cast<String, dynamic>());
      }
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить планировщик'));
  }

  /// Сводная теплокарта 1–5 преподавателей (суперпользователь).
  Future<TeacherScheduleOverview> getTeacherScheduleOverview({
    required DateTime from,
    required DateTime to,
    required List<int> teacherIds,
  }) async {
    if (teacherIds.isEmpty) {
      throw Exception('Выберите хотя бы одного преподавателя');
    }
    if (teacherIds.length > 5) {
      throw Exception('Не более 5 преподавателей');
    }
    final headers = await _getAuthHeaders();
    final ids = teacherIds.join(',');
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/teacher-schedule/overview?from=${_dateToIso(from)}&to=${_dateToIso(to)}&teacher_ids=$ids',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 35));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return TeacherScheduleOverview.fromJson(decoded);
      }
      if (decoded is Map) {
        return TeacherScheduleOverview.fromJson(decoded.cast<String, dynamic>());
      }
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить сводный график'));
  }

  /// Сводка nagavisor1.0 (суперпользователь).
  Future<Map<String, dynamic>> getNagavisor({
    required int teacherId,
    required DateTime from,
    required DateTime to,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse(
      '$baseUrl/admin/accounting/nagavisor?teacher_id=$teacherId&from=${_dateToIso(from)}&to=${_dateToIso(to)}',
    );
    final response = await timedGet(uri, headers: headers, timeout: const Duration(seconds: 45));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw Exception('Некорректный ответ сервера');
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(_extractMessage(response, 'Не удалось загрузить карточку преподавателя'));
  }

  String _extractMessage(dynamic response, String fallback) {
    try {
      final status = response.statusCode as int;
      final body = utf8.decode(response.bodyBytes as List<int>);
      final err = _tryDecodeJson(body);
      if (err?['message'] != null) {
        return '${err!['message']} (HTTP $status)';
      }
      return '$fallback (HTTP $status)';
    } catch (_) {
      return fallback;
    }
  }
}

