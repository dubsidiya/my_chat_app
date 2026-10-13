#!/bin/bash
# Деплой Flutter Web на Timeweb (reollity.ru) напрямую.
#
# Использование: bash scripts/deploy-web-timeweb.sh
#
# Что делает:
#   1. Собирает Flutter web с API_BASE_URL=https://api.reollity.ru
#   2. Загружает build/web на web-сервер Timeweb в /var/www/reollity
#   3. Проверяет доступность сайта.
#
# Требования: SSH-доступ root к web-серверу; пароль — в scripts/.timeweb_pass
# или будет запрошен интерактивно.
set -euo pipefail

API_URL="https://api.reollity.ru"
TW_HOST="93.183.80.97"
TW_USER="root"
REMOTE_DIR="/var/www/reollity"

cd "$(dirname "$0")/.."

# Пароль Timeweb: из файла или из stdin
PASS_FILE="scripts/.timeweb_pass"
if [ -f "$PASS_FILE" ]; then
  TW_PASS="$(cat "$PASS_FILE")"
else
  echo "Root-пароль Timeweb ($TW_HOST) не найден."
  echo "Создай файл $PASS_FILE с паролем (в .gitignore!), или введи сейчас:"
  read -r -s TW_PASS
  [ -n "$TW_PASS" ] || { echo "Пароль не введён — отмена."; exit 1; }
fi

SSH_WEB="ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 $TW_USER@$TW_HOST"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Нужен sshpass для передачи пароля. Установите его или настройте SSH-ключ для $TW_USER@$TW_HOST."
  exit 1
fi

SSH_PASS=(sshpass -p "$TW_PASS")

echo "🚀 [1/3] Сборка Flutter web (API_BASE_URL=$API_URL)..."
flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL="$API_URL"

echo "📦 [2/3] Загрузка на $TW_HOST:$REMOTE_DIR..."
"${SSH_PASS[@]}" $SSH_WEB "mkdir -p '$REMOTE_DIR'"
"${SSH_PASS[@]}" rsync -az --delete -e "ssh -o StrictHostKeyChecking=accept-new" build/web/ "$TW_USER@$TW_HOST:$REMOTE_DIR/"

echo "✅ [3/3] Проверка сайта и API..."
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://reollity.ru/")
API=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST -H 'Content-Type: application/json' -d '{}' "$API_URL/auth/login")
if [ "$HTTP" = "200" ] && [ "$API" = "400" ]; then
  echo "✅ Деплой успешен: сайт 200, API отвечает."
else
  echo "⚠️  Сайт: $HTTP, API: $API — проверь вручную."
  exit 1
fi
