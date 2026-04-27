import 'dart:io' as io;

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createTimedHttpClient() {
  final raw = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 45);
  return IOClient(raw);
}
