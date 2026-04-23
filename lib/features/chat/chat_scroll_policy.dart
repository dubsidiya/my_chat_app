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
}
