import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'timed_http_client.dart';

/// Единый HTTP-клиент: на mobile/desktop — [IOClient] с connectionTimeout (иначе TCP может висеть десятки секунд).
http.Client? _sharedClient;
http.Client get _httpClient => _sharedClient ??= createTimedHttpClient();

/// Единый таймаут для JSON API (кроме явно длинных операций).
const Duration kHttpTimeout = Duration(seconds: 45);

/// Загрузка файлов / multipart.
const Duration kHttpUploadTimeout = Duration(seconds: 120);

Future<http.Response> timedGet(
  Uri url, {
  Map<String, String>? headers,
  Duration? timeout,
}) =>
    _httpClient.get(url, headers: headers).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedPost(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    _httpClient.post(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedPut(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    _httpClient.put(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedPatch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    _httpClient.patch(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedDelete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
  Duration? timeout,
}) =>
    _httpClient.delete(url, headers: headers, body: body, encoding: encoding).timeout(timeout ?? kHttpTimeout);

Future<http.Response> timedMultipart(
  http.MultipartRequest request, {
  Duration? timeout,
}) async {
  final streamed = await request.send().timeout(timeout ?? kHttpUploadTimeout);
  return http.Response.fromStream(streamed).timeout(timeout ?? kHttpUploadTimeout);
}
