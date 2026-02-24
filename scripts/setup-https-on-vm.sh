#!/usr/bin/env bash
# Настройка HTTPS для API на ВМ (Ubuntu 22.04) через Caddy.
# Caddy сам получает и обновляет сертификат Let's Encrypt.
#
# Требуется: домен (или поддомен), A-запись которого указывает на IP ВМ.
#
# Использование на ВМ:
#   export DOMAIN=api.твой-домен.ru
#   cd /path/to/my_chat_app && sudo ./scripts/setup-https-on-vm.sh
#
# Или одной строкой:
#   sudo DOMAIN=api.твой-домен.ru ./scripts/setup-https-on-vm.sh
#
# После выполнения: открой порты 80 и 443 в Yandex Cloud (Сеть → Группы безопасности ВМ).
# Затем в Vercel задай переменную API_BASE_URL=https://api.твой-домен.ru и пересобери проект.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$DOMAIN" ]; then
  echo "Ошибка: задай домен для API (должен указывать на IP этой ВМ)."
  echo "  export DOMAIN=api.твой-домен.ru"
  echo "  sudo -E ./scripts/setup-https-on-vm.sh"
  exit 1
fi

echo "=== Установка Caddy (обратный прокси + авто-HTTPS) ==="
if ! command -v caddy &>/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y caddy
fi
caddy version

echo "=== Конфиг Caddy для $DOMAIN → 127.0.0.1:3000 ==="
TMP_CADDY="$(mktemp)"
sed "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$SCRIPT_DIR/caddy-api.Caddyfile.template" > "$TMP_CADDY"
sudo cp "$TMP_CADDY" /etc/caddy/Caddyfile
rm -f "$TMP_CADDY"

echo "=== Запуск Caddy ==="
sudo systemctl enable caddy
sudo systemctl restart caddy
sudo systemctl status caddy --no-pager -l || true

echo ""
echo "✅ HTTPS настроен. API доступен по адресу: https://$DOMAIN"
echo ""
echo "Дальше:"
echo "  1. В Yandex Cloud открой для ВМ входящие порты 80 и 443 (Сеть → Группы безопасности)."
echo "  2. В Vercel: Settings → Environment Variables → API_BASE_URL = https://$DOMAIN"
echo "  3. Пересобери/задеплой проект на Vercel."
echo "  4. В my_serve_chat_test/.env на ВМ добавь в ALLOWED_ORIGINS твой фронт, например:"
echo "     ALLOWED_ORIGINS=https://my-chat-app.vercel.app,https://$DOMAIN"
echo "     Затем: pm2 restart chat-server"
