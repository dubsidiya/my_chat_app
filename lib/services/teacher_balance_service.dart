import 'dart:convert';

import '../config/api_config.dart';
import '../models/teacher_balance.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

class TeacherBalanceService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    final h = <String, String>{'Content-Type': 'application/json'};
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Map<String, dynamic>? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  Future<TeacherBalanceSummary> getMyBalance() async {
    final response = await timedGet(
      Uri.parse('$baseUrl/reports/balance'),
      headers: await _headers(),
    );
    final data = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200 && data != null) {
      return TeacherBalanceSummary.fromJson(data);
    }
    throw Exception(data?['message'] ?? 'Не удалось загрузить баланс');
  }

  Future<({double balance, List<TeacherBalanceTransaction> transactions})> getMyTransactions({
    int limit = 50,
  }) async {
    final response = await timedGet(
      Uri.parse('$baseUrl/reports/balance/transactions?limit=$limit'),
      headers: await _headers(),
    );
    final data = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200 && data != null) {
      final list = data['transactions'];
      final txs = list is List
          ? list
              .whereType<Map>()
              .map((m) => TeacherBalanceTransaction.fromJson(
                    m.map((k, v) => MapEntry(k.toString(), v)),
                  ))
              .toList()
          : <TeacherBalanceTransaction>[];
      return (balance: _parseDouble(data['balance']), transactions: txs);
    }
    throw Exception(data?['message'] ?? 'Не удалось загрузить историю');
  }

  Future<List<TeacherBalanceListItem>> listTeachers() async {
    final response = await timedGet(
      Uri.parse('$baseUrl/admin/accounting/teacher-balances'),
      headers: await _headers(),
    );
    final data = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200 && data != null) {
      final list = data['teachers'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => TeacherBalanceListItem.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    }
    if (response.statusCode == 403) {
      throw Exception('Требуется доступ суперпользователя');
    }
    throw Exception(data?['message'] ?? 'Не удалось загрузить список');
  }

  Future<({TeacherBalanceSummary summary, List<TeacherBalanceTransaction> transactions})>
      getTeacherDetail(int teacherId, {int limit = 100}) async {
    final response = await timedGet(
      Uri.parse('$baseUrl/admin/accounting/teacher-balances/$teacherId?limit=$limit'),
      headers: await _headers(),
    );
    final data = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200 && data != null) {
      final list = data['transactions'];
      final txs = list is List
          ? list
              .whereType<Map>()
              .map((m) => TeacherBalanceTransaction.fromJson(
                    m.map((k, v) => MapEntry(k.toString(), v)),
                  ))
              .toList()
          : <TeacherBalanceTransaction>[];
      return (
        summary: TeacherBalanceSummary.fromJson(data),
        transactions: txs,
      );
    }
    throw Exception(data?['message'] ?? 'Не удалось загрузить баланс преподавателя');
  }

  Future<({double balance, TeacherBalanceTransaction transaction})> postTransaction({
    required int teacherId,
    required String type,
    required double amount,
    required String description,
  }) async {
    final response = await timedPost(
      Uri.parse('$baseUrl/admin/accounting/teacher-balances/$teacherId/transactions'),
      headers: await _headers(),
      body: jsonEncode({
        'type': type,
        'amount': amount,
        'description': description,
      }),
    );
    final data = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 201 && data != null) {
      final txRaw = data['transaction'];
      if (txRaw is Map) {
        return (
          balance: _parseDouble(data['balance']),
          transaction: TeacherBalanceTransaction.fromJson(
            txRaw.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
    }
    throw Exception(data?['message'] ?? 'Не удалось создать операцию');
  }

  Future<void> syncBalances({required String from, required String to}) async {
    final response = await timedPost(
      Uri.parse('$baseUrl/admin/accounting/teacher-balances/sync?from=$from&to=$to'),
      headers: await _headers(),
      body: jsonEncode({}),
    );
    final data = _decode(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200) return;
    throw Exception(data?['message'] ?? 'Не удалось синхронизировать балансы');
  }
}

double _parseDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
