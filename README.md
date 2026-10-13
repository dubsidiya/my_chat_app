# reollity

Flutter-приложение: чат
Клиент для бэкенда (Node.js + PostgreSQL).

## Стек

- **Клиент:** Flutter (iOS, Android, Web)
- **Бэкенд:** `my_serve_chat_test/` — Node.js, Express, PostgreSQL, WebSocket
- **Сервисы:** Firebase (push), Hive (кэш сообщений), secure storage (токен)

## Запуск

```bash
# Клиент
flutter pub get
flutter run

# Бэкенд (из корня проекта)
cd my_serve_chat_test && npm install && npm run dev
```

Web: `flutter run -d chrome`. Сборка: `flutter build web` / `flutter build apk` / `flutter build ios`.

## Конфиг

- API: `lib/config/api_config.dart` (или `--dart-define=API_BASE_URL=https://...`).
- Web-заголовок и PWA: `web/index.html`, `web/manifest.json`.
- **Production:** web размещён на `reollity.ru`, Node.js API — на `api.reollity.ru`, база данных — Timeweb PostgreSQL. Актуальные команды подключения и деплоя находятся в `recovered-backup-20261013/server-config/` (эта папка локальная и исключена из Git).

## Документация

- [Идеи и оптимизация](docs/FUTURE_AND_OPTIMIZATION.md) — что уже сделано и что можно добавить.
- Остальные гайды в `docs/`.
