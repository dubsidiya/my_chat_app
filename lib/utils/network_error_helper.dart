import 'dart:async';
import 'dart:io';

/// Превращает исключение сети/API в короткое сообщение для пользователя на русском.
/// Использовать в catch при показе SnackBar/диалога.
String networkErrorMessage(Object error) {
  final s = error.toString();
  if (error is SocketException) {
    return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
  }
  if (error is TimeoutException) {
    return 'Сервер не отвечает. Проверьте интернет или попробуйте позже.';
  }
  if (error is HandshakeException) {
    return 'Ошибка безопасного соединения. Проверьте дату на устройстве или попробуйте позже.';
  }
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('Connection refused')) {
    return 'Нет подключения к интернету. Проверьте сеть и попробуйте снова.';
  }
  if (s.contains('TimeoutException') || s.contains('timed out')) {
    return 'Сервер не отвечает. Проверьте интернет или попробуйте позже.';
  }
  // Убираем префикс "Exception: " и лишнее для пользователя
  String msg = s.replaceFirst(RegExp(r'^Exception:\s*'), '');
  if (msg.length > 120) msg = '${msg.substring(0, 117)}...';
  return msg;
}
