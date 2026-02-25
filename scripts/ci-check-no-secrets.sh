#!/usr/bin/env bash
# CI: проверка, что в репозитории не отслеживаются файлы с секретами.
# Используется в GitHub Actions. Выход 1, если любой из перечисленных путей в git ls-files.

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SECRET_PATHS=(
  "my_serve_chat_test/.env"
  "my_serve_chat_test/env-yandex-vm.txt"
  "docs/YANDEX_DB_CREDENTIALS.txt"
  "scripts/.deploy_key"
  "scripts/vm-connection.txt"
)

FOUND=
for path in "${SECRET_PATHS[@]}"; do
  if [ -n "$(git ls-files "$path" 2>/dev/null)" ]; then
    FOUND="${FOUND}  - ${path}"
  fi
done

if [ -n "$FOUND" ]; then
  echo "::error::В репозитории отслеживаются файлы с секретами (удалите из истории и смените секреты):"
  echo "$FOUND"
  echo "См. docs/SECRETS_ROTATION.md"
  exit 1
fi

echo "OK: файлы с секретами не отслеживаются в репо."
