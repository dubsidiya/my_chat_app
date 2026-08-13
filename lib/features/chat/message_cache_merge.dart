import '../../models/message.dart';

/// Слияние страницы с сервера и локального Hive-кэша по id.
///
/// Входящие сообщения побеждают при том же id (свежие поля с сервера).
/// Сообщения старше/новее окна страницы сохраняются — иначе пагинация
/// по 50 штук затирала бы историю или только что отправленное.
///
/// [evictMissingInWindow]: убрать id, которые попали в диапазон дат страницы,
/// но сервер их уже не отдаёт (удалённые). Не трогает `temp_` и сообщения
/// строго новее самой свежей в странице (гонка send vs fetch).
List<Message> mergeMessageCache({
  required List<Message> existing,
  required List<Message> incoming,
  bool evictMissingInWindow = false,
}) {
  if (incoming.isEmpty) {
    return List<Message>.from(existing);
  }

  final incomingById = <String, Message>{};
  DateTime? oldest;
  DateTime? newest;
  for (final message in incoming) {
    if (message.id.isEmpty) continue;
    incomingById[message.id] = message;
    final time = DateTime.tryParse(message.createdAt);
    if (time == null) continue;
    if (oldest == null || time.isBefore(oldest)) oldest = time;
    if (newest == null || time.isAfter(newest)) newest = time;
  }

  final byId = <String, Message>{};
  for (final message in existing) {
    if (message.id.isEmpty) continue;
    if (evictMissingInWindow &&
        oldest != null &&
        newest != null &&
        !incomingById.containsKey(message.id) &&
        !message.id.startsWith('temp_')) {
      final time = DateTime.tryParse(message.createdAt);
      if (time != null && !time.isBefore(oldest) && !time.isAfter(newest)) {
        continue;
      }
    }
    byId[message.id] = message;
  }
  incomingById.forEach((id, message) => byId[id] = message);

  final merged = byId.values.toList();
  merged.sort(_compareMessagesByTime);
  return merged;
}

int _compareMessagesByTime(Message a, Message b) {
  final aTime = DateTime.tryParse(a.createdAt);
  final bTime = DateTime.tryParse(b.createdAt);
  if (aTime != null && bTime != null) {
    final byTime = aTime.compareTo(bTime);
    if (byTime != 0) return byTime;
  }
  return a.id.compareTo(b.id);
}
