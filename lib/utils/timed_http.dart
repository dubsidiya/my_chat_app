import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Единый таймаут для JSON API (кроме явно длинных операций).
const Duration kHttpTimeout = Duration(seconds: 45);

/// Загрузка файлов / multipart.
const Duration kHttpUploadTimeout = Duration(seconds: 120);

Future<http.Response> timedGet(
  Uri url, {
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    http.get(url, headers: headers).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedPost(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    http.post(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedPut(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    http.put(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedPatch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    http.patch(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedDelete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    http.delete(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedMultipart(
  http.MultipartRequest request, {
  Duration? timeout,
}) async {
  final streamed = await request.send().timeout(timeout ?? kHttpUploadTimeout);
  return http.Response.fromStream(streamed).timeout(timeout ?? kHttpUploadTimeout);
}
