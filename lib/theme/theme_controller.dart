import 'package:flutter/foundation.dart';

import 'app_colors.dart';
import 'theme_variant.dart';
import '../services/storage_service.dart';

/// Глобальный контроллер темы. Хранит активный [AppThemeVariant] и оповещает
/// слушателей об изменениях. Используется в `main.dart` для перестроения
/// MaterialApp при смене темы.
///
/// Сохранение/восстановление выбора пользователя выполняется через
/// [StorageService].
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  AppThemeVariant _variant = AppThemeVariant.ultravioletDark;

  /// Текущий вариант. Совпадает с [AppColors.activeVariant].
  AppThemeVariant get variant => _variant;

  /// Загружает выбранную тему из локального хранилища (вызывать на старте).
  Future<void> loadFromStorage() async {
    final raw = await StorageService.getThemeVariantRaw();
    final loaded = appThemeVariantFromStorage(raw);
    _applyVariant(loaded, persist: false);
  }

  /// Меняет тему и сохраняет выбор в локальное хранилище.
  Future<void> setVariant(AppThemeVariant variant) async {
    if (_variant == variant) return;
    _applyVariant(variant, persist: true);
  }

  void _applyVariant(AppThemeVariant variant, {required bool persist}) {
    _variant = variant;
    AppColors.setActiveVariant(variant);
    notifyListeners();
    if (persist) {
      // fire-and-forget: ошибки сохранения не блокируют UI.
      // Логику записи берёт на себя StorageService.
      StorageService.setThemeVariantRaw(variant.storageKey);
    }
  }
}
