import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/student.dart';
import '../models/lesson.dart';
import '../models/transaction.dart';
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
  final String baseUrl = 'https://my-server-chat.onrender.com';

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
    final response = await http.get(
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

  // Создание студента
  Future<CreateStudentResult> createStudent({
    required String name,
    String? parentName,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/students'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'parent_name': parentName,
        'phone': phone,
        'email': email,
        'notes': notes,
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

  // Обновление студента
  Future<Student> updateStudent({
    required int id,
    required String name,
    String? parentName,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/students/$id'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'parent_name': parentName,
        'phone': phone,
        'email': email,
        'notes': notes,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Получаем баланс отдельно
      final balanceResponse = await http.get(
        Uri.parse('$baseUrl/students/$id/balance'),
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
    final response = await http.delete(
      Uri.parse('$baseUrl/students/$id'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить студента');
    }
  }

  // Получение занятий студента
  Future<List<Lesson>> getStudentLessons(int studentId) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
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

  // Создание занятия
  Future<Lesson> createLesson({
    required int studentId,
    required DateTime lessonDate,
    String? lessonTime,
    required double price,
    String? notes,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/students/$studentId/lessons'),
      headers: headers,
      body: jsonEncode({
        'lesson_date': lessonDate.toIso8601String().split('T')[0],
        'lesson_time': lessonTime,
        'price': price,
        'notes': notes,
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
    final response = await http.delete(
      Uri.parse('$baseUrl/students/lessons/$lessonId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось удалить занятие');
    }
  }

  // Пополнение баланса
  Future<void> depositBalance({
    required int studentId,
    required double amount,
    String? description,
  }) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/students/$studentId/deposit'),
      headers: headers,
      body: jsonEncode({
        'amount': amount,
        'description': description,
      }),
    );

    if (response.statusCode != 201) {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Не удалось пополнить баланс');
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

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

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
    final response = await http.post(
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
    final response = await http.get(
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
}

