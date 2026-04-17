import '../models/message.dart';

/// Распознавание аудио по MIME или расширению файла.
bool looksLikeAudio({String? mime, String? fileName}) {
  final m = (mime ?? '').toLowerCase().trim();
  final n = (fileName ?? '').toLowerCase().trim();
  if (m.startsWith('audio/')) return true;
  return n.endsWith('.m4a') ||
      n.endsWith('.aac') ||
      n.endsWith('.mp3') ||
      n.endsWith('.ogg') ||
      n.endsWith('.opus') ||
      n.endsWith('.wav');
}

/// Голосовое сообщение (тип или аудио-вложение).
bool isVoiceMessage(Message msg) {
  if (msg.messageType == 'voice' || msg.messageType == 'text_voice') return true;
  if (!msg.hasFile) return false;
  return looksLikeAudio(mime: msg.fileMime, fileName: msg.fileName);
}

/// Формат `MM:SS` для длительности голоса.
String formatVoiceDuration(Duration d) {
  final totalSeconds = d.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
