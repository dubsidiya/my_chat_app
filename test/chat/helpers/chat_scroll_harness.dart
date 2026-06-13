import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

/// Минимальный стенд, повторяющий production-flow открытия чата и скролла.
class ChatScrollHarness extends StatefulWidget {
  const ChatScrollHarness({
    super.key,
    this.initialItemHeights = const [56, 56, 56, 200, 56, 56],
    this.autoStartOpen = true,
    this.hasMoreMessages = true,
    this.onLoadMore,
  });

  final List<double> initialItemHeights;
  final bool autoStartOpen;
  final bool hasMoreMessages;
  final VoidCallback? onLoadMore;

  @override
  State<ChatScrollHarness> createState() => ChatScrollHarnessState();
}

class ChatScrollHarnessState extends State<ChatScrollHarness> {
  final ScrollController scrollController = ScrollController();

  bool isLoading = true;
  bool stickToBottom = true;
  bool initialOpenComplete = false;
  bool isLoadingMore = false;
  bool hasMoreMessages = true;
  int loadMoreCalls = 0;
  late List<double> itemHeights;

  @override
  void initState() {
    super.initState();
    itemHeights = List<double>.from(widget.initialItemHeights);
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
      stickToBottom = true;
      initialOpenComplete = false;
    });
  }

  Future<void> simulateOpenChat() async {
    isLoading = true;
    stickToBottom = true;
    initialOpenComplete = false;
    loadMoreCalls = 0;
    setState(() {});

    isLoading = false;
    setState(() {});

    if (ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
      stickToBottom: stickToBottom,
      messageCount: itemHeights.length,
    )) {
      _completeInitialOpenScroll();
    } else if (ChatScrollPolicy.shouldMarkInitialOpenCompleteImmediately(
      messageCount: itemHeights.length,
    )) {
      _markInitialOpenComplete();
    }
  }

  void _markInitialOpenComplete() {
    initialOpenComplete = true;
    setState(() {});
  }

  void _completeInitialOpenScroll() {
    _scrollToBottomAfterLayout(
      attempts: 3,
      onFinished: _markInitialOpenComplete,
    );
  }

  void _scrollToBottomAfterLayout({
    int attempts = 3,
    VoidCallback? onFinished,
  }) {
    void tryScroll(int left) {
      if (!mounted || left <= 0 || !stickToBottom) {
        onFinished?.call();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !stickToBottom) {
          onFinished?.call();
          return;
        }
        if (scrollController.hasClients && itemHeights.isNotEmpty) {
          final maxScroll = scrollController.position.maxScrollExtent;
          scrollController.jumpTo(maxScroll.clamp(0.0, double.infinity));
        }
        tryScroll(left - 1);
      });
    }

    tryScroll(attempts);
  }

  void simulateUserScrollUp() {
    stickToBottom = false;
    _markInitialOpenComplete();
    setState(() {});
  }

  bool handleUserScrollNotification(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    final direction = notification.direction;
    if (direction == ScrollDirection.reverse) {
      stickToBottom = false;
      _markInitialOpenComplete();
    } else if (direction == ScrollDirection.forward &&
        scrollController.hasClients &&
        isNearBottom) {
      stickToBottom = true;
    }
    return false;
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;
    if (ChatScrollPolicy.shouldReanchorToBottomOnContentGrowth(
      stickToBottom: stickToBottom,
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
    )) {
      position.jumpTo(position.maxScrollExtent);
    }

    if (!ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
      isLoading: isLoading,
      initialOpenComplete: initialOpenComplete,
      pixels: position.pixels,
    )) {
      return;
    }
    if (isLoadingMore || !hasMoreMessages || itemHeights.isEmpty) return;

    isLoadingMore = true;
    loadMoreCalls += 1;
    widget.onLoadMore?.call();

    final currentScrollPosition = scrollController.position.pixels;
    final maxScrollExtentBefore = scrollController.position.maxScrollExtent;

    setState(() {
      itemHeights.insert(0, 56);
      itemHeights.insert(0, 56);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients || !mounted) return;
      final maxScrollExtentAfter = scrollController.position.maxScrollExtent;
      final newScrollPosition = ChatScrollPolicy.preserveViewportAfterPrepend(
        currentScrollPosition: currentScrollPosition,
        maxScrollExtentBefore: maxScrollExtentBefore,
        maxScrollExtentAfter: maxScrollExtentAfter,
      );
      scrollController.jumpTo(
        newScrollPosition.clamp(0.0, scrollController.position.maxScrollExtent),
      );
      isLoadingMore = false;
      setState(() {});
    });
  }

  bool get isNearBottom {
    if (!scrollController.hasClients) return false;
    return ChatScrollPolicy.isNearBottom(
      pixels: scrollController.position.pixels,
      maxScrollExtent: scrollController.position.maxScrollExtent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : itemHeights.isEmpty
          ? const Center(child: Text('empty'))
          : NotificationListener<UserScrollNotification>(
              onNotification: handleUserScrollNotification,
              child: ListView.builder(
                controller: scrollController,
                itemCount: itemHeights.length,
                itemBuilder: (context, index) {
                  return SizedBox(
                    key: ValueKey('item-$index-${itemHeights[index]}'),
                    height: itemHeights[index],
                    child: ColoredBox(
                      color: index.isEven
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.green.withValues(alpha: 0.15),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('message $index'),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
