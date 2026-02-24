#!/usr/bin/env bash
# Запуск на ВМ Yandex (Ubuntu 22.04). Выполнять от обычного пользователя (ubuntu).
# Использование:
#   1. Скопируй проект на ВМ (git clone или rsync).
#   2. cd /path/to/my_chat_app && ./scripts/setup-server-on-yandex-vm.sh
#   3. Перед первым запуском задай переменные (или создай my_serve_chat_test/.env вручную):
#      export DATABASE_URL='postgresql://...'   # Yandex
#      export JWT_SECRET='...'                  # не короче 32 символов
#      export ALLOWED_ORIGINS='https://my-chat-app.vercel.app,...'
#      export YANDEX_ACCESS_KEY_ID=...          # если есть Object Storage
#      export YANDEX_SECRET_ACCESS_KEY=...
#      export YANDEX_BUCKET_NAME=mychatimage
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/my_serve_chat_test"

if [ ! -f "$APP_DIR/package.json" ]; then
  echo "Ошибка: не найден $APP_DIR/package.json. Запускай скрипт из корня репозитория."
  exit 1
fi

echo "=== 1/4 Установка Node.js 20 LTS (если ещё нет) ==="
if ! command -v node &>/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 18 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
node -v
npm -v

echo ""
echo "=== 2/4 Установка зависимостей ==="
cd "$APP_DIR"
npm ci 2>/dev/null || npm install

echo ""
echo "=== 3/4 Файл .env ==="
if [ ! -f "$APP_DIR/.env" ]; then
  if [ -z "$DATABASE_URL" ] || [ -z "$JWT_SECRET" ]; then
    echo "Создай $APP_DIR/.env с переменными: DATABASE_URL, JWT_SECRET (≥32 символов), ALLOWED_ORIGINS."
    echo "Пример (подставь свои значения):"
    echo "  NODE_ENV=production"
    echo "  PORT=3000"
    echo "  DATABASE_URL=postgresql://chat_app:PASSWORD@rc1a-....mdb.yandexcloud.net:6432/chat_db"
    echo "  JWT_SECRET=твой_секрет_не_короче_32_символов"
    echo "  ALLOWED_ORIGINS=https://my-chat-app.vercel.app,http://localhost:3000"
    echo "  YANDEX_ACCESS_KEY_ID=..."
    echo "  YANDEX_SECRET_ACCESS_KEY=..."
    echo "  YANDEX_BUCKET_NAME=mychatimage"
    exit 1
  fi
  cat > "$APP_DIR/.env" << EOF
NODE_ENV=production
PORT=3000
DATABASE_URL=$DATABASE_URL
JWT_SECRET=$JWT_SECRET
ALLOWED_ORIGINS=${ALLOWED_ORIGINS:-https://my-chat-app.vercel.app,http://localhost:3000}
EOF
  [ -n "$YANDEX_ACCESS_KEY_ID" ] && echo "YANDEX_ACCESS_KEY_ID=$YANDEX_ACCESS_KEY_ID" >> "$APP_DIR/.env"
  [ -n "$YANDEX_SECRET_ACCESS_KEY" ] && echo "YANDEX_SECRET_ACCESS_KEY=$YANDEX_SECRET_ACCESS_KEY" >> "$APP_DIR/.env"
  [ -n "$YANDEX_BUCKET_NAME" ] && echo "YANDEX_BUCKET_NAME=$YANDEX_BUCKET_NAME" >> "$APP_DIR/.env"
  echo "Создан .env из переменных окружения."
else
  echo "Файл .env уже есть."
fi

echo ""
echo "=== 4/4 Запуск сервера ==="
echo "Сервер будет слушать порт \${PORT:-3000}. Для выхода: Ctrl+C."
echo "Чтобы запускать в фоне и при перезагрузке — установи pm2: npm i -g pm2 && pm2 start index.js --name chat-server"
cd "$APP_DIR"
exec npm start
