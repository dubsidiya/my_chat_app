# Команды для работы с ВМ — справочник с комментариями

Все команды, которые использовались при настройке ВМ, автодеплоя и HTTPS. Запускать из корня репозитория (где есть папка `scripts/`). IP ВМ: **93.77.185.6**, пользователь: **ubuntu**, ключ: **scripts/.deploy_key**.

**Безопасность:** в файле указаны IP сервера и путь к ключу; секретов (приватный ключ, пароли) нет. Не коммитьте в публичный репозиторий, если не хотите светить инфраструктуру, или замените IP на плейсхолдер. Команда в п. 3 выводит первые 5 строк `.env` на ВМ — не запускайте её на общих экранах.

---

## 1. Узнать URL репозитория (для клонирования на ВМ)

```bash
git remote get-url origin
```

**Что делает:** выводит адрес удалённого репозитория (origin). Нужен, чтобы на ВМ выполнить `git clone <этот-адрес>`. Пример вывода: `git@github.com:dubsidiya/my_chat_app.git` или `https://github.com/dubsidiya/my_chat_app.git`.

---

## 2. Подключиться к ВМ по SSH

```bash
ssh -i scripts/.deploy_key -o StrictHostKeyChecking=accept-new ubuntu@93.77.185.6
```

**Что делает:**
- `ssh` — подключение по SSH.
- `-i scripts/.deploy_key` — использовать этот приватный ключ (без пароля по SSH).
- `-o StrictHostKeyChecking=accept-new` — при первом подключении принять fingerprint хоста и не спрашивать подтверждение в интерактиве.
- `ubuntu@93.77.185.6` — пользователь и IP ВМ.

После выполнения ты оказываешься в консоли на ВМ. Выход: `exit` или Ctrl+D.

---

## 3. Проверить, есть ли на ВМ файл .env (и показать начало)

```bash
ssh -i scripts/.deploy_key -o StrictHostKeyChecking=accept-new ubuntu@93.77.185.6 \
  "test -f ~/my_chat_app/my_serve_chat_test/.env && cat ~/my_chat_app/my_serve_chat_test/.env | head -5 || echo 'NO_ENV'"
```

**Что делает:**
- Подключается по SSH и выполняет одну команду в кавычках на ВМ.
- `test -f ...` — проверить, существует ли файл `.env`.
- `&& cat ... | head -5` — если да, вывести первые 5 строк (без показа секретов целиком).
- `|| echo 'NO_ENV'` — если файла нет, вывести `NO_ENV`.

---

## 4. На ВМ: перейти на git-клон, восстановить .env, поднять pm2 (один большой блок)

Эту последовательность выполняли одним вызовом SSH с передачей скрипта через heredoc. По шагам что делает каждая часть:

```bash
ssh -i scripts/.deploy_key -o StrictHostKeyChecking=accept-new ubuntu@93.77.185.6 'bash -s' << 'REMOTE'
set -e
# 1. Сохраняем .env во временный файл в домашней папке
if [ -f ~/my_chat_app/my_serve_chat_test/.env ]; then
  cp ~/my_chat_app/my_serve_chat_test/.env ~/.env.chat_backup
  echo "Backed up .env"
fi
# 2. Удаляем старую папку проекта (раньше заливали через rsync — без .git)
rm -rf ~/my_chat_app
# 3. Клонируем репозиторий с GitHub (HTTPS подходит для публичного репо)
git clone --depth 1 https://github.com/dubsidiya/my_chat_app.git ~/my_chat_app
# 4. Возвращаем .env на место
if [ -f ~/.env.chat_backup ]; then
  cp ~/.env.chat_backup ~/my_chat_app/my_serve_chat_test/.env
  rm ~/.env.chat_backup
  echo "Restored .env"
fi
# 5. Ставим зависимости по package-lock.json и запускаем сервер через pm2
cd ~/my_chat_app/my_serve_chat_test
npm ci
pm2 delete chat-server 2>/dev/null || true   # удалить старый процесс, если был
pm2 start index.js --name chat-server         # запустить приложение под именем chat-server
pm2 save                                       # сохранить список процессов (для pm2 resurrect после перезагрузки)
pm2 startup 2>/dev/null || true               # вывести команду для автозапуска (см. шаг 5)
echo "Done. pm2 list:"
pm2 list
REMOTE
```

**Что делает по частям:**
- `ssh ... 'bash -s' << 'REMOTE'` — подключиться к ВМ и передать весь блок до `REMOTE` в стандартный ввод `bash` на ВМ (выполнится как скрипт на сервере).
- `set -e` — при любой ошибке скрипт сразу завершиться.
- `cp ... ~/.env.chat_backup` — бэкап `.env`, чтобы не потерять после `rm -rf`.
- `rm -rf ~/my_chat_app` — удалить старую копию проекта (без git).
- `git clone --depth 1 ...` — клонировать только последний коммит (экономия места), чтобы на ВМ работали `git fetch`/`git reset` для автодеплоя.
- `npm ci` — установить зависимости строго по `package-lock.json` (как в CI).
- `pm2 delete ... || true` — удалить процесс с именем `chat-server`, если есть; `2>/dev/null` скрывает ошибку, если процесса не было.
- `pm2 start index.js --name chat-server` — запустить Node-приложение в фоне с именем `chat-server`.
- `pm2 save` — сохранить текущий список процессов в `~/.pm2/dump.pm2`.
- `pm2 startup` — показать команду для настройки автозапуска pm2 при загрузке ВМ (саму команду выполняли отдельно, см. ниже).

