/**
 * HTTP route access smoke (real Express routers + middleware).
 *
 * Covers audit F-02 regression (requirePrivateAccess + isSuperuser):
 * 1) superuser without PRIVATE_ACCESS env → GET /reports, /students/search not 403
 * 2) private teacher → GET /reports, /students/search → 200
 * 3) plain user → GET /reports, /students/search → 403
 * 4) private teacher → GET /students/:id/deposit-teachers → 403 (requireSuperuser)
 * 5) superuser → GET /students/:id/deposit-teachers not 403
 *
 * Run: node scripts/smoke-routes-access.js
 * npm:  npm run smoke:routes:access
 */
import pool from '../db.js';
import { hasPrivateAccess, isSuperuser } from '../middleware/auth.js';
import {
  assert,
  httpRequest,
  loadUsers,
  tokenForUser,
  withSmokeHttpServer,
} from './smoke-helpers.js';

const classify = (users) => {
  const withFlags = users.map((u) => ({
    ...u,
    super: isSuperuser(u),
    private: hasPrivateAccess(u),
  }));
  return {
    superOnly: withFlags.find((u) => u.super && !u.private) || null,
    superAny: withFlags.find((u) => u.super) || null,
    privateTeacher: withFlags.find((u) => u.private && !u.super) || withFlags.find((u) => u.private) || null,
    plain: withFlags.find((u) => !u.private && !u.super) || null,
  };
};

const withTemporarySuperuser = async (userId, fn) => {
  const prevIds = process.env.SUPERUSER_USER_IDS;
  const prevNames = process.env.SUPERUSER_USERNAMES;
  process.env.SUPERUSER_USER_IDS = String(userId);
  delete process.env.SUPERUSER_USERNAMES;
  try {
    await fn();
  } finally {
    if (prevIds === undefined) delete process.env.SUPERUSER_USER_IDS;
    else process.env.SUPERUSER_USER_IDS = prevIds;
    if (prevNames === undefined) delete process.env.SUPERUSER_USERNAMES;
    else process.env.SUPERUSER_USERNAMES = prevNames;
  }
};

const loadAnyStudentId = async () => {
  const res = await pool.query('SELECT id FROM students ORDER BY id ASC LIMIT 1');
  return res.rows[0] ? Number(res.rows[0].id) : null;
};

