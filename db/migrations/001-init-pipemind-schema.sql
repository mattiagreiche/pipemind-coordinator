-- Pipemind schema — run once on first deploy
-- Uses schema `pipemind` to avoid collision with n8n's own `public` tables.

CREATE SCHEMA IF NOT EXISTS pipemind;

-- ---------------------------------------------------------------
-- Helper: auto-refresh updated_at on any UPDATE
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION pipemind.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- ---------------------------------------------------------------
-- Helper: enforce valid approver role for each content type (CRIT-02)
-- Client-facing drafts (report, qa_reply, welcome) must have a team_lead approver.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION pipemind.approver_role_valid(
    p_content_type TEXT,
    p_approver_discord_id TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_role TEXT;
BEGIN
    SELECT role INTO v_role FROM pipemind.roster WHERE discord_id = p_approver_discord_id;
    IF NOT FOUND THEN RETURN FALSE; END IF;
    IF p_content_type IN ('report', 'qa_reply', 'welcome') THEN
        RETURN v_role = 'team_lead';
    END IF;
    RETURN TRUE;
END;
$$;

-- ---------------------------------------------------------------
-- Helper: block status from transitioning out of a settled state (CRIT-03)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION pipemind.check_status_transition()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status IN ('approved', 'rejected', 'expired') THEN
        RAISE EXCEPTION 'Draft % is already settled (%), cannot transition to %.',
            OLD.draft_id, OLD.status, NEW.status;
    END IF;
    -- Require discord_message_id when approving (MED-04)
    IF NEW.status = 'approved' AND NEW.discord_message_id IS NULL THEN
        RAISE EXCEPTION 'Draft % cannot be approved without a discord_message_id.',
            NEW.draft_id;
    END IF;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------
-- Table: roster
-- Materialized view of /config/roster.json — refreshed every 5 min by Workflow 00.
-- Authoritative source for Discord identity resolution (SC-19).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.roster (
    discord_id          TEXT PRIMARY KEY
                            CHECK (char_length(discord_id) BETWEEN 1 AND 32),
    name                TEXT NOT NULL
                            CHECK (char_length(name) BETWEEN 1 AND 100
                                   AND name ~ '^[\w\s\-''\.]+$'),   -- blocks prompt injection (MED-01)
    role                TEXT NOT NULL CHECK (role IN ('team_lead', 'developer', 'client')),
    clockify_user_id    TEXT,
    discord_channel_id  TEXT,       -- client Q&A channel (populated for client row only)
    source_hash         TEXT,       -- SHA-256 of the roster.json at last sync (HIGH-02)
    last_synced_at      TIMESTAMPTZ,-- set by Workflow 00 on every successful sync (HIGH-02)
    active              BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_roster_touch
BEFORE UPDATE ON pipemind.roster
FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();

-- ---------------------------------------------------------------
-- Table: approval_drafts
-- One row per draft, regardless of outcome. Every irreversible action
-- passes through here (SC-01). Status transitions are immutable once settled.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.approval_drafts (
    draft_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_tag         TEXT NOT NULL,
    content_type        TEXT NOT NULL CHECK (content_type IN ('report', 'qa_reply', 'welcome')),

    -- Draft content. boundary_audit_passed must be TRUE before approval is accepted (CRIT-01).
    draft_text          TEXT NOT NULL,
    edited_text         TEXT,
    boundary_audit_passed BOOLEAN NOT NULL DEFAULT FALSE,   -- set by F-08 audit node in workflow

    status              TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),

    -- Approver must be a team_lead for all client-facing content types (CRIT-02)
    approver_discord_id TEXT NOT NULL
                            REFERENCES pipemind.roster (discord_id),
    -- Function-based check enforces team_lead role for client-facing content
    CONSTRAINT chk_approver_role
        CHECK (pipemind.approver_role_valid(content_type, approver_discord_id)),

    discord_message_id  TEXT,       -- Discord message ID of the approval prompt
    discord_channel_id  TEXT NOT NULL,

    -- context_json: structural metadata only — individual PII keys are blocked (HIGH-03)
    context_json        JSONB
                            CHECK (
                                context_json IS NULL
                                OR (
                                    NOT (context_json ? 'developer_name')
                                    AND NOT (context_json ? 'developer_discord_id')
                                    AND NOT (context_json ? 'commit_count')
                                    AND NOT (context_json ? 'hours_logged')
                                    AND NOT (context_json ? 'clockify_user_id')
                                    AND NOT (context_json ? 'standup_text')
                                    AND NOT (context_json ? 'standup_excerpt')
                                )
                            ),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '48 hours',
    settled_at          TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_drafts_status_expires   ON pipemind.approval_drafts (status, expires_at);
CREATE INDEX IF NOT EXISTS idx_drafts_discord_message  ON pipemind.approval_drafts (discord_message_id);
CREATE INDEX IF NOT EXISTS idx_drafts_approver_status  ON pipemind.approval_drafts (approver_discord_id, status); -- MED-03

-- Immutable status transition + discord_message_id guard (CRIT-03 + MED-04)
CREATE TRIGGER trg_draft_status_immutable
BEFORE UPDATE OF status ON pipemind.approval_drafts
FOR EACH ROW EXECUTE FUNCTION pipemind.check_status_transition();

-- ---------------------------------------------------------------
-- Table: delivered_actions
-- One row per completed irreversible outbound action.
-- Prevents duplicate sends on retry (SC-21).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.delivered_actions (
    action_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id        UUID NOT NULL                           -- MED-02: NOT NULL, every delivery needs an audit trail
                        REFERENCES pipemind.approval_drafts (draft_id),
    action_type     TEXT NOT NULL CHECK (action_type IN ('gmail_send', 'drive_save', 'discord_qa', 'discord_welcome', 'clockify_write')),
    -- Format enforced: <action_type>:<draft_uuid> (HIGH-01, MED-04)
    dedup_key       TEXT NOT NULL UNIQUE
                        CHECK (dedup_key ~ '^(gmail_send|drive_save|discord_qa|discord_welcome|clockify_write):[0-9a-f\-]{36}$'),
    delivered_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- Table: client_welcomed
-- Prevents sending a duplicate welcome to the same client (F-15.3).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.client_welcomed (
    client_discord_id   TEXT PRIMARY KEY
                            REFERENCES pipemind.roster (discord_id) ON DELETE CASCADE, -- LOW-01
    welcomed_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------
-- Table: system_state
-- Global flags checked by every workflow before acting (SC-19).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.system_state (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_system_state_touch
BEFORE UPDATE ON pipemind.system_state
FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();    -- HIGH-04

-- Seed required flag (idempotent — safe to re-run).
INSERT INTO pipemind.system_state (key, value)
VALUES ('roster_valid', 'false')
ON CONFLICT (key) DO NOTHING;
