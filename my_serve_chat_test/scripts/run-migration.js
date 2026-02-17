/**
 * Запуск одной миграции: node scripts/run-migration.js [путь к .sql]
 * Пример: node scripts/run-migration.js migrations/add_chat_folders.sql
 */
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
import pool from '../db.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, '..');

dotenv.config({ path: join(rootDir, '.env') });

async function run() {
  const file = process.argv[2] || 'migrations/add_chat_folders.sql';
  const path = join(rootDir, file);
  const sql = readFileSync(path, 'utf8');
  const statements = sql
    .split(';')
    .map((s) => s.replace(/--[^\n]*/g, '').trim())
    .filter((s) => s.length > 0);
  for (const st of statements) {
    if (st) await pool.query(st + ';');
  }
  console.log('✅ Миграция выполнена:', file);
  process.exit(0);
}

run().catch((err) => {
  console.error('❌ Ошибка миграции:', err.message);
  process.exit(1);
});
