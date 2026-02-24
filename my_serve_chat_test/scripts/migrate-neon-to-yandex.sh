#!/usr/bin/env bash
# Перенос БД с Neon на Yandex Managed PostgreSQL.
# Требует: DATABASE_URL (Neon) и DATABASE_URL_YANDEX в .env или в окружении.
# Запуск из каталога my_serve_chat_test: ./scripts/migrate-neon-to-yandex.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if [ -f .env ]; then
  set -a
  source .env 2>/dev/null || true
  set +a
fi

if [ -z "$DATABASE_URL" ]; then
  echo "Ошибка: задайте DATABASE_URL (Neon) в .env или в окружении"
  exit 1
fi
if [ -z "$DATABASE_URL_YANDEX" ]; then
  echo "Ошибка: задайте DATABASE_URL_YANDEX в .env или в окружении"
  exit 1
fi

DUMP_FILE="${1:-neon_dump_$(date +%Y%m%d_%H%M%S).sql}"

echo "1/2 Дамп с Neon..."
pg_dump "$DATABASE_URL" --no-owner --no-acl -f "$DUMP_FILE"
echo "   Создан файл: $DUMP_FILE"

echo "2/2 Восстановление в Yandex..."
psql "$DATABASE_URL_YANDEX" -f "$DUMP_FILE"
echo "   Готово."

echo ""
echo "Миграция завершена. Можно удалить дамп: rm $DUMP_FILE"
echo "На Render замени DATABASE_URL на DATABASE_URL_YANDEX и перезапусти сервис."
