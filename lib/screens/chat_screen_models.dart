part of 'chat_screen.dart';

/// Элементы списка сообщений: кнопка «ещё», индикатор загрузки, заголовок даты или сообщение
class _ListEntry {}

class _LoadMoreEntry extends _ListEntry {}

class _LoadingEntry extends _ListEntry {}

class _DateHeaderEntry extends _ListEntry {
  final String label;
  _DateHeaderEntry(this.label);
}

class _MessageEntry extends _ListEntry {
  final int index;
  _MessageEntry(this.index);
}

enum _OutgoingUiState { queued, sending, error }

class _PendingUploadDraft {
  final String text;
  final String idempotencyKey;
  final String? replyToMessageId;
  final Message? replyToMessage;
  final Uint8List? imageBytes;
  final String? imagePath;
  final String? imageName;
  final Uint8List? fileBytes;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;

  const _PendingUploadDraft({
    required this.text,
    required this.idempotencyKey,
    this.replyToMessageId,
    this.replyToMessage,
    this.imageBytes,
    this.imagePath,
    this.imageName,
    this.fileBytes,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.fileMime,
  });

  bool get hasImage => imageBytes != null || (imagePath != null && imagePath!.isNotEmpty);
  bool get hasFile => fileBytes != null || (filePath != null && filePath!.isNotEmpty);
}
