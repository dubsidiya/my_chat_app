/// Локальный снимок блок-листа: WS и кэш не показывают тех, кого скрыл REST.
class BlockedUsersCache {
  BlockedUsersCache._();

  static final Set<String> _ids = <String>{};
  static int _mutationVersion = 0;

  static int get mutationVersion => _mutationVersion;

  static bool isBlocked(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return false;
    return _ids.contains(id);
  }

  static void rememberAll(Iterable<String> ids) {
    _ids
      ..clear()
      ..addAll(ids.map((id) => id.trim()).where((id) => id.isNotEmpty));
  }

  /// Ответ сервера: заменить список, если за время запроса не было local add.
  /// Иначе объединить — иначе фоновый fetch сотрёт только что поставленный блок.
  static void applyServerList(
    Iterable<String> ids, {
    required int versionAtRequestStart,
  }) {
    final incoming = ids.map((id) => id.trim()).where((id) => id.isNotEmpty);
    if (_mutationVersion == versionAtRequestStart) {
      _ids
        ..clear()
        ..addAll(incoming);
    } else {
      _ids.addAll(incoming);
    }
  }

  static void add(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return;
    _ids.add(id);
    _mutationVersion++;
  }

  static void clear() {
    _ids.clear();
    _mutationVersion++;
  }

  static List<String> snapshot() => List<String>.unmodifiable(_ids);
}
