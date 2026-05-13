// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenSearchPart on _ChatScreenState {
  Future<void> _openSearch() async {
    final controller = TextEditingController();
    Timer? debounce;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<Map<String, dynamic>> results = [];
        bool isLoading = false;
        String? error;

        Future<void> runSearch(StateSetter setModalState, String q) async {
          final query = q.trim().toLowerCase();
          if (query.isEmpty) {
            setModalState(() {
              results = [];
              error = null;
              isLoading = false;
            });
            return;
          }
          setModalState(() {
            isLoading = true;
            error = null;
          });
          try {
            final found = await _messagesService.searchMessages(
              widget.chatId,
              q.trim(),
              limit: 30,
            );
            setModalState(() {
              results = found;
              isLoading = false;
            });
          } catch (e) {
            // Локальный поиск по уже загруженным сообщениям (офлайн / при ошибке API)
            final local = _messages
                .where((m) {
                  final content = (m.content).toLowerCase();
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
            setModalState(() {
              results = local;
              isLoading = false;
              error = local.isEmpty ? 'Ничего не найдено' : null;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Поиск по сообщениям…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (v) {
                            debounce?.cancel();
                            debounce = Timer(
                              const Duration(milliseconds: 250),
                              () {
                                runSearch(setModalState, v);
                              },
                            );
                          },
                        ),
                      ),
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      Flexible(
                        child: results.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  20,
                                ),
                                child: Text(
                                  controller.text.trim().isEmpty
                                      ? 'Введите запрос для поиска'
                                      : 'Ничего не найдено',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: results.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final r = results[index];
                                  final messageId = (r['message_id'] ?? '')
                                      .toString();
                                  final sender = (r['sender_email'] ?? '')
                                      .toString();
                                  final snippet = (r['content_snippet'] ?? '')
                                      .toString();
                                  final createdAt = (r['created_at'] ?? '')
                                      .toString();
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
                                          ? _formatDate(createdAt)
                                          : '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _jumpToMessage(messageId);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    debounce?.cancel();
    controller.dispose();
  }

}
