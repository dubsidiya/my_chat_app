import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/student.dart';
import '../models/lesson.dart';
import '../models/transaction.dart';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

class CreateStudentResult {
  final Student student;
  final bool wasExisting;

  const CreateStudentResult({
    required this.student,
    required this.wasExisting,
  });
}

class StudentsService {
  final String baseUrl = ApiConfig.baseUrl;
  final Random _rnd = Random();
  static const int _idempotencyRandomMax = 1000000000;
  static const bool _enableIdempotencyHeaders =
      bool.fromEnvironment('ENABLE_IDEMPOTENCY_HEADERS', defaultValue: true);

  String _newIdempotencyKey(String scope) {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = _rnd.nextInt(_idempotencyRandomMax);
    return '$scope-$t-$r';
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await StorageService.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Получение всех студентов
  Future<List<Student>> getAllStudents() async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Student.fromJson(json)).toList();
    } else if (response.statusCode == 403) {
      try {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Требуется приватный доступ');
      } catch (_) {
        throw Exception('Требуется приватный доступ');
      }
    } else {
      throw Exception('Не удалось загрузить студентов: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getMakeupPendingSummary() async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/makeup-pending'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
      return const {'totalPending': 0, 'studentsCount': 0, 'items': []};
    }
    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось загрузить сводку отработок');
  }

  // Создание студента
  Future<CreateStudentResult> createStudent({
    required String name,
    String? parentName,
    String? phone,
    String? email,
    String? notes,
    bool payByBankTransfer = false,
  }) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('student-create');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/students'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'parent_name': parentName,
        'phone': phone,
        'email': email,
        'notes': notes,
        'pay_by_bank_transfer': payByBankTransfer,
      }),
    );

    // 201 = создан новый студент
    // 200 = студент уже существовал в базе и был добавлен (привязан) к текущему преподавателю
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return CreateStudentResult(
        student: Student.fromJson({...data, 'balance': 0.0}),
        wasExisting: response.statusCode == 200,
      );
    }

    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось создать студента');
  }

  /// Поиск похожих учеников по имени/фамилии для предотвращения дублей.
  Future<List<Map<String, dynamic>>> searchStudentCandidates(
    String query, {
    int limit = 8,
  }) async {
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/students/search').replace(
      queryParameters: {
        'q': query,
        'limit': limit.toString(),
      },
    );
    final response = await timedGet(uri, headers: headers);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось выполнить поиск учеников');
  }

  /// Привязка существующего ученика (по id) к текущему преподавателю.
  Future<CreateStudentResult> linkExistingStudent({
    required int studentId,
  }) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('student-link-existing');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/students/link-existing'),
      headers: headers,
      body: jsonEncode({'student_id': studentId}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return CreateStudentResult(
        student: Student.fromJson({...data, 'balance': data['balance'] ?? 0.0}),
        wasExisting: true,
      );
    }
    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось привязать существующего ученика');
  }

  // Обновление студента
  Future<Student> updateStudent({
    required int id,
    required String name,
    String? parentName,
    String? phone,
    String? email,
    String? notes,
    bool payByBankTransfer = false,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await timedPut(
      Uri.parse('$baseUrl/students/$id'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'parent_name': parentName,
        'phone': phone,
        'email': email,
        'notes': notes,
        'pay_by_bank_transfer': payByBankTransfer,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Для суперпользователя нужен общий баланс, для преподавателя — только свои операции.
      final userData = await StorageService.getUserData();
      final isSuperuser = userData?['isSuperuser'] == 'true';
      final balanceUrl = isSuperuser
          ? '$baseUrl/students/$id/balance'
          : '$baseUrl/students/$id/balance?mine=1';
      final balanceResponse = await timedGet(
        Uri.parse(balanceUrl),
        headers: headers,
      );
      final balanceData = jsonDecode(balanceResponse.body);
      return Student.fromJson({...data, 'balance': balanceData['balance']});
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось обновить студента');
    }
  }

  // Удаление студента
  Future<void> deleteStudent(int id) async {
    final headers = await _getAuthHeaders();
    final response = await timedDelete(
      Uri.parse('$baseUrl/students/$id'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить студента');
    }
  }

  /// Полное каскадное удаление ученика (только суперпользователь).
  Future<void> deleteStudentFull(int id) async {
    final headers = await _getAuthHeaders();
    final response = await timedDelete(
      Uri.parse('$baseUrl/students/$id/full'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить ученика полностью');
    }
  }

  // Получение занятий студента
  Future<List<Lesson>> getStudentLessons(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/$studentId/lessons'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Lesson.fromJson(json)).toList();
    } else {
      throw Exception('Не удалось загрузить занятия: ${response.statusCode}');
    }
  }

  /// Получение занятий студента, созданных текущим пользователем (created_by = me).
  /// Важно для автоподстановок (разные цены у разных преподавателей).
  Future<List<Lesson>> getStudentLessonsMine(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/$studentId/lessons?mine=1'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Lesson.fromJson(json)).toList();
    } else {
      throw Exception('Не удалось загрузить занятия: ${response.statusCode}');
    }
  }

  static String _dateToIso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Занятия по дням (только созданные текущим пользователем), для календаря.
  Future<Map<DateTime, int>> getLessonsCalendarSummary({
    required DateTime from,
    required DateTime to,
  }) async {
    if (to.isBefore(from)) {
      throw Exception('Некорректный период: дата "до" раньше даты "от"');
    }
    final headers = await _getAuthHeaders();
    final uri = Uri.parse('$baseUrl/students/calendar-summary').replace(
      queryParameters: {
        'from': _dateToIso(from),
        'to': _dateToIso(to),
      },
    );
    final response = await timedGet(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Не удалось загрузить календарь: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final days = data['days'] as List<dynamic>? ?? [];
    final out = <DateTime, int>{};
    for (final row in days) {
      if (row is! Map) continue;
      final ds = row['date']?.toString();
      final c = row['count'];
      if (ds == null) continue;
      final dt = DateTime.tryParse(ds);
      if (dt == null) continue;
      final key = DateTime(dt.year, dt.month, dt.day);
      final n = c is int ? c : int.tryParse(c.toString()) ?? 0;
      out[key] = n;
    }
    return out;
  }

  // Создание занятия
  Future<Lesson> createLesson({
    required int studentId,
    required DateTime lessonDate,
    String? lessonTime,
    int? durationMinutes,
    required double price,
    String? notes,
    String status = 'attended',
    int? originLessonId,
  }) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('lesson-create');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/students/$studentId/lessons'),
      headers: headers,
      body: jsonEncode({
        'lesson_date': lessonDate.toIso8601String().split('T')[0],
        'lesson_time': lessonTime,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'price': price,
        'notes': notes,
        'status': status,
        if (originLessonId != null) 'origin_lesson_id': originLessonId,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return Lesson.fromJson(data);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось создать занятие');
    }
  }

  // Удаление занятия
  Future<void> deleteLesson(int lessonId) async {
    final headers = await _getAuthHeaders();
    final response = await timedDelete(
      Uri.parse('$baseUrl/students/lessons/$lessonId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить занятие');
    }
  }

  // Пополнение баланса
  Future<Transaction> depositBalance({
    required int studentId,
    required double amount,
    String? description,
  }) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('deposit-create');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/students/$studentId/deposit'),
      headers: headers,
      body: jsonEncode({
        'amount': amount,
        'description': description,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final tx = Transaction.fromJson(data);
      if (tx.studentId != studentId) {
        throw Exception(
          'Сервер создал транзакцию для другого ученика: ожидали id=$studentId, получили id=${tx.studentId}. '
          'Операция не засчитана.',
        );
      }
      return tx;
    }

    final error = jsonDecode(response.body);
    throw Exception(error['message'] ?? 'Не удалось пополнить баланс');
  }

  Future<void> deleteTransaction(int transactionId) async {
    final headers = await _getAuthHeaders();
    final response = await timedDelete(
      Uri.parse('$baseUrl/students/transactions/$transactionId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      try {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Не удалось отменить транзакцию');
      } catch (_) {
        throw Exception('Не удалось отменить транзакцию');
      }
    }
  }

  // Загрузка банковской выписки
  Future<Map<String, dynamic>> uploadBankStatement(List<int> fileBytes, String fileName) async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Токен не найден');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/bank-statement/upload'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

    final response = await timedMultipart(request);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось обработать выписку');
    }
  }

  // Применение платежей из выписки
  Future<Map<String, dynamic>> applyPayments(List<Map<String, dynamic>> payments) async {
    final headers = await _getAuthHeaders();
    if (_enableIdempotencyHeaders) {
      headers['Idempotency-Key'] = _newIdempotencyKey('bank-statement-apply');
    }
    final response = await timedPost(
      Uri.parse('$baseUrl/bank-statement/apply'),
      headers: headers,
      body: jsonEncode({
        'payments': payments,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось применить платежи');
    }
  }

  // Получение транзакций студента
  Future<List<Transaction>> getStudentTransactions(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/$studentId/transactions'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Transaction.fromJson(json)).toList();
    } else {
      throw Exception('Не удалось загрузить транзакции: ${response.statusCode}');
    }
  }

  Future<double> getStudentBalance(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/$studentId/balance'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final raw = data['balance'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString()) ?? 0.0;
    } else {
      throw Exception('Не удалось загрузить баланс: ${response.statusCode}');
    }
  }

  /// Получение транзакций студента, созданных текущим пользователем.
  Future<List<Transaction>> getStudentTransactionsMine(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/$studentId/transactions?mine=1'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Transaction.fromJson(json)).toList();
    } else {
      throw Exception('Не удалось загрузить транзакции: ${response.statusCode}');
    }
  }

  /// Получение баланса только по операциям текущего пользователя.
  Future<double> getStudentBalanceMine(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await timedGet(
      Uri.parse('$baseUrl/students/$studentId/balance?mine=1'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final raw = data['balance'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString()) ?? 0.0;
    } else {
      throw Exception('Не удалось загрузить баланс: ${response.statusCode}');
    }
  }
}

