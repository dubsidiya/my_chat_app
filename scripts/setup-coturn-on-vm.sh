#!/usr/bin/env bash
# Установка coturn (TURN) на Ubuntu 22.04 для голосовых звонков WebRTC.
#
# Использование на ВМ:
#   export TURN_PUBLIC_IP=93.77.185.6   # публичный IP этой ВМ
#   export TURN_PRIVATE_IP=10.128.0.14  # опционально; иначе берётся из hostname -I
#   export TURN_SECRET='случайная-строка-32+'
#   # optional TLS (turns:443 / turns:5349):
#   export TURN_TLS_CERT=/etc/letsencrypt/live/turn.example/fullchain.pem
#   export TURN_TLS_KEY=/etc/letsencrypt/live/turn.example/privkey.pem
#   export TURN_TLS_HOST=turn.example
#   cd ~/my_chat_app && sudo -E ./scripts/setup-coturn-on-vm.sh
#
# После: открой UDP/TCP 3478, TCP 5349 (и 443 если проксируете TLS),
# UDP 49152-49252 в группе безопасности Yandex Cloud.
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

TURN_PRIVATE_IP="${TURN_PRIVATE_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
if [ -z "$TURN_PRIVATE_IP" ]; then
  echo "Ошибка: не удалось определить внутренний IP. Задай вручную:"
  echo "  export TURN_PRIVATE_IP=10.128.0.14"
  exit 1
fi

echo "=== coturn: public=$TURN_PUBLIC_IP private=$TURN_PRIVATE_IP ==="

echo "=== Установка coturn ==="
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn

mkdir -p /var/log/turnserver
chown turnserver:turnserver /var/log/turnserver 2>/dev/null || true

ENABLE_TLS=0
if [ -n "${TURN_TLS_CERT:-}" ] && [ -n "${TURN_TLS_KEY:-}" ]; then
  if [ ! -r "$TURN_TLS_CERT" ] || [ ! -r "$TURN_TLS_KEY" ]; then
    echo "Ошибка: TURN_TLS_CERT / TURN_TLS_KEY не читаются"
    exit 1
  fi
  mkdir -p /etc/coturn
  cp "$TURN_TLS_CERT" /etc/coturn/fullchain.pem
  cp "$TURN_TLS_KEY" /etc/coturn/privkey.pem
  chown turnserver:turnserver /etc/coturn/fullchain.pem /etc/coturn/privkey.pem
  chmod 640 /etc/coturn/fullchain.pem /etc/coturn/privkey.pem
  ENABLE_TLS=1
  echo "=== TLS material installed under /etc/coturn ==="
fi

TMP_CONF="$(mktemp)"
sed -e "s/TURN_PUBLIC_IP_PLACEHOLDER/$TURN_PUBLIC_IP/g" \
    -e "s/TURN_PRIVATE_IP_PLACEHOLDER/$TURN_PRIVATE_IP/g" \
    -e "s/TURN_SECRET_PLACEHOLDER/$TURN_SECRET/g" \
    "$SCRIPT_DIR/coturn/turnserver.conf.template" > "$TMP_CONF"

if [ "$ENABLE_TLS" = "1" ]; then
  # Replace the commented TLS section with an active one (no sed \\n pitfalls).
  python3 - "$TMP_CONF" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
begin = "# TURN_TLS_SECTION_BEGIN"
end = "# TURN_TLS_SECTION_END"
start = text.find(begin)
stop = text.find(end)
if start < 0 or stop < 0:
    raise SystemExit("TLS section markers missing in turnserver template")
replacement = """# TURN_TLS_SECTION_BEGIN
tls-listening-port=5349
cert=/etc/coturn/fullchain.pem
pkey=/etc/coturn/privkey.pem
# TURN_TLS_SECTION_END"""
path.write_text(text[:start] + replacement + text[stop + len(end):])
PY
fi

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
  if [ "$ENABLE_TLS" = "1" ]; then
    ufw allow 5349/tcp
  fi
  ufw allow 49152:49252/udp
fi

echo ""
echo "✅ coturn запущен (use-auth-secret / TURN REST)."
echo ""
echo "Добавь в ~/my_chat_app/my_serve_chat_test/.env:"
echo ""
echo "WEBRTC_STUN_URLS=stun:stun.l.google.com:19302,stun:${TURN_PUBLIC_IP}:3478"
echo "WEBRTC_TURN_URL=turn:${TURN_PUBLIC_IP}:3478"
echo "WEBRTC_TURN_SECRET=${TURN_SECRET}"
echo "WEBRTC_TURN_TTL_SECONDS=21600"
if [ -n "${TURN_TLS_HOST:-}" ] && [ "$ENABLE_TLS" = "1" ]; then
  echo "WEBRTC_TURN_TLS_ENABLED=true"
  echo "WEBRTC_TURN_TLS_HOST=${TURN_TLS_HOST}"
  echo "# or explicit:"
  echo "# WEBRTC_TURNS_URL=turns:${TURN_TLS_HOST}:443?transport=tcp,turns:${TURN_TLS_HOST}:5349?transport=tcp"
fi
echo ""
echo "# Legacy static shared credentials (optional fallback if HMAC unset):"
echo "# WEBRTC_TURN_USERNAME=..."
echo "# WEBRTC_TURN_CREDENTIAL=..."
echo ""
echo "Затем: pm2 restart chat-server"
echo ""
echo "Yandex Cloud: входящие UDP/TCP 3478$([ "$ENABLE_TLS" = "1" ] && echo ', TCP 5349'), UDP 49152-49252."
echo "HMAC smoke: npm run smoke:call:turn  (или GET /calls/ice-servers с JWT)."
