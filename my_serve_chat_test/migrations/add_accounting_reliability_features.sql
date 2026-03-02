-- Миграция: reliability-фичи для учёта занятий и отчётов
-- 1) timezone пользователя для серверной оценки "сегодня"
-- 2) idempotency ключи для create-операций
-- 3) audit trail бизнес-действий
-- 4) pg_trgm + индекс для быстрого fuzzy-поиска учеников

-- Timezone пользователя (IANA, например Europe/Moscow)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS timezone VARCHAR(64) NOT NULL DEFAULT 'Europe/Moscow';

UPDATE users
SET timezone = 'Europe/Moscow'
WHERE timezone IS NULL OR TRIM(timezone) = '';

-- Таблица idempotency-запросов
CREATE TABLE IF NOT EXISTS idempotency_keys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scope VARCHAR(120) NOT NULL,
    idempotency_key VARCHAR(200) NOT NULL,
    request_hash VARCHAR(128) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'completed')),
    response_status INTEGER,
    response_body JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    expires_at TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP + interval '24 hours'),
    UNIQUE(user_id, scope, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_expires_at ON idempotency_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_idempotency_scope_status ON idempotency_keys(scope, status);

-- Таблица аудита бизнес-событий
CREATE TABLE IF NOT EXISTS audit_events (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    event_type VARCHAR(120) NOT NULL,
    entity_type VARCHAR(120),
    entity_id VARCHAR(120),
    payload JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_events_created_at ON audit_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_events_user_id ON audit_events(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_event_type ON audit_events(event_type);

-- Улучшенный fuzzy-поиск учеников
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_students_name_trgm
ON students
USING gin (LOWER(REPLACE(TRIM(name), 'ё', 'е')) gin_trgm_ops);
