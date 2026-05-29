// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenSearchPart on _ChatScreenState {
  Future<void> _openSearch() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ChatMessageSearchSheet(
          messages: _messages,
          onSearch: (query) => _messagesService.searchMessages(
            widget.chatId,
            query,
            limit: 30,
          ),
          onSelectMessage: (messageId) {
            Navigator.pop(sheetContext);
            _jumpToMessage(messageId);
          },
          formatDate: _formatDate,
        );
      },
    );
  }
}

class _ChatMessageSearchSheet extends StatefulWidget {
  const _ChatMessageSearchSheet({
    required this.messages,
    required this.onSearch,
    required this.onSelectMessage,
    required this.formatDate,
  });

  final List<Message> messages;
  final Future<List<Map<String, dynamic>>> Function(String query) onSearch;
  final void Function(String messageId) onSelectMessage;
  final String Function(String dateString) formatDate;

  @override
  State<_ChatMessageSearchSheet> createState() =>
      _ChatMessageSearchSheetState();
}

class _ChatMessageSearchSheetState extends State<_ChatMessageSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final found = await widget.onSearch(q.trim());
      if (!mounted) return;
      setState(() {
        _results = found;
        _isLoading = false;
      });
    } catch (e) {
      final local = widget.messages
          .where((m) {
            final content = m.content.toLowerCase();
            final fileName = (m.fileName ?? '').toLowerCase();
            return content.contains(query) || fileName.contains(query);
          })
          .take(30)
          .map(
            (m) => {
              'message_id': m.id,
              'sender_email': m.senderEmail,
              'content_snippet': m.content.length > 80
                  ? '${m.content.substring(0, 80)}…'
                  : m.content,
              'created_at': m.createdAt,
            },
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _results = local;
        _isLoading = false;
        _error = local.isEmpty ? 'Ничего не найдено' : null;
      });
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _runSearch(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: maxHeight,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Поиск по сообщениям…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onChanged: _onQueryChanged,
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                          child: Text(
                            _controller.text.trim().isEmpty
                                ? 'Введите запрос для поиска'
                                : 'Ничего не найдено',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final r = _results[index];
                            final messageId =
                                (r['message_id'] ?? '').toString();
                            final sender =
                                (r['sender_email'] ?? '').toString();
                            final snippet =
                                (r['content_snippet'] ?? '').toString();
                            final createdAt =
                                (r['created_at'] ?? '').toString();
                            return ListTile(
                              title: Text(
                                sender.isNotEmpty ? sender : 'Сообщение',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                createdAt.isNotEmpty
                                    ? widget.formatDate(createdAt)
                                    : '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              onTap: () =>
                                  widget.onSelectMessage(messageId),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
