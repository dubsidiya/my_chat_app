/**
 * Smoke для XLSX-выгрузки бухгалтерии:
 *  - валидация дат → 400
 *  - корректные параметры → 200 и валидный xlsx (5 листов, русские заголовки)
 *  - флаг bank_transfer_only → суффикс в имени файла
 *
 * Не трогает существующие endpoints. Запуск:
 *   node scripts/smoke-accounting-xlsx.js
 */
import ExcelJS from 'exceljs';
import pool from '../db.js';
import { exportAccountingXlsx } from '../controllers/adminAccountingController.js';

const makeRes = () => ({
  statusCode: 200,
  body: null,
  headers: {},
  setHeader(name, value) {
    this.headers[name] = value;
    return this;
  },
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
});

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const run = async () => {
  const today = new Date();
  const isoToday = today.toISOString().slice(0, 10);
  const monthAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
  const isoFrom = monthAgo.toISOString().slice(0, 10);

  // 1) Некорректные даты → 400.
  const badRes = makeRes();
  await exportAccountingXlsx(
    { user: { userId: 1, email: 'smoke' }, query: { from: '2025/01/01', to: isoToday } },
    badRes
  );
  assert(badRes.statusCode === 400, `Ожидался 400 для bad from, получили ${badRes.statusCode}`);

  // 2) Перепутанные даты → 400.
  const swappedRes = makeRes();
  await exportAccountingXlsx(
    { user: { userId: 1, email: 'smoke' }, query: { from: isoToday, to: isoFrom } },
    swappedRes
  );
  assert(swappedRes.statusCode === 400, `Ожидался 400 для to<from, получили ${swappedRes.statusCode}`);

  // 3) Корректные параметры → 200 + валидный xlsx.
  const okRes = makeRes();
  await exportAccountingXlsx(
    { user: { userId: 1, email: 'smoke' }, query: { from: isoFrom, to: isoToday } },
    okRes
  );
  assert(okRes.statusCode === 200, `Ожидался 200, получили ${okRes.statusCode}`);
  assert(Buffer.isBuffer(okRes.body), 'Ответ должен быть Buffer (xlsx)');
  assert(
    (okRes.headers['Content-Type'] || '').includes('officedocument.spreadsheetml.sheet'),
    `Неверный Content-Type: ${okRes.headers['Content-Type']}`
  );
  const dispo = (okRes.headers['Content-Disposition'] || '').toString();
  assert(dispo.includes('buhgalteriya_') && dispo.endsWith('.xlsx"'), `Неверное имя файла: ${dispo}`);

  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(okRes.body);
  const sheetNames = wb.worksheets.map((s) => s.name);
  const expected = ['Сводка', 'Преподаватели', 'Ученики', 'Занятия', 'Транзакции'];
  for (const name of expected) {
    assert(sheetNames.includes(name), `В книге нет листа "${name}". Есть: ${sheetNames.join(', ')}`);
  }

  // Заголовки таблиц на русском — проверим лист "Преподаватели".
  const teachersSheet = wb.getWorksheet('Преподаватели');
  const teacherHeader = teachersSheet.getRow(1).values.filter(Boolean).map(String);
  assert(
    teacherHeader.includes('Преподаватель') && teacherHeader.includes('Долг'),
    `Заголовки "Преподаватели" неверные: ${teacherHeader.join(' | ')}`
  );

  // 4) Bank transfer flag меняет суффикс файла.
  const bankRes = makeRes();
  await exportAccountingXlsx(
    {
      user: { userId: 1, email: 'smoke' },
      query: { from: isoFrom, to: isoToday, bank_transfer_only: '1' },
    },
    bankRes
  );
  assert(bankRes.statusCode === 200, `bank_transfer_only ожидал 200, получили ${bankRes.statusCode}`);
  const bankDispo = (bankRes.headers['Content-Disposition'] || '').toString();
  assert(
    bankDispo.includes('_raschetnyi_schet.xlsx"'),
    `Ожидали суффикс _raschetnyi_schet в имени файла, получили: ${bankDispo}`
  );

  console.log('✅ smoke-accounting-xlsx: ok');
  await pool.end();
};

run().catch(async (error) => {
  console.error('❌ smoke-accounting-xlsx failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
