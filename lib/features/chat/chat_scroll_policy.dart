class ChatScrollPolicy {
  const ChatScrollPolicy._();

  /// Автоскролл только когда пользователь «приклеен» к низу чата.
  static bool shouldAutoScroll({required bool stickToBottom}) => stickToBottom;

  static bool isNearBottom({
    required double pixels,
    required double maxScrollExtent,
    double threshold = 140,
  }) {
    return (maxScrollExtent - pixels) <= threshold;
  }

  static double preserveViewportAfterPrepend({
    required double currentScrollPosition,
    required double maxScrollExtentBefore,
    required double maxScrollExtentAfter,
  }) {
    return currentScrollPosition + (maxScrollExtentAfter - maxScrollExtentBefore);
  }

  /// Подгрузка старых сообщений только после первичного открытия чата.
  static bool shouldTriggerLoadMoreOnScroll({
    required bool isLoading,
    required bool initialOpenComplete,
    required double pixels,
    double loadMoreThreshold = 300,
  }) {
    if (isLoading) return false;
    if (!initialOpenComplete) return false;
    return pixels <= loadMoreThreshold;
  }

  /// Контент вырос (медиа, layout) — держим низ только если приклеены и уже у низа.
  static bool shouldReanchorToBottomOnContentGrowth({
    required bool stickToBottom,
    required double pixels,
    required double maxScrollExtent,
    double threshold = 140,
    double jumpEpsilon = 2,
  }) {
    if (!stickToBottom) return false;
    if (!isNearBottom(
      pixels: pixels,
      maxScrollExtent: maxScrollExtent,
      threshold: threshold,
    )) {
      return false;
    }
    return (maxScrollExtent - pixels) > jumpEpsilon;
  }

  /// Первичный скролл после `_isLoading = false`, когда сообщения уже есть.
  static bool shouldRunInitialScrollAfterLoad({
    required bool stickToBottom,
    required int messageCount,
  }) {
    return stickToBottom && messageCount > 0;
  }

  /// Пустой чат: не ждём layout, сразу завершаем первичное открытие.
  static bool shouldMarkInitialOpenCompleteImmediately({
    required int messageCount,
  }) {
    return messageCount == 0;
  }

  /// Poll/WebSocket: автоскролл только если пользователь приклеен к низу.
  static bool shouldScrollOnIncomingMessages({required bool stickToBottom}) {
    return stickToBottom;
  }

  /// Pull-to-refresh / reload: автоскролл только если приклеены к низу.
  static bool shouldAutoScrollAfterReload({required bool stickToBottom}) {
    return stickToBottom;
  }
}
