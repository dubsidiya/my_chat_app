/**
 * Read-only check: предоплата/долг в дереве выгрузки считаются по кошельку
 * (ученик+преподаватель), а не дублируются у всех преподавателей ученика.
 *
 * Run:
 *   node scripts/smoke-accounting-wallet-prepaid.js
 */
import pool from '../db.js';
import { exportAccounting } from '../controllers/adminAccountingController.js';
import { buildAccountingExport } from '../services/accounting/buildAccountingExport.js';

const makeRes = () => ({
  statusCode: 200,
  body: null,
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(payload) {
    this.body = payload;
    return this;
  },
  send(payload) {
    this.body = payload;
    return this;
  },
  setHeader() {},
});

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const EPS = 0.01;

const run = async () => {
  // Широкий период, чтобы захватить имеющиеся данные.
  const to = new Date().toISOString().slice(0, 10);
  const from = '2020-01-01';

  const res = makeRes();
  await exportAccounting({ query: { from, to, format: 'json' } }, res);
  assert(res.statusCode === 200, `export status ${res.statusCode}`);
  const tree = res.body?.tree;
  assert(Array.isArray(tree), 'tree отсутствует в ответе');

  // 1) Поля кошелька присутствуют у всех узлов учеников.
  let nodeCount = 0;
  // studentId -> { walletPrepaidSum, walletDebtSum, overallPrepaid, overallDebt, teacherNodes }
  const byStudent = new Map();

  for (const t of tree) {
    for (const s of t.students || []) {
      nodeCount += 1;
      assert(
        Object.prototype.hasOwnProperty.call(s, 'walletPrepaidAsOfTo'),
        `нет walletPrepaidAsOfTo у ученика ${s.studentId} препода ${t.teacherId}`
      );
      assert(
        Object.prototype.hasOwnProperty.call(s, 'walletDebtAsOfTo'),
        `нет walletDebtAsOfTo у ученика ${s.studentId} препода ${t.teacherId}`
      );
      assert(s.walletPrepaidAsOfTo >= -EPS, 'walletPrepaid отрицательный');
      assert(s.walletDebtAsOfTo >= -EPS, 'walletDebt отрицательный');

      const acc = byStudent.get(s.studentId) || {
        walletPrepaidSum: 0,
        walletDebtSum: 0,
        overallPrepaid: s.overallPrepaidAsOfTo || 0,
        overallDebt: s.overallDebtAsOfTo || 0,
        teacherNodes: 0,
      };
      acc.walletPrepaidSum += s.walletPrepaidAsOfTo || 0;
      acc.walletDebtSum += s.walletDebtAsOfTo || 0;
      acc.teacherNodes += 1;
      byStudent.set(s.studentId, acc);
    }
  }

  // 2) Инварианты на ученика:
  //    - сумма долга по кошелькам == общий долг ученика (долг полностью атрибутируется кошелькам);
  //    - сумма предоплат по кошелькам <= общий остаток (разница = неадресный legacy-пул);
  //    - предоплата на узле не превышает общий остаток ученика.
  let multiTeacher = 0;
  let duplicationGuardChecked = 0;
  for (const [sid, a] of byStudent.entries()) {
    assert(
      Math.abs(a.walletDebtSum - a.overallDebt) < 1,
      `ученик ${sid}: долг по кошелькам ${a.walletDebtSum} != общий ${a.overallDebt}`
    );
    assert(
      a.walletPrepaidSum <= a.overallPrepaid + 1,
      `ученик ${sid}: предоплата по кошелькам ${a.walletPrepaidSum} > общей ${a.overallPrepaid}`
    );

    if (a.teacherNodes > 1) {
      multiTeacher += 1;
      // Anti-regression: если у ученика есть предоплата, она не должна
      // механически дублироваться (== overall) у КАЖДОГО преподавателя.
      // sum по кошелькам <= overall гарантирует отсутствие дублирования.
      if (a.overallPrepaid > 0) {
        duplicationGuardChecked += 1;
        assert(
          a.walletPrepaidSum <= a.overallPrepaid + 1,
          `ученик ${sid}: предоплата дублируется у преподавателей`
        );
      }
    }
  }

  console.log(
    `✅ tree: ok ` +
      `(узлов: ${nodeCount}, учеников: ${byStudent.size}, ` +
      `с несколькими преподами: ${multiTeacher}, проверка дублирования: ${duplicationGuardChecked})`
  );

  // 3) Сервис выгрузки (используется в Excel): wallets сходятся с per-student.
  const payload = await buildAccountingExport(pool, { from, to });
  assert(Array.isArray(payload.wallets), 'payload.wallets отсутствует');
  const studentById = new Map((payload.students || []).map((s) => [s.id, s]));

  const walletByStudent = new Map();
  for (const w of payload.wallets) {
    const acc = walletByStudent.get(w.studentId) || { prepaid: 0, debt: 0 };
    acc.prepaid += w.prepaidAsOfTo || 0;
    acc.debt += w.debtAsOfTo || 0;
    walletByStudent.set(w.studentId, acc);
    assert(w.prepaidAsOfTo >= -EPS, 'wallets: предоплата отрицательная');
    assert(w.debtAsOfTo >= -EPS, 'wallets: долг отрицательный');
  }

  for (const [sid, acc] of walletByStudent.entries()) {
    const s = studentById.get(sid);
    if (!s) continue;
    // Кошельки (адресные + неадресный остаток) дают ровно общий остаток ученика.
    assert(
      Math.abs(acc.prepaid - (s.prepaidAsOfTo || 0)) < 1,
      `ученик ${sid}: предоплата кошельков ${acc.prepaid} != общей ${s.prepaidAsOfTo}`
    );
    assert(
      Math.abs(acc.debt - (s.debtAsOfTo || 0)) < 1,
      `ученик ${sid}: долг кошельков ${acc.debt} != общему ${s.debtAsOfTo}`
    );
  }

  console.log(
    `✅ wallets: ok (кошельков: ${payload.wallets.length}, учеников с кошельками: ${walletByStudent.size})`
  );
  console.log('✅ smoke-accounting-wallet-prepaid: ok');
};

run()
  .then(() => {
    process.exit(0);
  })
  .catch((e) => {
    console.error('❌ smoke-accounting-wallet-prepaid:', e.message);
    process.exit(1);
  });
