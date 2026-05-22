# Промпт: генерация smoke-теста (my_chat_app backend)

Используй этот чеклист при добавлении smoke после фикса бага, особенно access/permissions и audit finding.

## 1. Определи слой бага

| Слой | Когда тестировать | Как |
|------|-------------------|-----|
| **Route middleware** | 403/401 до контроллера (requirePrivateAccess, requireSuperuser) | **HTTP** через mini Express + real routes (`scripts/smoke-helpers.js` → `withSmokeHttpServer`) |
| **Controller logic** | owner/super/404 внутри handler | Прямой вызов controller + `makeRes()` |
| **Service/DB** | транзакции, idempotency, export shape | pool + service/controller |
| **Live integration** | WS relay, login flow | fetch к `BASE_URL` + env credentials |

**Правило:** если finding упоминает `routes/*.js` и middleware — controller-only smoke **недостаточен**; добавь HTTP-сценарий.

## 2. Структура файла

```
my_serve_chat_test/scripts/smoke-<domain>-<topic>.js
```

Обязательно в шапке:

- что проверяет (1–3 пункта);
- `Run: node scripts/...` или npm script;
- связанный audit ID (если есть).

Шаблон:

```javascript
import pool from '../db.js';
import { assert, withSmokeHttpServer, loadUsers, bearerGet } from './smoke-helpers.js';

const run = async () => {
  // arrange from DB + env
  // act
  // assert status + minimal body contract
  // cleanup in finally if создавали данные
  console.log('✅ smoke-...: ok');
  await pool.end();
};

run().catch(async (e) => {
  console.error('❌ smoke-... failed:', e?.message || e);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
```

## 3. Сценарии и данные

- **Позитив + негатив** для каждого инварианта (allowed → 200, forbidden → 403/404 по контракту).
- **Superuser:** `isSuperuser(u)` из env `SUPERUSER_*`; private — `hasPrivateAccess(u)` из `PRIVATE_ACCESS_*`.
- Идеальный кейс для route access: super **без** private (`isSuperuser && !hasPrivateAccess`).
- Если super не в env — **временно** выставь `SUPERUSER_USER_IDS` на plain user из БД, проверь 200, верни env (см. `smoke-routes-access.js`).
- Cleanup: удалять только то, что создал smoke (reports, messages, idempotency keys).

## 4. Регистрация

1. Добавь script в `my_serve_chat_test/package.json`.
2. Если стабилен и быстрый — включи в `smoke:all`.
3. В audit/doc укажи команду верификации.

## 5. После правок access/reports

```bash
cd my_serve_chat_test
npm run smoke:routes:access
npm run smoke:reports:permissions
npm run smoke:reports:regressions
npm run smoke:accounting:hidden-quality
```

## 6. Anti-patterns

- Не дублировать `makeRes`/`assert` — используй `smoke-helpers.js`.
- Не тестировать только controller, если баг был в router.
- Не требовать второго superuser в БД для HTTP route smoke (достаточно env super + GET /reports).
- Не добавлять зависимости (supertest) без необходимости — `fetch` + in-process server.

## 7. Definition of done

- [ ] HTTP-сценарий для route middleware (если применимо)
- [ ] npm script + (при необходимости) `smoke:all`
- [ ] Прогон локально зелёный
- [ ] Audit finding перенесён в «Resolved» с командой smoke
