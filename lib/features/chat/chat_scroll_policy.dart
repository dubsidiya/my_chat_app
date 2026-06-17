/// Политики скролла чата для `ListView(reverse: true)`.
///
/// В reverse-списке низ (самые новые сообщения) — это смещение **0**, точное и
/// стабильное значение, а старые сообщения находятся ближе к `maxScrollExtent`
/// (вверху). Благодаря этому:
///  • «прилипание» к низу не требует прыжков — достаточно быть у смещения 0;
///  • догрузка истории добавляет элементы «выше» якоря-низа и не сдвигает
///    видимую область, поэтому не нужна математика сохранения позиции;
///  • рост контента (догрузка картинки) у низа не порождает обратную связь
///    `jumpTo(maxScrollExtent)` → пересчёт оценки → снова `jumpTo` («пружину»).
class ChatScrollPolicy {
  const ChatScrollPolicy._();

  /// «У низа» (видны новые сообщения). В reverse это малое смещение.
  static bool isAtBottom({
    required double pixels,
    double threshold = 120,
  }) {
    return pixels <= threshold;
  }

  /// Догрузка истории: пользователь подошёл к верхнему краю списка. В reverse
  /// верх — это близко к `maxScrollExtent`.
  static bool shouldLoadMoreOnScroll({
    required bool isLoading,
    required bool initialOpenComplete,
    required double pixels,
    required double maxScrollExtent,
    double threshold = 300,
  }) {
    if (isLoading) return false;
    if (!initialOpenComplete) return false;
    if (maxScrollExtent <= 0) return false;
    return (maxScrollExtent - pixels) <= threshold;
  }

  /// Автоскролл к низу при входящем сообщении / после reload — только если
  /// пользователь уже у низа (иначе не дёргаем читающего историю).
  static bool shouldAutoScrollOnIncoming({required bool atBottom}) => atBottom;
}
