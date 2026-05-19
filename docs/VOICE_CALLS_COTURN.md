# Голосовые звонки: push и coturn на ВМ

Краткая инструкция для **reollity / my_chat_app** на Yandex Cloud (ВМ `chat-server`).

---

## 1. Push при входящем звонке

### Как работает

1. Звонящий шлёт `call_invite` по WebSocket.
2. Сервер пересылает invite собеседнику и отправляет **FCM** (`type: incoming_call`).
3. Если приложение в фоне или закрыто — пользователь видит push «Входящий звонок».
4. По тапу открывается экран звонка; при принятии идёт `call_accept` и WebRTC.

### Что нужно на сервере

Уже должны быть настроены Firebase credentials (как для сообщений):

- `FIREBASE_SERVICE_ACCOUNT_PATH` или `FIREBASE_SERVICE_ACCOUNT_JSON`, или
- `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY`

После деплоя бэкенда с новым кодом:

```bash
cd ~/my_chat_app/my_serve_chat_test
pm2 restart chat-server
pm2 logs chat-server --lines 50
```

В логах при звонке без FCM у собеседника: `incoming_call_push_skipped` / `no_token`.

### Что нужно в приложении

- Пользователь **разрешил уведомления**.
- После логина приложение отправило FCM-токен (`POST /auth/fcm-token`).
- Собрана **новая** версия iOS/Android с каналом `voice_calls`.

### Ограничения

- **iOS:** обычный push, не VoIP PushKit — в фоне звонок может не «звонить» так громко, как телефонный; нужен тап по уведомлению.
- **Web:** звонки и push не поддерживаются.
- Если звонок старше **5 минут** на сервере — сессия сбрасывается, принять не получится.

---

## 2. coturn (TURN) на той же ВМ

Нужен, когда два устройства **не могут соединиться напрямую** (разные сети, жёсткий NAT). Без TURN часть звонков обрывается на «Соединение…».

### Шаг 1. Узнать публичный IP ВМ

В консоли Yandex Cloud или на ВМ:

```bash
curl -s ifconfig.me
# например: 93.77.185.6
```

Дальше подставьте его вместо `YOUR_PUBLIC_IP`.

### Шаг 2. Установка (автоматически)

На ВМ из репозитория:

```bash
cd ~/my_chat_app
export TURN_PUBLIC_IP=YOUR_PUBLIC_IP
export TURN_SECRET='длинный-случайный-секрет-минимум-32-символа'
sudo -E ./scripts/setup-coturn-on-vm.sh
```

Скрипт:

- ставит `coturn`;
- пишет `/etc/turnserver.conf`;
- открывает firewall (ufw), если включён;
- выводит строки для `.env` Node.

### Шаг 3. Порты в Yandex Cloud

**Сеть → Группа безопасности** ВМ `chat-server` — входящие:

| Протокол | Порт | Назначение |
|----------|------|------------|
| UDP | 3478 | STUN/TURN |
| TCP | 3478 | TURN (TCP fallback) |
| UDP | 49152–49252 | relay (диапазон в скрипте, можно сузить) |

### Шаг 4. Переменные в `my_serve_chat_test/.env`

```env
WEBRTC_STUN_URLS=stun:stun.l.google.com:19302,stun:YOUR_PUBLIC_IP:3478
WEBRTC_TURN_URL=turn:YOUR_PUBLIC_IP:3478?transport=udp
WEBRTC_TURN_USERNAME=reollity
WEBRTC_TURN_CREDENTIAL=тот-же-TURN_SECRET-что-в-coturn
```

Перезапуск API:

```bash
pm2 restart chat-server
```

Клиент подхватывает ICE при звонке с `GET /calls/ice-servers` (с JWT).

### Шаг 5. Проверка coturn

На ВМ:

```bash
sudo systemctl status coturn
sudo turnutils_uclient -v -u reollity -w "$TURN_SECRET" YOUR_PUBLIC_IP
```

Успех — в выводе `allocate` / relay.

### Ресурсы ВМ (2 vCPU, 2 GB)

Для **нескольких** одновременных голосовых звонков coturn на той же ВМ обычно достаточно (~50–100 MB RAM). Следите:

```bash
htop
```

Если CPU/RAM в пиках — вынесите coturn на отдельную мини-ВМ или увеличьте конфиг.

### Безопасность

- `TURN_SECRET` — только в `.env` на сервере и в `turnserver.conf`, не коммитить.
- Не открывайте coturn в интернет без `use-auth-secret` / `lt-cred-mech` (скрипт включает).

---

## 3. Чеклист после настройки

- [ ] Деплой бэкенда + `pm2 restart`
- [ ] У обоих тестовых пользователей есть FCM-токен (залогиниться в приложении)
- [ ] Звонок **личный чат** → кнопка телефона
- [ ] Тест: приложение у B **свёрнуто** → приходит push
- [ ] Тест: звонок соединяется (если нет — добавить coturn и порты UDP)
- [ ] В `.env` заданы `WEBRTC_TURN_*` после установки coturn

---

## Связанные файлы

| Файл | Назначение |
|------|------------|
| `my_serve_chat_test/websocket/callSignaling.js` | Сигналинг + вызов push |
| `my_serve_chat_test/utils/pushNotifications.js` | `sendIncomingCallPushToUser` |
| `lib/services/push_notification_service.dart` | Обработка `incoming_call` |
| `lib/services/voice_call_service.dart` | WebRTC + `applyIncomingFromPush` |
| `scripts/setup-coturn-on-vm.sh` | Установка coturn |
