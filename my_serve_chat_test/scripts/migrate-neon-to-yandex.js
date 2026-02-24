/**
 * Перенос БД с Neon на Yandex Managed PostgreSQL.
 * Использует DATABASE_URL (Neon) и DATABASE_URL_YANDEX из .env.
 * Запуск: node scripts/migrate-neon-to-yandex.js
 */
import { spawn } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, '..');
dotenv.config({ path: join(rootDir, '.env') });

const SOURCE = process.env.DATABASE_URL;
const TARGET = process.env.DATABASE_URL_YANDEX;

if (!SOURCE) {
  console.error('❌ В .env задайте DATABASE_URL (Neon)');
  process.exit(1);
}
if (!TARGET) {
  console.error('❌ В .env задайте DATABASE_URL_YANDEX (строка подключения к Yandex)');
  process.exit(1);
}

const dumpFile = join(rootDir, `neon_dump_${Date.now()}.sql`);

// Для pg_dump без root.crt используем sslmode=require (Neon с verify-full иначе требует сертификат)
const sourceForDump = SOURCE.replace(/sslmode=verify-full/, 'sslmode=require').replace(/&?channel_binding=\w+/, '');

// Используем pg_dump/psql из PostgreSQL 17, если есть (Neon на PG 17)
const pg17 = '/opt/homebrew/opt/postgresql@17/bin';
const envWithPg17 = { ...process.env, PATH: `${pg17}:${process.env.PATH}` };

function run(cmd, args, env = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: 'inherit', env: { ...envWithPg17, ...env } });
    p.on('close', (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}`))));
  });
}

async function main() {
  console.log('1/2 Дамп с Neon...');
  await run('pg_dump', [sourceForDump, '--no-owner', '--no-acl', '-f', dumpFile]);
  console.log('   Создан:', dumpFile);

  console.log('2/2 Восстановление в Yandex...');
  await run('psql', [TARGET, '-f', dumpFile]);
  console.log('   Готово.');

  console.log('\n✅ Миграция завершена.');
  console.log('   Дамп можно удалить: rm', dumpFile);
  console.log('   На Render замени DATABASE_URL на значение DATABASE_URL_YANDEX и перезапусти сервис.');
}

main().catch((err) => {
  console.error('❌', err.message);
  process.exit(1);
});
