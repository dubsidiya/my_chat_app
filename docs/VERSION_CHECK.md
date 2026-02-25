# Проверка версии приложения (пока не используется)

Функция «есть ли у пользователя последняя версия» реализована, но **сейчас отключена**, потому что приложение ещё не опубликовано в App Store и Google Play.

## Что уже есть в коде

- **Бэкенд:** `GET /version` — отдаёт `minVersion`, `latestVersion`, `forceUpdate`, `message`, ссылки на магазины. Параметры задаются через переменные окружения (см. `my_serve_chat_test/.env.example`, блок «Проверка версии приложения»).
- **Flutter:** сервис `lib/services/version_check_service.dart` — запрашивает `/version`, сравнивает с текущей версией из `package_info_plus`, показывает диалог «Требуется обновление» или «Доступна новая версия» с кнопкой в магазин.
- **Вызов отключён:** в `lib/screens/main_tabs_screen.dart` вызов проверки закомментирован.

## Как включить, когда приложение будет в сторе

1. В **`lib/screens/main_tabs_screen.dart`** раскомментировать блок в `initState`:
   - добавить импорт `import '../services/version_check_service.dart';`
   - раскомментировать второй `WidgetsBinding.instance.addPostFrameCallback` с `VersionCheckService.check()` и `showDialogIfNeeded`.

2. На **сервере** в `.env` задать (после публикации в магазинах):
   ```env
   APP_MIN_VERSION=1.0.0
   APP_LATEST_VERSION=1.0.0
   APP_STORE_URL_ANDROID=https://play.google.com/store/apps/details?id=ВАШ_PACKAGE
   APP_STORE_URL_IOS=https://apps.apple.com/app/idXXXXX
   ```
   При выходе новой версии — обновить `APP_LATEST_VERSION` (и при необходимости `APP_MIN_VERSION`) и перезапустить сервер.

3. Выполнить `flutter pub get` (зависимость `package_info_plus` уже в `pubspec.yaml`).

После этого при каждом входе пользователя в приложение будет запрос к `/version` и при устаревшей версии — диалог с предложением обновиться.
