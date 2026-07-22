import 'dart:async';

/// Глобальный hook: ChatScreen регистрирует pause just_audio перед WebRTC.
/// Иначе входящий accept / auto-open не останавливает голосовое сообщение.
///
/// Стек handlers: несколько ChatScreen в navigator stack — unregister одного
/// не должен сбрасывать handler другого видимого чата.
typedef CallPlaybackPauseHandler = Future<void> Function();

class CallPlaybackPause {
  CallPlaybackPause._();

  static final List<CallPlaybackPauseHandler> _stack = [];

  static void register(CallPlaybackPauseHandler handler) {
    _stack.remove(handler);
    _stack.add(handler);
  }

  static void unregister([CallPlaybackPauseHandler? handler]) {
    if (handler != null) {
      _stack.remove(handler);
      return;
    }
    if (_stack.isNotEmpty) _stack.removeLast();
  }

  static Future<void> pauseBestEffort() async {
    final handlers = List<CallPlaybackPauseHandler>.of(_stack);
    for (final h in handlers) {
      try {
        await h();
      } catch (_) {}
    }
  }
}
