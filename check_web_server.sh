#!/bin/bash
# Скрипт для проверки состояния веб-сервера 93.183.80.97

echo "=== Проверка файлов ==="
ssh root@93.183.80.97 '
  echo "Содержимое /var/www/reollity:"
  ls -lah /var/www/reollity/ | head -20
  echo ""
  echo "Есть ли index.html?"
  test -f /var/www/reollity/index.html && echo "✅ index.html есть" || echo "❌ index.html НЕТ"
  echo ""
  echo "Есть ли canvaskit?"
  test -d /var/www/reollity/canvaskit && echo "✅ canvaskit/ есть" || echo "❌ canvaskit/ НЕТ"
  test -f /var/www/reollity/canvaskit/canvaskit.wasm && echo "✅ canvaskit.wasm есть" || echo "❌ canvaskit.wasm НЕТ"
'

echo ""
echo "=== Проверка nginx ==="
ssh root@93.183.80.97 '
  echo "Статус nginx:"
  systemctl status nginx --no-pager | head -10
  echo ""
  echo "Конфиг nginx:"
  test -f /etc/nginx/sites-enabled/reollity && echo "✅ /etc/nginx/sites-enabled/reollity есть" || echo "❌ конфиг НЕ настроен"
  echo ""
  echo "Проверка curl localhost:"
  curl -fsS -o /dev/null -w "HTTP код: %{http_code}\n" http://localhost/ || echo "❌ Nginx не отвечает"
'

echo ""
echo "=== Проверка портов ==="
ssh root@93.183.80.97 '
  echo "Открытые порты:"
  ss -tlnp | grep -E ":80|:443"
'
