/**
 * Reconcile the database schema required by the currently deployed backend.
 *
 * This is deliberately additive and safe to re-run. Historical migrations that
 * delete data or remove legacy objects are intentionally excluded. The base
 * database_schema.sql bootstraps an empty database; this script also upgrades
 * an already-created older database to the current application contract.
 */
import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import dotenv from 'dotenv';
import pool from '../db.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, '..');
dotenv.config({ path: join(rootDir, '.env') });

/**
 * Order matters: a migration may alter a table/column created by an earlier
 * migration. Do not put destructive historical migrations in this list.
 */
const RECONCILIATION_MIGRATIONS = [
  // Users and authentication.
  'migrations/add_fcm_token.sql',
  'migrations/add_display_name.sql',
  'migrations/add_token_version.sql',
  'migrations/add_avatar_url.sql',

  // Chats and encryption (server-held key for new chats; legacy key tables are fallback).
  'migrations/add_chat_is_group.sql',
  'migrations/add_chat_roles.sql',
  'migrations/add_chat_folders.sql',
  'migrations/add_custom_chat_folders.sql',
  'migrations/add_chat_shared_key.sql',
  'migrations/add_chat_invites.sql',
  'migrations/add_e2ee_keys.sql',
  'migrations/add_e2ee_key_requests.sql',
  'migrations/add_e2ee_key_versioning.sql',

  // Message columns must precede dependent message tables/indexes.
  'migrations/add_images_to_messages.sql',
  'migrations/add_original_image_url.sql',
  'migrations/add_message_statuses.sql',
  'migrations/add_files_to_messages.sql',
  'migrations/add_message_features.sql',
  'migrations/add_unread_indexes.sql',
  'migrations/add_message_user_deletions.sql',

  // Notifications and moderation.
  'migrations/add_push_devices.sql',
  'migrations/add_user_blocks_and_reports.sql',

  // Students, reports and accounting.
  'migrations/add_students_tables.sql',
  'migrations/add_teacher_students.sql',
  'migrations/add_teacher_students_archived.sql',
  'migrations/add_students_pay_by_bank_transfer.sql',
  'migrations/add_lesson_status_and_makeup.sql',
  'migrations/add_transactions_target_teacher.sql',
  'migrations/add_reports_tables.sql',
  'migrations/add_reports_late_flag.sql',
  'migrations/add_teacher_balance.sql',
  'migrations/add_accounting_reliability_features.sql',
  'migrations/add_report_lessons_unique_lesson.sql',
  'migrations/add_lessons_created_by_date_index.sql',
  'migrations/add_transactions_lesson_created_by_indexes.sql',
  'migrations/add_students_normalized_contact_indexes.sql',
];

// These historical files are intentionally not run automatically:
// - cleanup_password_reset.sql removes legacy data.
// - add_accounting_uniqueness_indexes.sql can alter historical accounting data
//   while resolving duplicates; run it only with an explicit data-migration plan.
// - add_lessons_makeup_origin_unique.sql normalizes historical duplicate makeup
//   links; run it only with an explicit data-migration plan.

const REQUIRED_COLUMNS = {
  users: ['display_name', 'avatar_url', 'fcm_token', 'token_version', 'timezone'],
  chats: ['is_group', 'shared_chat_key', 'current_key_version'],
  chat_users: ['role', 'folder', 'folder_id'],
  messages: [
    'key_version', 'delivered_at', 'edited_at', 'image_url', 'original_image_url',
    'message_type', 'file_url', 'file_name', 'file_size', 'file_mime', 'reply_to_message_id',
  ],
  students: ['pay_by_bank_transfer'],
  teacher_students: ['is_archived', 'archived_at'],
  lessons: ['status', 'is_chargeable', 'origin_lesson_id'],
  transactions: ['lesson_id', 'target_teacher_id'],
  reports: ['is_late'],
};

const REQUIRED_TABLES = [
  'auth_sessions',
  'audit_events',
  'chat_folders',
  'chat_invites',
  'chat_key_requests',
  'chat_keys',
  'content_reports',
  'idempotency_keys',
  'message_forwards',
  'message_locations',
  'message_reactions',
  'message_reads',
  'message_templates',
  'message_user_deletions',
  'pinned_messages',
  'push_devices',
  'teacher_balance_transactions',
  'user_blocks',
];

async function applyOne(relPath) {
  const full = join(rootDir, relPath);
  if (!existsSync(full)) throw new Error(`Missing migration file: ${relPath}`);
  await pool.query(readFileSync(full, 'utf8'));
  console.log('ok', relPath);
}

async function ensureAuthSessionsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS auth_sessions (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      refresh_token_hash TEXT NOT NULL,
      token_version INTEGER NOT NULL DEFAULT 0,
      user_agent TEXT NULL,
      ip TEXT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      expires_at TIMESTAMP NOT NULL,
      revoked_at TIMESTAMP NULL
    );
    CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_active
      ON auth_sessions(user_id, revoked_at, expires_at);
  `);
  console.log('ok auth_sessions');
}

async function verifyContract() {
  const result = await pool.query(`
    SELECT table_name, column_name
      FROM information_schema.columns
     WHERE table_schema = 'public'
  `);
  const columns = new Set(result.rows.map((row) => `${row.table_name}.${row.column_name}`));
  const missing = [];

  for (const table of REQUIRED_TABLES) {
    if (!result.rows.some((row) => row.table_name === table)) missing.push(`table:${table}`);
  }
  for (const [table, names] of Object.entries(REQUIRED_COLUMNS)) {
    for (const name of names) {
      if (!columns.has(`${table}.${name}`)) missing.push(`column:${table}.${name}`);
    }
  }

  if (missing.length > 0) {
    throw new Error(`Database schema contract is incomplete: ${missing.join(', ')}`);
  }
  console.log('schema_contract=ok');
}

async function main() {
  for (const file of RECONCILIATION_MIGRATIONS) await applyOne(file);
  await ensureAuthSessionsTable();
  await verifyContract();
  await pool.end();
}

main().catch(async (error) => {
  console.error('schema reconciliation failed:', error.message);
  await pool.end().catch(() => {});
  process.exit(1);
});