---

## 5. Включить автозапуск pm2 при перезагрузке ВМ

```bash
ssh -i scripts/.deploy_key ubuntu@93.77.185.6 \
  "sudo env PATH=\$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu"
```

**Что делает:**
- На ВМ через SSH выполняется команда `pm2 startup`.
- `sudo` — от root, чтобы создать systemd-юнит.
- `env PATH=$PATH:/usr/bin` — подставить текущий PATH (нужен, чтобы pm2 нашёл node).
- `pm2 startup systemd -u ubuntu --hp /home/ubuntu` — создать службу systemd для пользователя `ubuntu`, домашняя папка `/home/ubuntu`. После перезагрузки ВМ pm2 сам поднимет сохранённые процессы (`pm2 resurrect`).

---

## 6. Проверить, что API отвечает по HTTPS

```bash
curl -s -o /dev/null -w "%{http_code}" https://reollity.duckdns.org/healthz && echo "" && curl -s https://reollity.duckdns.org/healthz
```

**Что делает:**
- Первый `curl`: `-s` тихо, `-o /dev/null` тело ответа не выводить, `-w "%{http_code}"` вывести только код (200, 404 и т.д.). Проверка, что эндпоинт доступен.
- Второй `curl`: вывести тело ответа (должно быть `ok` для `/healthz`).

Краткий вариант — только код и тело:

```bash
curl -s https://reollity.duckdns.org/healthz
```

---

## 7. Залить код на ВМ через rsync (без git)

```bash
rsync -avz --exclude node_modules --exclude '.env' --exclude '.git' \
  -e "ssh -i scripts/.deploy_key -o StrictHostKeyChecking=accept-new" \
  ./ ubuntu@93.77.185.6:~/my_chat_app/
```

**Что делает:**
- `rsync -avz` — синхронизация: архивный режим, сохранять атрибуты, сжатие. Копирует только изменённые файлы.
- `--exclude node_modules` и т.д. — не тащить тяжёлые/секретные каталоги и файлы.
- `-e "ssh ..."` — использовать этот SSH (ключ и опции).
- `./` — источник: текущая папка (корень репо).
- `ubuntu@93.77.185.6:~/my_chat_app/` — назначение: домашняя папка ubuntu на ВМ. После такой заливки на ВМ **нет** `.git` — для автодеплоя через GitHub Actions нужен именно git-клон (см. блок 4).

---

## 8. Настроить HTTPS на ВМ (Caddy + Let's Encrypt) — одной командой с Mac

Скрипт из репозитория:

```bash
./scripts/setup-https-reollity-from-mac.sh
```

**Что делает скрипт внутри:**
1. `rsync` — заливает проект на ВМ (как в п. 7).
2. По SSH на ВМ запускает `scripts/setup-https-on-vm.sh` с `DOMAIN=reollity.duckdns.org`: ставит Caddy, получает сертификат, проксирует HTTPS → `127.0.0.1:3000`.

Вручную то же самое:

```bash
rsync -avz --exclude node_modules --exclude '.env' --exclude '.git' \
  -e "ssh -i scripts/.deploy_key -o StrictHostKeyChecking=accept-new" \
  ./ ubuntu@93.77.185.6:~/my_chat_app/

ssh -i scripts/.deploy_key -o StrictHostKeyChecking=accept-new ubuntu@93.77.185.6 \
  "cd ~/my_chat_app && chmod +x scripts/setup-https-on-vm.sh && sudo DOMAIN=reollity.duckdns.org ./scripts/setup-https-on-vm.sh"
```

---

## 9. Полный деплой с Mac (код + .env + npm ci + pm2)

Если настроен файл `my_serve_chat_test/env-yandex-vm.txt`:

```bash
./scripts/deploy-to-yandex-vm-now.sh
```

**Что делает:** копирует проект и этот файл как `.env` на ВМ, по SSH ставит Node (если нужно), выполняет `npm ci`, перезапускает/запускает `pm2` с именем `chat-server`. Подробности — в самом скрипте `scripts/deploy-to-yandex-vm-now.sh`.

---

## Краткая шпаргалка

| Задача              | Команда |
|---------------------|--------|
| Войти на ВМ         | `ssh -i scripts/.deploy_key ubuntu@93.77.185.6` |
| Проверить API       | `curl -s https://reollity.duckdns.org/healthz` |
| Залить код (rsync)  | `rsync -avz --exclude node_modules --exclude '.env' -e "ssh -i scripts/.deploy_key" ./ ubuntu@93.77.185.6:~/my_chat_app/` |
| Полный деплой       | `./scripts/deploy-to-yandex-vm-now.sh` |
| HTTPS один раз      | `./scripts/setup-https-reollity-from-mac.sh` |

Данные для подключения и переменные — в `scripts/vm-connection.txt` (файл в .gitignore).
