#!/usr/bin/env bash
# Один запуск с Mac: заливает код на ВМ и настраивает HTTPS для reollity.duckdns.org.
# Требуется: порты 80 и 443 открыты в Yandex Cloud для ВМ.
# Запуск: ./scripts/setup-https-reollity-from-mac.sh
set -e

VM="ubuntu@93.77.185.6"
DOMAIN="reollity.duckdns.org"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_KEY="$SCRIPT_DIR/.deploy_key"

if [ ! -f "$SSH_KEY" ]; then
  echo "Нет ключа $SSH_KEY."
  exit 1
fi
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=accept-new"

echo "=== Заливка кода на ВМ ==="
rsync -avz --exclude node_modules --exclude '.env' --exclude '.git' -e "ssh $SSH_OPTS" \
  "$REPO_ROOT/" "$VM:~/my_chat_app/"

echo ""
echo "=== Запуск настройки HTTPS на ВМ (DOMAIN=$DOMAIN) ==="
ssh $SSH_OPTS "$VM" "cd ~/my_chat_app && chmod +x scripts/setup-https-on-vm.sh && sudo DOMAIN=$DOMAIN ./scripts/setup-https-on-vm.sh"

echo ""
echo "Проверка: curl -s https://$DOMAIN/healthz"
