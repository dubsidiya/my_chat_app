#!/usr/bin/env bash
# Всё в одном: копирует проект на ВМ, поднимает Node/deps, запускает сервер через pm2.
# Запуск с Mac: ./scripts/deploy-to-yandex-vm-now.sh
# Пароль ВМ запросится 3 раза (rsync, scp, ssh). Чтобы один раз: добавь ключ на ВМ:
#   ssh-copy-id ubuntu@93.77.185.6
# (пароль ВМ смотри в консоли Yandex: ВМ → Подключиться → «Указать пароль».)
set -e

VM="ubuntu@93.77.185.6"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="my_serve_chat_test"
ENV_FILE="$REPO_ROOT/$APP_DIR/env-yandex-vm.txt"
SSH_KEY="$SCRIPT_DIR/.deploy_key"

if [ ! -f "$ENV_FILE" ]; then
  echo "Нет файла $ENV_FILE. Создай env-yandex-vm.txt с переменными для ВМ."
  exit 1
fi
if [ ! -f "$SSH_KEY" ]; then
  echo "Нет ключа $SSH_KEY. Сгенерируй: ssh-keygen -t ed25519 -f scripts/.deploy_key -N '' -C deploy"
  exit 1
fi
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=accept-new"

echo "Проект: $REPO_ROOT"
echo "ВМ: $VM"
echo ""

# 1. Копируем только нужное для бэкенда (без Flutter/Android build и node_modules)
echo "=== 1/4 Копирование проекта на ВМ..."
rsync -avz \
  --exclude node_modules --exclude "$APP_DIR/node_modules" --exclude .git \
  --exclude build --exclude .dart_tool --exclude android/build --exclude ios/Pods --exclude ios/.symlinks \
  --exclude '*.iml' --exclude .metadata --exclude .packages \
  -e "ssh $SSH_OPTS" \
  "$REPO_ROOT/" "$VM:~/my_chat_app/"

# 2. Копируем .env
echo ""
echo "=== 2/4 Копирование .env на ВМ..."
scp $SSH_OPTS "$ENV_FILE" "$VM:~/my_chat_app/$APP_DIR/.env"

# 3 и 4. На ВМ: установка и запуск
echo ""
echo "=== 3/4 Установка Node и зависимостей на ВМ..."
echo "=== 4/4 Запуск сервера (pm2)..."
ssh $SSH_OPTS "$VM" "bash -s" << 'REMOTE'
set -e
cd ~/my_chat_app || exit 1
chmod +x scripts/setup-server-on-yandex-vm.sh 2>/dev/null || true

# Node 20 если нет
if ! command -v node &>/dev/null || [ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)" -lt 18 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

cd my_serve_chat_test
npm ci 2>/dev/null || npm install
npm i -g pm2 2>/dev/null || true
pm2 delete chat-server 2>/dev/null || true
pm2 start index.js --name chat-server
pm2 save
pm2 startup 2>/dev/null || true
echo ""
echo "Сервер запущен. Проверка: curl http://93.77.185.6:3000/healthz"
REMOTE

echo ""
echo "Готово. Проверь: curl http://93.77.185.6:3000/healthz"
