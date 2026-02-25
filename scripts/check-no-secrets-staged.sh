#!/usr/bin/env bash
# Проверка: не попали ли файлы с секретами в индекс git.
# Запуск: из корня репо: bash scripts/check-no-secrets-staged.sh
# В CI можно вызывать перед сборкой или в pre-commit.

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FOUND=
for f in my_serve_chat_test/.env my_serve_chat_test/env-yandex-vm.txt docs/YANDEX_DB_CREDENTIALS.txt scripts/.deploy_key scripts/vm-connection.txt; do
  if git diff --cached --name-only -- "$f" 2>/dev/null | grep -q .; then
    FOUND="${FOUND}  - $f"
  fi
done

if [ -n "$FOUND" ]; then
  echo "Ошибка: в коммит попали файлы с секретами (не коммить!):"
  echo "$FOUND"
  echo "Убери их из индекса: git reset HEAD -- <файл>"
  echo "См. docs/SECRETS_ROTATION.md"
  exit 1
fi

echo "OK: секреты не в индексе."
