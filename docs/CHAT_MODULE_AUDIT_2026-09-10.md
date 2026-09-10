# Аудит модуля чата — 2026-09-10

Симптом: новый аккаунт в **Edge/Chrome на Windows** (Flutter web) набирает текст, сообщение не уходит. В БД чат создаётся, ключ есть, чужие сообщения пишутся, `POST /messages` от этого пользователя нет.

## Как устроен модуль

| Слой | Файлы |
|------|--------|
| UI чата | `lib/screens/chat_screen.dart` + parts (`*_send`, `*_queue`, `*_websocket`, `*_media_voice`) |
| Поле ввода | `lib/widgets/chat_input_bar.dart` |
| HTTP | `lib/services/messages_service.dart` → `POST {API}/messages` |
| Ключ чата | `lib/services/chat_key_service.dart` → `GET /chats/:id/key` (это **не** E2EE; ключ на сервере) |
| WS | `lib/services/websocket_service.dart` — доставка/typing, **не** отправка текста |
| Сервер | `messagesController.sendMessage`, `routes/messages/writeRoutes.js` |

Цепочка отправки текста: кнопка/Enter → `_sendMessage` → optimistic `temp_*` → `encryptText` (опционально) → `POST /messages` → 201.

## Почему Edge «не отправляет»

Проверено по БД и коду. Запрос **не доходит до INSERT** (нет строки и скорее всего нет лога `📨 sendMessage`).

1. **Enter на Flutter web** — поле `maxLines: 6`. Enter уходит в нативный `<textarea>` (новая строка). `Focus.onKeyEvent` в Edge часто **не вызывается**. Человек жмёт Enter — Dart не видит send.
2. **Клик «Отправить»** — Flutter web кладёт HTML-оверлей поверх `TextField`. На Windows (масштаб 125–150%) оверлей наезжает на соседние кнопки. Клик не доходит до `IconButton`.
3. **Шифрование до POST** — `await encryptText` без таймаута. WebCrypto в Edge может зависнуть → `_isSendingMessage = true` навсегда, кнопка превращается в спиннер, повторные клики молча игнорируются.
4. **Drop файла** — `desktop_drop` на вебе делает `webkitGetAsEntry()!`. В Edge для файлов с рабочего стола это часто `null`. DropDone ещё отсекается, если координаты «мимо» виджета.
5. **Helmet CORP `same-origin`** на API — лишний риск для кросс-origin POST из Vercel в Edge. GET `/chats` при этом уже мог проходить.
6. **Кэш PWA / service worker** на Vercel — после деплоя Edge может крутить старый `main.dart.js`.

Не причина для этого симптома: права участника чата, `token_version` нового юзера, парсер зашифрованного JSON, отсутствие `Idempotency-Key` в CORS (на проде заголовок уже разрешён), Firebase (на web не инициализируется).

## Что сделано в коде (нужен новый деплой)

Клиент (Vercel):

- Enter на web: capture `keydown` на `document` (`lib/utils/web_composer_enter_web.dart`). Shift+Enter = новая строка.
- Кнопка отправки и «+» обёрнуты в `PointerInterceptor` (клик поверх HTML-оверлея).
- `encryptText` ограничен 3 секундами — дальше уходит plaintext, POST не блокируется.
- Drop на web через `dataTransfer.files`, не через `webkitGetAsEntry`.

Сервер (нужен рестарт API, не только Vercel):

- Helmet `crossOriginResourcePolicy: cross-origin`.

## Как проверить после выкладки

1. Vercel: дождаться нового билда. В Edge: Ctrl+Shift+R (лучше Application → Service Workers → Unregister).
2. API: `pm2 restart` (или как крутится Node), иначе CORP не сменится.
3. В чате: должен появиться пузырь `temp_*`, в Network — `POST https://reollity.duckdns.org/messages`.
4. Если POST красный — смотреть OPTIONS и `Access-Control-Allow-Origin`.
5. Если POST нет, а спиннер крутится — снова зависание до POST (писать).
6. Файл: либо drag, либо «+».
