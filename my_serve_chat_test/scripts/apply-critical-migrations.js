/**
 * Apply additive / IF NOT EXISTS migrations that production must have.
 * Safe to re-run. Used by deploy scripts so schema never lags behind code.
 *
 * Usage: node scripts/apply-critical-migrations.js
 */
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
import pool from '../db.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, '..');
dotenv.config({ path: join(rootDir, '.env') });

/** Order matters when later files depend on earlier objects. */
const CRITICAL = [
  'migrations/add_fcm_token.sql',
  'migrations/add_token_version.sql',
  'migrations/add_avatar_url.sql',
  'migrations/add_chat_shared_key.sql',
  'migrations/add_push_devices.sql',
  'migrations/add_message_user_deletions.sql',
  'migrations/add_user_blocks_and_reports.sql',
  'migrations/add_chat_invites.sql',
  'migrations/add_custom_chat_folders.sql',
  // Needs CREATE EXTENSION privilege on Managed PG — run manually if missing:
  // 'migrations/add_accounting_reliability_features.sql',
];

async function applyOne(relPath) {
  const full = join(rootDir, relPath);
  if (!existsSync(full)) {
    console.warn('skip missing', relPath);
    return;
  }
  const sql = readFileSync(full, 'utf8');
  try {
    await pool.query(sql);
    console.log('ok', relPath);
  } catch (error) {
    // Managed PG often blocks CREATE EXTENSION; do not abort the whole deploy.
    if (
      error?.code === '42501' ||
      /permission denied to create extension/i.test(String(error?.message || ''))
    ) {
      console.warn('skip privileged', relPath, error.message);
      return;
    }
    throw error;
  }
}

async function main() {
  for (const file of CRITICAL) {
    await applyOne(file);
  }
  const check = await pool.query(
    `SELECT to_regclass('public.push_devices') AS push_devices`
  );
  console.log('push_devices=', check.rows[0].push_devices);
  process.exit(0);
}

main().catch((err) => {
  console.error('critical migrations failed:', err.message);
  process.exit(1);
});
