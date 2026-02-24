# Ошибка «XMLHttpRequest error» после перехода на Yandex VM

Если при логине или запросах к API появляется **XMLHttpRequest error**, чаще всего причина одна из двух.

---

## 1. Mixed content (страница HTTPS → API HTTP)

**Ситуация:** приложение открыто по **HTTPS** (например с Vercel: `https://my-chat-app.vercel.app`), а API на ВМ работает по **HTTP** (`http://93.77.185.6:3000`).  
Браузер **блокирует** такие запросы (безопасность mixed content), в результате — «XMLHttpRequest error».

### Что сделать

**Вариант А. Поднять API по HTTPS на ВМ (рекомендуется, один скрипт)**

В репозитории есть скрипт, который ставит **Caddy** и автоматически получает сертификат Let's Encrypt:

1. Домен (или поддомен) с **A-записью на IP ВМ** (93.77.185.6).
2. На ВМ: `sudo DOMAIN=api.твой-домен.ru ./scripts/setup-https-on-vm.sh`
3. В Yandex Cloud открой для ВМ порты **80** и **443**.
4. В Vercel задай переменную **API_BASE_URL** = `https://api.твой-домен.ru` и пересобери проект.

**Пошаговая инструкция с нуля (домен, порты, команды, Vercel):** [HTTPS_API_PO_SHAGAM.md](HTTPS_API_PO_SHAGAM.md).  
Кратко: [YANDEX_SERVER_MIGRATION.md](YANDEX_SERVER_MIGRATION.md) → шаг 5а.

**Вариант Б. Туннель с HTTPS (быстрая проверка)**

- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) или [ngrok](https://ngrok.com/): поднять туннель с HTTPS до `http://127.0.0.1:3000` на ВМ.
- В приложении временно указать этот HTTPS-URL как базовый API.

**Вариант В. Тест без mixed content**

- Запускать приложение по **HTTP**: например `flutter run -d chrome` (открывается `http://localhost:...`) — тогда запросы к `http://93.77.185.6:3000` не блокируются.
- Или раздавать веб-сборку по HTTP с своего сервера, а не с Vercel.

---

## 2. CORS или сервер недоступен

**Ситуация:** запрос доходит до сервера, но в ответе нет нужного `Access-Control-Allow-Origin`, либо сервер вообще не отвечает (не запущен, закрыт порт, другой IP).

### Что проверить

1. **Сервер на ВМ запущен и порт открыт**
   - На ВМ: `pm2 list` или `curl -s http://127.0.0.1:3000/healthz` → должен вернуть `ok`.
   - С твоего компьютера: `curl -s http://93.77.185.6:3000/healthz` → тоже `ok`. Если нет — проверь группу безопасности в Yandex Cloud (входящий порт 3000).

2. **ALLOWED_ORIGINS на ВМ**
   - В `my_serve_chat_test/.env` на ВМ задай:
     ```bash
     ALLOWED_ORIGINS=https://my-chat-app.vercel.app,http://localhost:3000,http://127.0.0.1:3000
     ```
   - Если используешь другой домен приложения — добавь его в список.
   - После изменения перезапусти сервер: `pm2 restart chat-server`.

3. **Логи на ВМ**
   - `pm2 logs chat-server` — нет ли ошибок при запросе на `/auth/login` и не пишет ли CORS об отклонённом origin.

---

## Кратко

| Откуда открыто приложение | Куда идут запросы | Результат |
|---------------------------|--------------------|-----------|
| **HTTPS** (Vercel)        | **HTTP** (93.77.185.6:3000) | Браузер блокирует → XMLHttpRequest error |
| **HTTP** (localhost)      | **HTTP** (93.77.185.6:3000) | Обычно работает, если CORS и порт настроены |

Итог: при использовании приложения с **Vercel (HTTPS)** нужно, чтобы API тоже был доступен по **HTTPS** (домен + nginx + SSL или туннель).
