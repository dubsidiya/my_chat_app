// ignore_for_file: invalid_use_of_protected_member

part of 'chat_screen.dart';

extension _ChatScreenMediaVoicePart on _ChatScreenState {
  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source);
      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return;
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = picked.name;
          _selectedImagePath = null;
          _selectedFilePath = null;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
        });
      } else {
        setState(() {
          _selectedImagePath = picked.path;
          _selectedImageBytes = null;
          _selectedImageName = picked.name;
          _selectedFilePath = null;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка выбора изображения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    await _pickImageFromSource(ImageSource.gallery);
  }

  Future<void> _pickImageFromCamera() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Съемка с камеры недоступна в веб-версии'),
        ),
      );
      return;
    }
    await _pickImageFromSource(ImageSource.camera);
  }

  Future<void> _pickVideoFromSource(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: source);
      if (picked == null) return;

      final pickedName = picked.name.trim().isNotEmpty
          ? picked.name
          : (source == ImageSource.camera ? 'video.mp4' : 'video');

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return;
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFilePath = null;
          _selectedFileName = pickedName;
          _selectedFileSize = bytes.length;
          _selectedImagePath = null;
          _selectedImageBytes = null;
          _selectedImageName = null;
        });
      } else {
        final length = await picked.length();
        setState(() {
          _selectedFilePath = picked.path;
          _selectedFileBytes = null;
          _selectedFileName = pickedName;
          _selectedFileSize = length;
          _selectedImagePath = null;
          _selectedImageBytes = null;
          _selectedImageName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка выбора видео: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    await _pickVideoFromSource(ImageSource.gallery);
  }

  Future<void> _pickVideoFromCamera() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Съёмка с камеры недоступна в веб-версии'),
        ),
      );
      return;
    }
    await _pickVideoFromSource(ImageSource.camera);
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: kIsWeb,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      setState(() {
        _selectedFileName = file.name;
        _selectedFileSize = file.size;
        if (kIsWeb) {
          _selectedFileBytes = file.bytes;
          _selectedFilePath = null;
        } else {
          _selectedFilePath = file.path;
          _selectedFileBytes = null;
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Ошибка выбора файла: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Не удалось выбрать файл'),
        ),
      );
    }
  }

  /// Обработка перетаскивания файлов (drag-and-drop). Вызывается только onDragDone — без оверлея, чтобы не перекрывать чат.
  Future<void> _handleFilesDropped(DropDoneDetails details) async {
    if (_isRecordingVoice || _isUploadingImage || _isUploadingFile) return;
    final items = details.files;
    if (items.isEmpty) return;
    final DropItem fileItem = items.firstWhere(
      (item) => item is! DropItemDirectory,
      orElse: () => items.first,
    );
    if (fileItem is DropItemDirectory) return;
    try {
      final bytes = await fileItem.readAsBytes();
      final fileName = fileItem.name;
      if (bytes.isEmpty) return;
      final parts = fileName.toLowerCase().split('.');
      final ext = parts.length > 1 ? parts.last : '';
      final imageExtensions = [
        'jpg',
        'jpeg',
        'jpe',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'bmp',
        'tiff',
        'tif',
        'avif',
        'ico',
        'svg',
      ];
      if (imageExtensions.contains(ext)) {
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImagePath = null;
          _selectedImageName = fileName;
          _selectedFilePath = null;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
        });
      } else {
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFilePath = null;
          _selectedFileName = fileName;
          _selectedFileSize = bytes.length;
          _selectedImagePath = null;
          _selectedImageBytes = null;
          _selectedImageName = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Файл добавлен: $fileName'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка при добавлении файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024.0;
    return '${gb.toStringAsFixed(1)} GB';
  }

  /// Сжатие изображения для уменьшения размера файла и использования памяти
  ///
  /// [imageBytes] - оригинальные байты изображения
  /// [maxWidth] - максимальная ширина (по умолчанию 2560px для лучшего качества)
  /// [quality] - качество JPEG (0-100, по умолчанию 92 для высокого качества)
  ///
  /// Возвращает сжатые байты изображения
  Future<Uint8List> _compressImage(
    Uint8List imageBytes, {
    int maxWidth = 2560,
    int quality = 92,
  }) async {
    try {
      // Декодируем изображение
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        if (kDebugMode) {
          debugPrint(
            '⚠️  Не удалось декодировать изображение, возвращаем оригинал',
          );
        }
        return imageBytes;
      }

      // Вычисляем новый размер с сохранением пропорций
      int newWidth = originalImage.width;
      int newHeight = originalImage.height;

      if (originalImage.width > maxWidth) {
        newHeight = (originalImage.height * maxWidth / originalImage.width)
            .round();
        newWidth = maxWidth;
      }

      // Если изображение уже меньше maxWidth, не изменяем размер
      if (newWidth == originalImage.width &&
          newHeight == originalImage.height) {
        // Просто перекодируем с качеством для уменьшения размера
        final compressedBytes = Uint8List.fromList(
          img.encodeJpg(originalImage, quality: quality),
        );

        final savedBytes = imageBytes.length - compressedBytes.length;
        if (savedBytes > 0 && kDebugMode) {
          debugPrint(
            '📦 Сжатие (качество): ${imageBytes.length} → ${compressedBytes.length} байт (${(savedBytes / imageBytes.length * 100).toStringAsFixed(1)}% меньше)',
          );
        }
        return compressedBytes;
      }

      // Изменяем размер
      final resizedImage = img.copyResize(
        originalImage,
        width: newWidth,
        height: newHeight,
      );

      // Кодируем обратно в JPEG с качеством
      final compressedBytes = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: quality),
      );

      final savedBytes = imageBytes.length - compressedBytes.length;
      final savedPercent = (savedBytes / imageBytes.length * 100)
          .toStringAsFixed(1);
      if (kDebugMode) {
        debugPrint(
          '📦 Сжатие изображения: ${imageBytes.length} → ${compressedBytes.length} байт ($savedPercent% меньше, ${originalImage.width}x${originalImage.height} → ${newWidth}x$newHeight)',
        );
      }

      return compressedBytes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️  Ошибка сжатия изображения: $e, возвращаем оригинал');
      }
      return imageBytes; // Возвращаем оригинал при ошибке
    }
  }

  /// Скачивание изображения
  Future<void> _downloadImage(String imageUrl, String fileName) async {
    try {
      final url = Uri.parse(imageUrl);
      if (await canLaunchUrl(url)) {
        // Открываем изображение в браузере/приложении для просмотра
        // Пользователь может сохранить его через контекстное меню
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                kIsWeb
                    ? 'Изображение открыто в новой вкладке. Используйте "Сохранить как..." для скачивания.'
                    : 'Изображение открыто для просмотра',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Не удалось открыть URL');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка скачивания: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isUploadingImage || _isUploadingFile) return;
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'Голосовые сообщения пока не поддерживаются в веб-версии',
          ),
        ),
      );
      return;
    }
    if (_isRecordingVoice) {
      await _stopAndSendVoiceRecording();
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecordingIfNotRecording() async {
    if (_isRecordingVoice) return;
    await _startVoiceRecording();
  }

  Future<void> _stopAndSendVoiceRecordingIfRecording() async {
    if (!_isRecordingVoice) return;
    await _stopAndSendVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (!mounted) return;
    // на всякий: не даём начать при выбранных вложениях
    if (_selectedImagePath != null ||
        _selectedImageBytes != null ||
        _selectedFilePath != null ||
        _selectedFileBytes != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'Сначала отправьте/уберите вложение, затем запишите голосовое',
          ),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'Нет доступа к микрофону. Разрешите доступ в настройках.',
          ),
        ),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _voiceRecordTempPath = path;

    await _voiceRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _voiceRecordTimer?.cancel();
    setState(() {
      _isRecordingVoice = true;
      _voiceRecordDuration = Duration.zero;
    });
    _voiceRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _voiceRecordDuration += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _cancelVoiceRecording() async {
    HapticFeedback.lightImpact();
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;

    try {
      await _voiceRecorder.stop();
    } catch (_) {}

    final tmp = _voiceRecordTempPath;
    _voiceRecordTempPath = null;
    if (tmp != null) {
      try {
        final f = File(tmp);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _voiceRecordDuration = Duration.zero;
    });
  }

  Future<void> _stopAndSendVoiceRecording() async {
    HapticFeedback.mediumImpact();
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;

    String? recordedPath;
    try {
      recordedPath = await _voiceRecorder.stop();
    } catch (_) {}

    final tmp = recordedPath ?? _voiceRecordTempPath;
    _voiceRecordTempPath = null;

    if (tmp == null || tmp.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordDuration = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Не удалось сохранить запись'),
        ),
      );
      return;
    }

    try {
      final file = File(tmp);
      final bytes = await file.readAsBytes();
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Убираем режим записи + подставляем файл как вложение и отправляем обычным путём.
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordDuration = Duration.zero;

        _selectedFileBytes = bytes;
        _selectedFileName = name;
        _selectedFileSize = bytes.length;
        _selectedFilePath = null;
      });

      // Удаляем временный файл — дальше работаем с bytes.
      try {
        await file.delete();
      } catch (_) {}

      await _sendMessage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordDuration = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Ошибка записи: $e'),
        ),
      );
    }
  }

  Future<void> _toggleVoicePlayback(Message msg) async {
    final url = msg.fileUrl;
    if (url == null || url.isEmpty) return;

    HapticFeedback.lightImpact();

    final same = _voicePlayingMessageId == msg.id;
    try {
      if (same && _voiceIsPlaying) {
        await _voicePlayer.pause();
        return;
      }

      if (!same) {
        setState(() {
          _voicePlayingMessageId = msg.id;
          _voicePosition = Duration.zero;
          _voiceDuration = null;
        });
        await _voicePlayer.setUrl(url);
      }

      await _voicePlayer.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voicePlayingMessageId = null;
        _voicePosition = Duration.zero;
        _voiceDuration = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            'Не удалось воспроизвести аудио: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Widget _buildVoiceBubble(Message msg, {required bool isMine}) {
    final isCurrent = _voicePlayingMessageId == msg.id;
    final dur = isCurrent ? (_voiceDuration ?? Duration.zero) : Duration.zero;
    final pos = isCurrent ? _voicePosition : Duration.zero;
    final isBusy =
        isCurrent &&
        (_voiceProcessingState == ProcessingState.loading ||
            _voiceProcessingState == ProcessingState.buffering);
    final showPlaying = isCurrent && _voiceIsPlaying;

    return ChatVoiceBubble(
      isMine: isMine,
      isBusy: isBusy,
      showPlaying: showPlaying,
      position: pos,
      totalDuration: dur,
      onPlayPause: () => _toggleVoicePlayback(msg),
      onPositionDrag: isCurrent
          ? (v) {
              setState(() {
                _voicePosition = Duration(milliseconds: v.toInt());
              });
            }
          : null,
      onSeekEnd: isCurrent
          ? (v) async {
              try {
                await _voicePlayer.seek(Duration(milliseconds: v.toInt()));
              } catch (_) {}
            }
          : null,
    );
  }
}
