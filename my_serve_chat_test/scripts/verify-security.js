/**
 * Проверка загрузки модулей безопасности и ключевой логики (без БД и сервера).
 * Запуск: node scripts/verify-security.js
 */
import { sanitizeForDisplay, sanitizeMessageContent, parsePositiveInt } from '../utils/sanitize.js';
import { securityEvent } from '../utils/auditLog.js';
import ExcelJS from 'exceljs';

const assert = (ok, msg) => {
  if (!ok) throw new Error(msg);
};

console.log('1. utils/sanitize.js');
assert(sanitizeForDisplay('  a \x00b\u200B  ', 10) === 'a b', 'sanitizeForDisplay');
assert(sanitizeMessageContent('a\x00b\n') === 'ab\n', 'sanitizeMessageContent');
assert(parsePositiveInt(1) === 1 && parsePositiveInt(0) === null && parsePositiveInt(-1) === null, 'parsePositiveInt');
assert(parsePositiveInt('99999999999999999999') === null, 'parsePositiveInt overflow');
console.log('   OK');

console.log('2. utils/auditLog.js');
securityEvent('test', { ip: '127.0.0.1', user: { userId: 1 } });
console.log('   OK');

console.log('3. exceljs (parseExcel replacement)');
const wb = new ExcelJS.Workbook();
const ws = wb.addWorksheet('Sheet1');
ws.addRow(['A', 'B', 'C']);
ws.addRow([1, 2, 3]);
const buf = await wb.xlsx.writeBuffer();
assert(Buffer.isBuffer(buf) || buf instanceof Uint8Array, 'exceljs writeBuffer');
const wb2 = new ExcelJS.Workbook();
await wb2.xlsx.load(buf);
const sheet = wb2.worksheets[0];
assert(sheet && sheet.rowCount >= 2, 'exceljs load');
console.log('   OK');

console.log('4. Загрузка маршрутов и контроллеров');
await import('../routes/auth.js');
await import('../routes/chats.js');
await import('../controllers/authController.js');
await import('../controllers/chatsController.js');
await import('../controllers/bankStatementController.js');
await import('../controllers/moderationController.js');
await import('../middleware/auth.js');
console.log('   OK');

console.log('\n✅ Все проверки пройдены.');
