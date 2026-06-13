class ChatScrollPolicy {
  const ChatScrollPolicy._();

  static bool shouldAutoScrollToBottom({
    required bool didInitialOpenScrollToBottom,
    required bool isNearBottom,
  }) {
    return !didInitialOpenScrollToBottom || isNearBottom;
  }

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

  /// Подгрузка старых сообщений только после первичного скролла к низу при открытии.
  static bool shouldTriggerLoadMoreOnScroll({
    required bool isLoading,
    required bool didInitialOpenScrollToBottom,
    required double pixels,
    double loadMoreThreshold = 300,
  }) {
    if (isLoading) return false;
    if (!didInitialOpenScrollToBottom) return false;
    return pixels <= loadMoreThreshold;
  }

  static bool isScrollExtentStable({
    required double? previousMaxScrollExtent,
    required double currentMaxScrollExtent,
    double epsilon = 1.0,
  }) {
    if (previousMaxScrollExtent == null) return false;
    return (currentMaxScrollExtent - previousMaxScrollExtent).abs() < epsilon;
  }

  /// Остановка цикла `_scrollToBottomUntilSettled` при открытии чата.
  static bool shouldStopInitialScrollSettling({
    required int attempt,
    required int maxAttempts,
    required double? previousMaxScrollExtent,
    required double currentMaxScrollExtent,
    required bool isNearBottom,
    int minAttemptsBeforeStableStop = 2,
  }) {
    if (attempt >= maxAttempts) return true;
    if (attempt >= minAttemptsBeforeStableStop &&
        isNearBottom &&
        isScrollExtentStable(
          previousMaxScrollExtent: previousMaxScrollExtent,
          currentMaxScrollExtent: currentMaxScrollExtent,
        )) {
      return true;
    }
    return false;
  }

  /// Пользователь ушёл от низа — прекращаем первичный автоскролл, не перетягивать вниз.
  static bool shouldAbortInitialScrollSettling({
    required int attempt,
    required bool isNearBottom,
  }) {
    return attempt > 0 && !isNearBottom;
  }

  /// Первичный скролл после `_isLoading = false`, когда сообщения уже есть.
  static bool shouldRunInitialScrollAfterLoad({
    required bool shouldAutoScrollToBottom,
    required int messageCount,
  }) {
    return shouldAutoScrollToBottom && messageCount > 0;
  }

  /// Пустой чат: не ждём layout, сразу завершаем первичное открытие.
  static bool shouldMarkInitialScrollCompleteImmediately({
    required bool shouldAutoScrollToBottom,
    required int messageCount,
  }) {
    return shouldAutoScrollToBottom && messageCount == 0;
  }

  /// Poll/WebSocket: автоскролл только если пользователь у низа.
  static bool shouldScrollOnIncomingMessages({required bool isNearBottom}) {
    return isNearBottom;
  }

  /// Pull-to-refresh / reload: автоскролл как при первом открытии или у низа.
  static bool shouldAutoScrollAfterReload({
    required bool didInitialOpenScrollToBottom,
    required bool isNearBottom,
  }) {
    return shouldAutoScrollToBottom(
      didInitialOpenScrollToBottom: didInitialOpenScrollToBottom,
      isNearBottom: isNearBottom,
    );
  }
}
