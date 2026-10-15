# Исправленная конфигурация деплоя

## Проблема
Оба workflow деплоили на один сервер 129.101.115.158, но должно быть:
- **Web (Flutter)** → `93.183.80.97`
- **Backend (Node.js)** → `129.101.115.158`

## Что исправлено

### 1. Workflows переименованы и разделены

**Было:**
- `.github/workflows/deploy-web-reollity.yml` → деплой на 129.101.115.158
- `.github/workflows/deploy-yandex-vm.yml` → деплой на 129.101.115.158

**Стало:**
- `.github/workflows/deploy-web-93.yml` → деплой **web** на **93.183.80.97**
- `.github/workflows/deploy-backend-129.yml` → деплой **backend** на **129.101.115.158**

### 2. Web workflow (deploy-web-93.yml)

```yaml
name: Deploy web to 93.183.80.97
```

- SSH key: `WEB_SERVER_KEY` (secrets)
- Деплой: `rsync build/web/ → root@93.183.80.97:/var/www/reollity/`
- Smoke test: проверка index.html и canvaskit на 93.183.80.97

### 3. Backend workflow (deploy-backend-129.yml)

```yaml
name: Deploy backend to 129.101.115.158
```

- SSH key: `REOLLITY_RECOVERY_KEY` (secrets)
- Деплой: `rsync my_serve_chat_test/ → root@129.101.115.158:/opt/reollity/backend/`
- Рестарт: `systemctl restart reollity-chat.service`
- Smoke test: healthz на 129.101.115.158:3100 + api.reollity.ru

## Что нужно сделать

### 1. Добавить GitHub Secret

В GitHub: **Settings → Secrets and variables → Actions → New repository secret**

```
Name: WEB_SERVER_KEY
Value: <приватный SSH-ключ для root@93.183.80.97>
```

### 2. Настроить DNS (если нужны домены)

Сейчас DNS возвращает странные IP:
- `reollity.ru` → 240.0.0.22
- `api.reollity.ru` → 240.0.0.59

**Правильная конфигурация:**

```dns
reollity.ru         A    93.183.80.97
api.reollity.ru     A    129.101.115.158
```

### 3. Альтернатива: использовать прямые IP

Если не хочешь настраивать DNS, измени build command в `deploy-web-93.yml`:

```yaml
- name: Build web
  run: |
    flutter pub get
    flutter build web --release --no-wasm-dry-run --no-web-resources-cdn \
      --dart-define=API_BASE_URL=http://129.101.115.158:3100
```

**Важно:** Убедись что backend слушает на `0.0.0.0:3100`, а не `127.0.0.1:3100`.

### 4. Проверь firewall на серверах

**На 93.183.80.97 (web):**
```bash
# Должен быть открыт порт 80 или 443
sudo ufw allow 80
sudo ufw allow 443
```

**На 129.101.115.158 (backend):**
```bash
# Должен быть открыт порт 3100 (или настроен через Nginx reverse proxy)
sudo ufw allow 3100
```

## Проверка после деплоя

1. **Закоммить изменения:**
```bash
git add .github/workflows/
git commit -m "fix: separate web and backend deployment to different servers"
git push origin main
```

2. **Проверить Actions:**
   - Web должен деплоиться на 93.183.80.97
   - Backend должен деплоиться на 129.101.115.158

3. **Открыть в браузере:**
   - Web: `http://93.183.80.97` или `https://reollity.ru` (если DNS настроен)
   - API: `http://129.101.115.158:3100/healthz` или `https://api.reollity.ru/healthz`

## Структура серверов

```
┌─────────────────────────┐
│   93.183.80.97          │
│   (web server)          │
│                         │
│   /var/www/reollity/    │
│   - index.html          │
│   - flutter_bootstrap.js│
│   - canvaskit/          │
│   - ...                 │
└─────────────────────────┘
          │
          │ HTTP requests
          ▼
┌─────────────────────────┐
│   129.101.115.158       │
│   (backend server)      │
│                         │
│   /opt/reollity/backend/│
│   - index.js            │
│   - controllers/        │
│   - routes/             │
│                         │
│   systemd service:      │
│   reollity-chat.service │
│   Port: 3100            │
└─────────────────────────┘
```

## Статус

✅ Workflows разделены и переименованы  
⚠️ Нужно добавить `WEB_SERVER_KEY` в GitHub Secrets  
⚠️ Нужно проверить DNS настройки или использовать прямые IP  
⚠️ Нужно проверить firewall на обоих серверах  
