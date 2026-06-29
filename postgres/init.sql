-- =============================================================================
-- Pipemind Coordination Agent — Postgres init script
-- Run automatically by the postgres container on first start.
-- Idempotent: all statements use IF NOT EXISTS.
-- =============================================================================

-- The database itself is created by the POSTGRES_DB env var before this script
-- runs. The CREATE DATABASE statement below is a no-op safety net for manual
-- runs against an already-initialised cluster.
SELECT 'CREATE DATABASE coordination_agent'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'coordination_agent'
)\gexec

-- Connect to the target database (effective only when run via psql directly;
-- Docker entrypoint already connects to POSTGRES_DB before running this file).
\connect coordination_agent

-- ---------------------------------------------------------------------------
-- drafts
-- Approval gate pattern (SC-01 / F-03).
-- Stores every pending irreversible action awaiting human approval.
-- status: 'pending' | 'approved' | 'rejected' | 'expired' | 'executed'
-- type:   e.g. 'client_report' | 'time_entry' | 'checkin_offer'
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS drafts (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    type                TEXT        NOT NULL,
    content_json        JSONB       NOT NULL,
    approver_discord_id TEXT        NOT NULL,
    status              TEXT        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'executed')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '48 hours')
);

CREATE INDEX IF NOT EXISTS drafts_status_idx      ON drafts (status);
CREATE INDEX IF NOT EXISTS drafts_approver_idx    ON drafts (approver_discord_id);
CREATE INDEX IF NOT EXISTS drafts_expires_at_idx  ON drafts (expires_at);

-- ---------------------------------------------------------------------------
-- project_memory  (Phase 1 — F-14)
-- Key/value store for persistent agent memory: summaries, decisions, context.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_memory (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    key         TEXT        NOT NULL UNIQUE,
    value_json  JSONB       NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS project_memory_key_idx ON project_memory (key);

-- ---------------------------------------------------------------------------
-- roster  (Phase 1 — F-04/F-05/F-06)
-- Authoritative team member list. Loaded from roster.yml at startup; this
-- table is the runtime cache. Never expose individual rows to the client.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS roster (
    discord_id   TEXT        PRIMARY KEY,
    name         TEXT        NOT NULL,
    clockify_id  TEXT,
    active       BOOLEAN     NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- mute_list  (Phase 1 — F-05)
-- Developers who have opted out of proactive check-in messages.
-- Honour strictly — never contact a muted developer proactively (SC-06).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS mute_list (
    discord_id  TEXT        PRIMARY KEY,
    muted_by    TEXT        NOT NULL,
    muted_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- P1 index addition
-- Speeds up draft lookup by developer discord_id for time_entry approval polling
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS drafts_type_approver_status_idx
  ON drafts (type, approver_discord_id, status);
