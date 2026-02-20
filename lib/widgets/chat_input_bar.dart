import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ChatInputBar extends StatelessWidget {
  final ColorScheme scheme;
  final Color accent1;
  final Color accent2;
  final TextEditingController controller;
  final bool isUploadingImage;
  final bool isUploadingFile;
  final bool isRecordingVoice;
  final Duration voiceRecordDuration;
  final VoidCallback onCancelVoiceRecording;
  final VoidCallback onPickFile;
  final VoidCallback onPickImage;
  final VoidCallback onToggleVoiceRecording;
  final void Function() onVoiceLongPressStart;
  final void Function() onVoiceLongPressEnd;
  final VoidCallback onSend;
  final void Function(String) onChanged;
  final List<Map<String, String>> mentionSuggestions;
  final void Function(String handle) onSelectMention;

  const ChatInputBar({
    super.key,
    required this.scheme,
    required this.accent1,
    required this.accent2,
    required this.controller,
    required this.isUploadingImage,
    required this.isUploadingFile,
    required this.isRecordingVoice,
    required this.voiceRecordDuration,
    required this.onCancelVoiceRecording,
    required this.onPickFile,
    required this.onPickImage,
    required this.onToggleVoiceRecording,
    required this.onVoiceLongPressStart,
    required this.onVoiceLongPressEnd,
    required this.onSend,
    required this.onChanged,
    required this.mentionSuggestions,
    required this.onSelectMention,
  });

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRecordingVoice)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red.shade50,
                  Colors.red.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.2), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Запись: ${_formatDuration(voiceRecordDuration)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade800,
                      fontSize: 14,
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onCancelVoiceRecording,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close_rounded, size: 22, color: Colors.red.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (mentionSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.22)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: mentionSuggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outline.withValues(alpha: 0.18)),
                itemBuilder: (context, index) {
                  final s = mentionSuggestions[index];
                  final handle = (s['handle'] ?? '').toString();
                  final label = (s['label'] ?? s['email'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.alternate_email_rounded, color: AppColors.primaryGlow),
                    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('@$handle', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => onSelectMention(handle),
                  );
                },
              ),
            ),
          ),
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: accent2.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: Icon(Icons.attach_file_rounded, color: accent2),
                onPressed: isRecordingVoice ? null : onPickFile,
                tooltip: 'Прикрепить файл',
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: accent1.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: Icon(Icons.image_rounded, color: accent1),
                onPressed: isRecordingVoice ? null : onPickImage,
                tooltip: 'Прикрепить изображение',
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Удерживайте для записи. Отпустите — отправить. Тап — старт/стоп.',
              child: GestureDetector(
                onLongPressStart: (_) {
                  if (isUploadingImage || isUploadingFile) return;
                  onVoiceLongPressStart();
                },
                onLongPressEnd: (_) {
                  if (isUploadingImage || isUploadingFile) return;
                  onVoiceLongPressEnd();
                },
                child: Material(
                  color: (isRecordingVoice ? Colors.red : accent1).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: (isUploadingImage || isUploadingFile) ? null : onToggleVoiceRecording,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                        color: isRecordingVoice ? Colors.red.shade700 : accent1,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Введите сообщение...',
                    hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (isUploadingImage || isUploadingFile)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent1, accent2],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: AppColors.neonGlow,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: isRecordingVoice ? null : onSend,
                  tooltip: 'Отправить',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

