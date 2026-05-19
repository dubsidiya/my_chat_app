#!/usr/bin/env bash
# Установка coturn (TURN) на Ubuntu 22.04 для голосовых звонков WebRTC.
#
# Использование на ВМ:
#   export TURN_PUBLIC_IP=93.77.185.6   # публичный IP этой ВМ
#   export TURN_SECRET='случайная-строка-32+'
#   export TURN_USER=reollity            # опционально, по умолчанию reollity
#   cd ~/my_chat_app && sudo -E ./scripts/setup-coturn-on-vm.sh
#
# После: открой UDP/TCP 3478 и UDP 49152-49252 в группе безопасности Yandex Cloud.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$TURN_PUBLIC_IP" ]; then
  echo "Ошибка: задай публичный IP ВМ:"
  echo "  export TURN_PUBLIC_IP=\$(curl -s ifconfig.me)"
  exit 1
fi

if [ -z "$TURN_SECRET" ] || [ ${#TURN_SECRET} -lt 16 ]; then
  echo "Ошибка: задай TURN_SECRET (минимум 16 символов):"
  echo "  export TURN_SECRET=\$(openssl rand -hex 24)"
  exit 1
fi

TURN_USER="${TURN_USER:-reollity}"

echo "=== Установка coturn ==="
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn

mkdir -p /var/log/turnserver
chown turnserver:turnserver /var/log/turnserver 2>/dev/null || true

TMP_CONF="$(mktemp)"
sed -e "s/TURN_PUBLIC_IP_PLACEHOLDER/$TURN_PUBLIC_IP/g" \
    -e "s/TURN_SECRET_PLACEHOLDER/$TURN_SECRET/g" \
    -e "s/TURN_USER_PLACEHOLDER/$TURN_USER/g" \
    "$SCRIPT_DIR/coturn/turnserver.conf.template" > "$TMP_CONF"
cp "$TMP_CONF" /etc/turnserver.conf
rm -f "$TMP_CONF"

# Ubuntu: coturn по умолчанию выключен
sed -i 's/^#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn 2>/dev/null || true
grep -q '^TURNSERVER_ENABLED=1' /etc/default/coturn 2>/dev/null || echo 'TURNSERVER_ENABLED=1' >> /etc/default/coturn

systemctl enable coturn
systemctl restart coturn
systemctl status coturn --no-pager -l || true

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q 'Status: active'; then
  echo "=== UFW: открываем порты TURN ==="
  ufw allow 3478/tcp
  ufw allow 3478/udp
  ufw allow 49152:49252/udp
fi

echo ""
echo "✅ coturn запущен."
echo ""
echo "Добавь в ~/my_chat_app/my_serve_chat_test/.env:"
echo ""
echo "WEBRTC_STUN_URLS=stun:stun.l.google.com:19302,stun:${TURN_PUBLIC_IP}:3478"
echo "WEBRTC_TURN_URL=turn:${TURN_PUBLIC_IP}:3478?transport=udp"
echo "WEBRTC_TURN_USERNAME=${TURN_USER}"
echo "WEBRTC_TURN_CREDENTIAL=${TURN_SECRET}"
echo ""
echo "Затем: pm2 restart chat-server"
echo ""
echo "Yandex Cloud: входящие UDP/TCP 3478 и UDP 49152-49252 на ВМ."
echo "Проверка: turnutils_uclient -v -u ${TURN_USER} -w \"\$TURN_SECRET\" ${TURN_PUBLIC_IP}"
