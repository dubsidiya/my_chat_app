import 'package:flutter/material.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

/// Стенд, повторяющий production-модель скролла чата: `ListView(reverse: true)`.
/// Низ (новые сообщения) — смещение 0; старые сообщения сверху, ближе к
/// `maxScrollExtent`. `itemHeights` хранится в порядке старые→новые (как
/// `_messages`), а в reverse-список мапится index 0 = новое (низ).
class ChatScrollHarness extends StatefulWidget {
  const ChatScrollHarness({
    super.key,
    this.initialItemHeights = const [56, 56, 56, 200, 56, 56],
    this.autoStartOpen = true,
    this.hasMoreMessages = true,
    this.onLoadMore,
  });

  final List<double> initialItemHeights; // старые -> новые
  final bool autoStartOpen;
  final bool hasMoreMessages;
  final VoidCallback? onLoadMore;

  @override
  State<ChatScrollHarness> createState() => ChatScrollHarnessState();
}

class ChatScrollHarnessState extends State<ChatScrollHarness> {
  final ScrollController scrollController = ScrollController();

  bool isLoading = true;
  bool initialOpenComplete = false;
  bool isLoadingMore = false;
  bool hasMoreMessages = true;
  int loadMoreCalls = 0;

  late List<double> itemHeights; // старые -> новые
  late List<int> _itemIds; // стабильные ключи
  int _nextOldId = -1;
  int _nextNewId = 0;

  @override
  void initState() {
    super.initState();
    itemHeights = List<double>.from(widget.initialItemHeights);
    _itemIds = List<int>.generate(itemHeights.length, (i) => i);
    _nextNewId = itemHeights.length;
    hasMoreMessages = widget.hasMoreMessages;
    scrollController.addListener(_onScroll);
    if (widget.autoStartOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => simulateOpenChat());
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  void showListWithoutInitialScroll() {
    setState(() {
      isLoading = false;
      initialOpenComplete = false;
    });
  }

  Future<void> simulateOpenChat() async {
    isLoading = true;
    initialOpenComplete = false;
    loadMoreCalls = 0;
    setState(() {});

    isLoading = false;
    setState(() {});

    // reverse:true → список открывается у низа сам, прокрутка не нужна.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => initialOpenComplete = true);
    });
  }

  /// Reload (E2EE/pull-to-refresh): позиция сохраняется reverse-списком.
  Future<void> simulateE2eeReload() async {
    isLoading = true;
    setState(() {});
    isLoading = false;
    setState(() {});
  }

  bool get isAtBottom {
    if (!scrollController.hasClients) return true;
    return ChatScrollPolicy.isAtBottom(
      pixels: scrollController.position.pixels,
    );
  }

  void growItemAt(int index, double newHeight) {
    if (index < 0 || index >= itemHeights.length) return;
    setState(() => itemHeights[index] = newHeight);
  }

  /// Новое (самое новое) сообщение — добавляется в конец данных (низ в reverse).
  void appendNewMessage(double height) {
    setState(() {
      itemHeights.add(height);
      _itemIds.add(_nextNewId++);
    });
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (!ChatScrollPolicy.shouldLoadMoreOnScroll(
      isLoading: isLoading,
      initialOpenComplete: initialOpenComplete,
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
    )) {
      return;
    }
    if (isLoadingMore || !hasMoreMessages || itemHeights.isEmpty) return;

    isLoadingMore = true;
    loadMoreCalls += 1;
    widget.onLoadMore?.call();

    setState(() {
      // Старые сообщения — в начало данных. В reverse это «выше» якоря-низа,
      // позиция сохраняется автоматически (без пересчёта maxScrollExtent).
      itemHeights.insert(0, 56);
      _itemIds.insert(0, _nextOldId--);
      itemHeights.insert(0, 56);
      _itemIds.insert(0, _nextOldId--);
      isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : itemHeights.isEmpty
          ? const Center(child: Text('empty'))
          : ListView.builder(
              controller: scrollController,
              reverse: true,
              itemCount: itemHeights.length,
              itemBuilder: (context, index) {
                // index 0 = низ = самое новое = последний элемент данных.
                final dataIndex = itemHeights.length - 1 - index;
                return SizedBox(
                  key: ValueKey('item-${_itemIds[dataIndex]}'),
                  height: itemHeights[dataIndex],
                  child: ColoredBox(
                    color: dataIndex.isEven
                        ? Colors.blue.withValues(alpha: 0.15)
                        : Colors.green.withValues(alpha: 0.15),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('message $dataIndex'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
