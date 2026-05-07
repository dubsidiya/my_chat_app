// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenExport on _ChatScreenState {
  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        // Сегодня - показываем только время
        return DateFormat('HH:mm').format(date);
      } else if (difference.inDays == 1) {
        // Вчера
        return 'Вчера ${DateFormat('HH:mm').format(date)}';
      } else if (difference.inDays < 7) {
        // На этой неделе - показываем день недели и время
        final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
        final weekday = weekdays[date.weekday - 1];
        return '$weekday ${DateFormat('HH:mm').format(date)}';
      } else {
        // Старше недели - показываем полную дату
        return DateFormat('dd.MM.yyyy HH:mm').format(date);
      }
    } catch (e) {
      // Если не удалось распарсить, возвращаем как есть
      return dateString;
    }
  }

  String _sanitizeFileName(String input) {
    final sanitized = input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    if (sanitized.isEmpty) return 'chat';
    return sanitized.length > 60 ? sanitized.substring(0, 60) : sanitized;
  }

  String _formatExportTime(String createdAt) {
    try {
      return DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(DateTime.parse(createdAt).toLocal());
    } catch (_) {
      return createdAt;
    }
  }

  Future<List<Message>> _collectMessagesForExport() async {
    final mergedById = <String, Message>{for (final m in _messages) m.id: m};
    var offset = 0;
    var hasMore = true;
    var safety = 0;

    while (hasMore && safety < 200) {
      final page = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: 100,
        offset: offset,
        useCache: true,
      );
      for (final m in page.messages) {
        mergedById[m.id] = m;
      }
      if (page.messages.isEmpty) break;
      hasMore = page.hasMore;
      offset += page.messages.length;
      safety++;
    }

    final result = mergedById.values.toList();
    result.sort((a, b) {
      final ta = DateTime.tryParse(a.createdAt);
      final tb = DateTime.tryParse(b.createdAt);
      if (ta == null && tb == null) return a.id.compareTo(b.id);
      if (ta == null) return -1;
      if (tb == null) return 1;
      return ta.compareTo(tb);
    });
    return result;
  }

  String _buildChatExportText(List<Message> messages) {
    final now = DateTime.now();
    final buffer = StringBuffer()
      ..writeln('Chat export')
      ..writeln('Chat: ${widget.chatName}')
      ..writeln('Chat ID: ${widget.chatId}')
      ..writeln('Exported at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}')
      ..writeln('Total messages: ${messages.length}')
      ..writeln('---');

    for (final m in messages) {
      final parts = <String>[];
      final text = m.content.trim();
      if (text.isNotEmpty) parts.add(text);
      if (m.hasImage) parts.add('[image] ${m.imageUrl}');
      if (m.hasFile) {
        final fileLabel = (m.fileName != null && m.fileName!.trim().isNotEmpty)
            ? m.fileName!.trim()
            : 'file';
        parts.add('[file] $fileLabel ${m.fileUrl}');
      }
      if (parts.isEmpty) parts.add('[empty message]');

      final line =
          '[${_formatExportTime(m.createdAt)}] ${m.senderEmail}: ${parts.join(' | ')}';
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  Future<void> _exportChat() async {
    if (_isExportingChat) return;
    setState(() => _isExportingChat = true);
    try {
      final messages = await _collectMessagesForExport();
      final text = _buildChatExportText(messages);
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = '${_sanitizeFileName(widget.chatName)}_$timestamp.txt';

      final okWeb = await downloadTextFile(
        filename: fileName,
        content: text,
        mimeType: 'text/plain; charset=utf-8',
      );
      if (okWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Экспорт чата начат'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text, flush: true);
      if (!mounted) return;

      final uri = Uri.file(file.path);
      final canOpen = await canLaunchUrl(uri);
      if (canOpen) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Экспорт сохранен: ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Не удалось экспортировать чат: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingChat = false);
      }
    }
  }
}
