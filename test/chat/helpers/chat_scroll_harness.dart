import 'package:flutter/material.dart';
import 'package:my_chat_app/features/chat/chat_scroll_policy.dart';

/// Минимальный стенд, повторяющий production-flow открытия чата и скролла.
class ChatScrollHarness extends StatefulWidget {
  const ChatScrollHarness({
    super.key,
    this.initialItemHeights = const [56, 56, 56, 200, 56, 56],
    this.autoStartOpen = true,
    this.simulateDelayedMediaIndex,
    this.simulateDelayedMediaHeight = 400,
    this.delayedMediaAfterFrames = 2,
    this.hasMoreMessages = true,
    this.onLoadMore,
  });

  final List<double> initialItemHeights;
  final bool autoStartOpen;
  final int? simulateDelayedMediaIndex;
  final double simulateDelayedMediaHeight;
  final int delayedMediaAfterFrames;
  final bool hasMoreMessages;
  final VoidCallback? onLoadMore;

  @override
  State<ChatScrollHarness> createState() => ChatScrollHarnessState();
}

class ChatScrollHarnessState extends State<ChatScrollHarness> {
  final ScrollController scrollController = ScrollController();

  bool isLoading = true;
  bool didInitialOpenScrollToBottom = false;
  bool isLoadingMore = false;
  bool hasMoreMessages = true;
  int loadMoreCalls = 0;
  int _initialScrollSettleGeneration = 0;
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

  /// Для widget-тестов: показать список без завершённого первичного скролла.
  void showListWithoutInitialScroll() {
    setState(() {
      isLoading = false;
      didInitialOpenScrollToBottom = false;
    });
  }

  Future<void> simulateOpenChat() async {
    isLoading = true;
    didInitialOpenScrollToBottom = false;
    loadMoreCalls = 0;
    setState(() {});

    isLoading = false;
    setState(() {});

    if (ChatScrollPolicy.shouldRunInitialScrollAfterLoad(
      shouldAutoScrollToBottom: true,
      messageCount: itemHeights.length,
    )) {
      _completeInitialOpenScroll();
    } else if (ChatScrollPolicy.shouldMarkInitialScrollCompleteImmediately(
      shouldAutoScrollToBottom: true,
      messageCount: itemHeights.length,
    )) {
      didInitialOpenScrollToBottom = true;
      setState(() {});
    }

    final delayedIndex = widget.simulateDelayedMediaIndex;
    if (delayedIndex != null) {
      var framesLeft = widget.delayedMediaAfterFrames;
      void scheduleMediaExpand() {
        if (framesLeft <= 0) {
          if (delayedIndex < 0 || delayedIndex >= itemHeights.length) return;
          setState(() {
            itemHeights[delayedIndex] = widget.simulateDelayedMediaHeight;
          });
          if (!didInitialOpenScrollToBottom) {
            _completeInitialOpenScroll();
          }
          return;
        }
        framesLeft -= 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          scheduleMediaExpand();
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => scheduleMediaExpand());
    }
  }

  void _completeInitialOpenScroll() {
    final generation = ++_initialScrollSettleGeneration;
    _scrollToBottomUntilSettled(generation: generation);
  }

  void _cancelInitialScrollSettling() {
    _initialScrollSettleGeneration++;
    didInitialOpenScrollToBottom = true;
    setState(() {});
  }

  void _scrollToBottomUntilSettled({
    required int generation,
    int maxAttempts = 12,
  }) {
    void finish() {
      if (generation != _initialScrollSettleGeneration || !mounted) return;
      didInitialOpenScrollToBottom = true;
      setState(() {});
    }

    void tryScroll(int attempt, double? previousMaxExtent) {
      if (!mounted || generation != _initialScrollSettleGeneration) return;
      if (attempt >= maxAttempts) {
        finish();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _initialScrollSettleGeneration) return;
        if (!scrollController.hasClients || itemHeights.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            tryScroll(attempt + 1, previousMaxExtent);
          });
          return;
        }

        final nearBottom = isNearBottom;
        if (ChatScrollPolicy.shouldAbortInitialScrollSettling(
          attempt: attempt,
          isNearBottom: nearBottom,
        )) {
          finish();
          return;
        }

        final maxScroll = scrollController.position.maxScrollExtent;
        if (ChatScrollPolicy.shouldStopInitialScrollSettling(
          attempt: attempt,
          maxAttempts: maxAttempts,
          previousMaxScrollExtent: previousMaxExtent,
          currentMaxScrollExtent: maxScroll,
          isNearBottom: nearBottom,
        )) {
          scrollController.jumpTo(maxScroll.clamp(0.0, double.infinity));
          finish();
          return;
        }

        scrollController.jumpTo(maxScroll.clamp(0.0, double.infinity));
        tryScroll(attempt + 1, maxScroll);
      });
    }

    tryScroll(0, null);
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    if (!didInitialOpenScrollToBottom &&
        ChatScrollPolicy.shouldAbortInitialScrollSettling(
          attempt: 1,
          isNearBottom: isNearBottom,
        )) {
      _cancelInitialScrollSettling();
    }

    if (!ChatScrollPolicy.shouldTriggerLoadMoreOnScroll(
      isLoading: isLoading,
      didInitialOpenScrollToBottom: didInitialOpenScrollToBottom,
      pixels: scrollController.position.pixels,
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
    if (!scrollController.hasClients) return true;
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
          : ListView.builder(
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
    );
  }
}
