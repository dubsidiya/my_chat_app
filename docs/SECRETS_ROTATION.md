# Ротация секретов и очистка истории

Если файлы с секретами (**env-yandex-vm.txt**, **.env**, **docs/YANDEX_DB_CREDENTIALS.txt**, **scripts/.deploy_key**) когда-либо попадали в репозиторий (в т.ч. в историю коммитов), необходимо:

## 1. Сменить все секреты

- **Пароль БД:** в консоли Yandex Cloud (Managed PostgreSQL) смени пароль пользователя `chat_app`. Обнови `DATABASE_URL` на ВМ и в любых локальных .env.
- **JWT_SECRET:** сгенерируй новый ключ (`openssl rand -base64 32`), обнови в .env на ВМ и перезапусти сервис. Все выданные токены станут недействительными (пользователям нужно войти заново).
- **Yandex Object Storage:** при утечке ключей — перевыпусти статические ключи доступа в консоли Yandex и обнови `YANDEX_ACCESS_KEY_ID` / `YANDEX_SECRET_ACCESS_KEY` на ВМ.
- **SSH-ключ деплоя:** сгенерируй новую пару (`ssh-keygen -t ed25519 -f scripts/.deploy_key -N ''`), добавь публичный ключ на ВМ в `~/.ssh/authorized_keys`, обнови секрет `DEPLOY_SSH_KEY` в GitHub Actions.

## 2. Убедиться, что файлы не отслеживаются

```bash
# Проверить, не в индексе ли секреты
git status my_serve_chat_test/.env my_serve_chat_test/env-yandex-vm.txt docs/YANDEX_DB_CREDENTIALS.txt scripts/.deploy_key

# Если они показываются как изменённые или уже закоммичены — убрать из индекса (файлы останутся на диске)
git rm --cached my_serve_chat_test/.env 2>/dev/null || true
git rm --cached my_serve_chat_test/env-yandex-vm.txt 2>/dev/null || true
git rm --cached docs/YANDEX_DB_CREDENTIALS.txt 2>/dev/null || true
git rm --cached scripts/.deploy_key 2>/dev/null || true
```

После этого закоммить удаление из индекса. **Важно:** старые коммиты всё ещё будут содержать секреты в истории.

## 3. Удалить секреты из истории (опционально, но рекомендуется при утечке)

Использовать **BFG Repo-Cleaner** или **git filter-repo**:

```bash
# Пример с BFG (нужна установка: https://rtyley.github.io/bfg-repo-cleaner/)
# Клонировать репо как mirror, затем:
bfg --delete-files env-yandex-vm.txt
bfg --delete-files YANDEX_DB_CREDENTIALS.txt
bfg --delete-files .env
git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

Либо с **git filter-repo** (см. документацию по пути к конкретным файлам).

После перезаписи истории все клоны репозитория должны переклонироваться; force-push в main потребует прав.

## 4. Предотвращение повторной утечки

- Используй только **env-yandex-vm.example.txt** и **YANDEX_DB_CREDENTIALS.example.txt** в репо (с плейсхолдерами).
- Реальные значения храни только на ВМ (в .env), в менеджере секретов или на доверенной машине вне репо.
- Перед `git add` проверяй: `git status` не должен показывать .env, env-yandex-vm.txt, YANDEX_DB_CREDENTIALS.txt, scripts/.deploy_key.
- **Автоматически:** при каждом push и pull_request GitHub Actions (workflow **Security check**) проверяет, что эти файлы не отслеживаются в репо, и запускает `npm audit` в бэкенде.

См. также: docs/SECURITY_AUDIT_2025-02-25.md, docs/SECURITY_AUDIT_PROMPT.md.
