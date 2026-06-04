import 'package:web/web.dart' as web;

/// True when the page is served over HTTPS or localhost (required for getUserMedia).
bool isWebSecureContext() => web.window.isSecureContext;