const run = async () => {
  const users = await loadUsers();
  assert(users.length > 0, 'Нет пользователей для smoke-routes-access');

  const studentId = await loadAnyStudentId();
  const { superOnly, superAny, privateTeacher, plain } = classify(users);

  await withSmokeHttpServer(async (base) => {
    // 0) Гарантированный F-02: временно делаем plain user super через env
    if (plain) {
      await withTemporarySuperuser(plain.userId, async () => {
        const token = tokenForUser(plain, false);
        const reportsRes = await httpRequest(base, '/reports/', { token });
        assert(
          reportsRes.status === 200,
          `temp super plain user GET /reports/ ожидали 200, получили ${reportsRes.status}: ${reportsRes.text}`
        );

        const studentsRes = await httpRequest(base, '/students/search?q=a', { token });
        assert(
          studentsRes.status !== 403,
          `temp super plain user GET /students/search не должен быть 403, получили ${studentsRes.status}`
        );

        if (studentId != null) {
          const depositRes = await httpRequest(base, `/students/${studentId}/deposit-teachers`, { token });
          assert(
            depositRes.status !== 403,
            `temp super plain user GET deposit-teachers не должен быть 403, получили ${depositRes.status}`
          );
        }

        console.log(`   temp-super plain (${plain.email}): /reports + /students OK (F-02 route bypass)`);
      });
    } else {
      console.warn('⚠️  Пропущено: нет plain user для temp-super F-02 сценария');
    }

    // 1) Super из env (если настроен)
    const superUser = superOnly || superAny;
    if (superUser) {
      const token = tokenForUser(superUser, false);
      const reportsRes = await httpRequest(base, '/reports/', { token });
      assert(
        reportsRes.status !== 403,
        `superuser GET /reports/ не должен быть 403, получили ${reportsRes.status}: ${reportsRes.text}`
      );
      assert(
        reportsRes.status === 200,
        `superuser GET /reports/ ожидали 200, получили ${reportsRes.status}`
      );

      const studentsRes = await httpRequest(base, '/students/search?q=a', { token });
      assert(
        studentsRes.status !== 403,
        `superuser GET /students/search не должен быть 403, получили ${studentsRes.status}`
      );

      if (studentId != null) {
        const depositRes = await httpRequest(base, `/students/${studentId}/deposit-teachers`, { token });
        assert(
          depositRes.status !== 403,
          `superuser GET deposit-teachers не должен быть 403, получили ${depositRes.status}`
        );
      }

      if (superOnly) {
        console.log(`   super-only (${superOnly.email}): /reports + /students + deposit-teachers OK`);
      } else {
        console.warn(
          `⚠️  superuser (${superUser.email}) также в PRIVATE_ACCESS_* — route smoke прошёл, но нет чистого super-only в env`
        );
      }
    } else {
      console.warn('⚠️  Пропущено: нет superuser в SUPERUSER_* для HTTP route smoke');
    }

    // 2) Private teacher проходит requirePrivateAccess, но не requireSuperuser
    if (privateTeacher) {
      const token = tokenForUser(privateTeacher, true);
      const reportsRes = await httpRequest(base, '/reports/', { token });
      assert(reportsRes.status === 200, `private teacher GET /reports/ ожидали 200, получили ${reportsRes.status}`);

      const studentsRes = await httpRequest(base, '/students/search?q=a', { token });
      assert(
        studentsRes.status !== 403,
        `private teacher GET /students/search не должен быть 403, получили ${studentsRes.status}`
      );

      if (studentId != null) {
        const depositRes = await httpRequest(base, `/students/${studentId}/deposit-teachers`, { token });
        assert(
          depositRes.status === 403,
          `private teacher GET deposit-teachers ожидали 403, получили ${depositRes.status}`
        );
      }

      console.log(`   private (${privateTeacher.email}): /reports + /students OK, deposit-teachers 403 OK`);
    } else {
      console.warn('⚠️  Пропущено: нет пользователя с PRIVATE_ACCESS_*');
    }

    // 3) Обычный user без private → 403 (env super не подмешан — withTemporarySuperuser уже завершился)
    if (plain) {
      const token = tokenForUser(plain, false);
      const reportsRes = await httpRequest(base, '/reports/', { token });
      assert(reportsRes.status === 403, `plain user GET /reports/ ожидали 403, получили ${reportsRes.status}`);

      const studentsRes = await httpRequest(base, '/students/search?q=a', { token });
      assert(studentsRes.status === 403, `plain user GET /students/search ожидали 403, получили ${studentsRes.status}`);

      if (studentId != null) {
        const depositRes = await httpRequest(base, `/students/${studentId}/deposit-teachers`, { token });
        assert(
          depositRes.status === 403,
          `plain user GET deposit-teachers ожидали 403, получили ${depositRes.status}`
        );
      }

      console.log(`   plain (${plain.email}): /reports + /students 403 OK`);
    } else {
      console.warn('⚠️  Пропущено: нет plain user (все в private/super lists?)');
    }
  });

  console.log('✅ smoke-routes-access: ok');
  // db.js делает pool.query через setTimeout(1s) при импорте — ждём, чтобы не шуметь после pool.end()
  await new Promise((r) => setTimeout(r, 1100));
  await pool.end();
};

run().catch(async (error) => {
  console.error('❌ smoke-routes-access failed:', error?.message || error);
  try {
    await pool.end();
  } catch (_) {}
  process.exit(1);
});
