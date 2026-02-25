import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';

/// Результат проверки версии приложения.
enum VersionCheckResult {
  /// Версия актуальна.
  upToDate,
  /// Доступно обновление (рекомендуется, но не блокируем).
  updateAvailable,
  /// Требуется обязательное обновление (ниже minVersion).
  updateRequired,
}

class VersionCheckInfo {
  final VersionCheckResult result;
  final String? message;
  final String? storeUrlAndroid;
  final String? storeUrlIos;

  const VersionCheckInfo({
    required this.result,
    this.message,
    this.storeUrlAndroid,
    this.storeUrlIos,
  });
}

/// Сервис проверки версии приложения: запрашивает с бэкенда min/latest версию
/// и сравнивает с текущей. Показывает диалог «Обновите приложение» при необходимости.
class VersionCheckService {
  static const String _versionPath = '/version';

  /// Сравнение версий в формате "1.0.0". Возвращает: < 0 если a < b, 0 если a == b, > 0 если a > b.
  static int _compareVersions(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    for (int i = 0; i < 3; i++) {
      final ai = i < aParts.length ? aParts[i] : 0;
      final bi = i < bParts.length ? bParts[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  static List<int> _parseVersion(String v) {
    final s = v.split('+').first.trim();
    return s.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  /// Запросить с бэкенда данные о версии и сравнить с текущей.
  /// При ошибке сети возвращает null (не блокируем пользователя).
  static Future<VersionCheckInfo?> check() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final uri = Uri.parse('${ApiConfig.baseUrl}$_versionPath');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('timeout'),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      if (data == null) return null;
      final minVersion = data['minVersion'] as String? ?? '0.0.0';
      final latestVersion = data['latestVersion'] as String? ?? minVersion;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final message = data['message'] as String? ?? 'Доступна новая версия приложения. Обновите для корректной работы.';
      final storeUrlAndroid = data['storeUrlAndroid'] as String?;
      final storeUrlIos = data['storeUrlIos'] as String?;

      final belowMin = _compareVersions(currentVersion, minVersion) < 0;
      final belowLatest = _compareVersions(currentVersion, latestVersion) < 0;

      if (belowMin) {
        return VersionCheckInfo(
          result: VersionCheckResult.updateRequired,
          message: message,
          storeUrlAndroid: storeUrlAndroid,
          storeUrlIos: storeUrlIos,
        );
      }
      if (belowLatest && forceUpdate) {
        return VersionCheckInfo(
          result: VersionCheckResult.updateRequired,
          message: message,
          storeUrlAndroid: storeUrlAndroid,
          storeUrlIos: storeUrlIos,
        );
      }
      if (belowLatest) {
        return VersionCheckInfo(
          result: VersionCheckResult.updateAvailable,
          message: message,
          storeUrlAndroid: storeUrlAndroid,
          storeUrlIos: storeUrlIos,
        );
      }
      return const VersionCheckInfo(result: VersionCheckResult.upToDate);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('VersionCheckService: $e');
      }
      return null;
    }
  }

  /// Показать диалог по результату проверки. Вызывать после check() когда есть context.
  static Future<void> showDialogIfNeeded(BuildContext context, VersionCheckInfo? info) async {
    if (info == null || info.result == VersionCheckResult.upToDate) return;
    if (!context.mounted) return;

    if (info.result == VersionCheckResult.updateRequired) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Требуется обновление'),
          content: Text(info.message ?? 'Для продолжения работы обновите приложение до последней версии.'),
          actions: [
            TextButton(
              onPressed: () => _openStore(context, info),
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
      return;
    }

    if (info.result == VersionCheckResult.updateAvailable) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Доступна новая версия'),
          content: Text(info.message ?? 'Рекомендуем обновиться для получения новых возможностей и исправлений.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openStore(context, info);
              },
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }
  }

  static Future<void> _openStore(BuildContext context, VersionCheckInfo info) async {
    final uri = _storeUri(info);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Uri? _storeUri(VersionCheckInfo info) {
    if (defaultTargetPlatform == TargetPlatform.iOS && info.storeUrlIos != null) {
      return Uri.tryParse(info.storeUrlIos!);
    }
    if (info.storeUrlAndroid != null) return Uri.tryParse(info.storeUrlAndroid!);
    if (info.storeUrlIos != null) return Uri.tryParse(info.storeUrlIos!);
    return null;
  }
}
