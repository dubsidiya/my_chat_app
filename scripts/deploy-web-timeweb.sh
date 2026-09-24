#!/bin/bash
# Деплой веб-версии на Timeweb (reollity.ru) через Яндекс-VM (jump host).
#
# Использование: bash scripts/deploy-web-timeweb.sh
#
# Что делает:
#   1. Собирает Flutter web с API_BASE_URL=https://reollity.ru
#   2. Заливает через ubuntu@93.77.185.6 (jump) на root@93.183.80.97:/var/www/reollity
#   3. Проверяет, что сайт поднялся
#
# Требования: scripts/.deploy_key (Яндекс-VM), root-доступ к Timeweb (пароль
# хранится в scripts/.timeweb_pass или вводится вручную).
set -euo pipefail

API_URL="https://reollity.ru"
JUMP_USER="ubuntu"
JUMP_HOST="93.77.185.6"
JUMP_KEY="scripts/.deploy_key"
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

SSH_JUMP="ssh -i $JUMP_KEY -o BatchMode=yes -o ConnectTimeout=25 $JUMP_USER@$JUMP_HOST"

echo "🚀 [1/3] Сборка Flutter web (API_BASE_URL=$API_URL)..."
flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL="$API_URL"

echo "📦 [2/3] Заливка через jump host ($JUMP_HOST) → $TW_HOST:/var/www/reollity..."
$SSH_JUMP "mkdir -p /tmp/webapp"
rsync -az --delete -e "ssh -i $JUMP_KEY -o BatchMode=yes" build/web/ "$JUMP_USER@$JUMP_HOST:/tmp/webapp/"
$SSH_JUMP "sshpass -p '$TW_PASS' rsync -az --delete -e 'ssh -o StrictHostKeyChecking=accept-new' /tmp/webapp/ $TW_USER@$TW_HOST:$REMOTE_DIR/"

echo "✅ [3/3] Проверка сайта..."
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$API_URL/")
API=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -X POST -H 'Content-Type: application/json' -d '{}' "$API_URL/auth/login")
if [ "$HTTP" = "200" ] && [ "$API" = "400" ]; then
  echo "✅ Деплой успешен: $API_URL (сайт 200, API отвечает)."
else
  echo "⚠️  Сайт: $HTTP, API: $API — проверь вручную $API_URL"
  exit 1
fi
