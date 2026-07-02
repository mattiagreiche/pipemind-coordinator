-- F-06: Unblock Assistance — apply after 005-time-entry-approval.sql
-- Adds unblock_offers tracking table and extends constraint value lists
-- on approval_drafts, delivered_actions, and outreach_log to include
-- the new action types introduced by F-06.

-- ---------------------------------------------------------------
-- Helper: auto-refresh updated_at on any UPDATE
-- Already created in 001; CREATE OR REPLACE is idempotent.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION pipemind.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- ---------------------------------------------------------------
-- Table: unblock_offers
-- One row per (person, day, feature_area) — tracks an in-flight
-- unblock offer through its full state machine (F-06.1–F-06.4).
-- Individual-level — never surfaced upward; no upward escalation
-- is permitted while status is pending, declined, or ignored (F-06.4).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.unblock_offers (
    offer_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    discord_id      TEXT NOT NULL REFERENCES pipemind.roster (discord_id),
    offer_date      DATE NOT NULL,
    feature_area    TEXT NOT NULL
                        CHECK (char_length(feature_area) BETWEEN 1 AND 100
                               AND feature_area ~ '^[A-Za-z0-9 \-_]+$'),
    blocker_source  TEXT NOT NULL CHECK (blocker_source IN ('standup', 'project_signal')),
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                            'pending', 'accepted', 'declined', 'ignored', 'just_talk',
                            'dm_failed',
                            'help_menu_sent', 'colleague_pending', 'colleague_unavailable',
                            'colleague_draft_pending', 'colleague_done',
                            'meeting_pending', 'meeting_draft_pending', 'meeting_done'
                        )),
    offer_count     INTEGER NOT NULL DEFAULT 1,
    dm_channel_id   TEXT,
    draft_id        UUID REFERENCES pipemind.approval_drafts (draft_id),
    responded_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_unblock_offer_person_day_area UNIQUE (discord_id, offer_date, feature_area)
);

DROP TRIGGER IF EXISTS trg_unblock_offers_touch ON pipemind.unblock_offers;
CREATE TRIGGER trg_unblock_offers_touch
BEFORE UPDATE ON pipemind.unblock_offers
FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();

CREATE INDEX IF NOT EXISTS idx_unblock_offers_discord_date
    ON pipemind.unblock_offers (discord_id, offer_date DESC);

CREATE INDEX IF NOT EXISTS idx_unblock_offers_status_date
    ON pipemind.unblock_offers (status, offer_date DESC);

-- ---------------------------------------------------------------
-- Extend outreach_log.outreach_type to include 'unblock_offer'
-- Prior value list (from 003): ('check_in', 'time_log_offer')
-- ---------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE pipemind.outreach_log
        DROP CONSTRAINT IF EXISTS outreach_log_outreach_type_check;
    ALTER TABLE pipemind.outreach_log
        ADD CONSTRAINT outreach_log_outreach_type_check
            CHECK (outreach_type IN ('check_in', 'time_log_offer', 'unblock_offer'));
EXCEPTION WHEN duplicate_object THEN NULL;
       WHEN undefined_object   THEN NULL;
END $$;

-- ---------------------------------------------------------------
-- Extend approval_drafts.content_type to include 'colleague_dm'
-- and 'calendar_event'
-- Prior value list (after 005): ('report', 'qa_reply', 'welcome', 'time_entry')
-- Neither new type is client-facing, so approver_role_valid() already
-- returns TRUE for them — no function change needed.
-- ---------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE pipemind.approval_drafts
        DROP CONSTRAINT IF EXISTS approval_drafts_content_type_check;
    ALTER TABLE pipemind.approval_drafts
        ADD CONSTRAINT approval_drafts_content_type_check
            CHECK (content_type IN (
                'report', 'qa_reply', 'welcome', 'time_entry',
                'colleague_dm', 'calendar_event'
            ));
EXCEPTION WHEN duplicate_object THEN NULL;
       WHEN undefined_object   THEN NULL;
END $$;

-- ---------------------------------------------------------------
-- Extend delivered_actions.action_type to include
-- 'discord_colleague_dm' and 'calendar_event_create'
-- Prior value list (from 001): ('gmail_send', 'drive_save',
--   'discord_qa', 'discord_welcome', 'clockify_write')
-- ---------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE pipemind.delivered_actions
        DROP CONSTRAINT IF EXISTS delivered_actions_action_type_check;
    ALTER TABLE pipemind.delivered_actions
        ADD CONSTRAINT delivered_actions_action_type_check
            CHECK (action_type IN (
                'gmail_send', 'drive_save', 'discord_qa', 'discord_welcome',
                'clockify_write', 'discord_colleague_dm', 'calendar_event_create'
            ));
EXCEPTION WHEN duplicate_object THEN NULL;
       WHEN undefined_object   THEN NULL;
END $$;

-- ---------------------------------------------------------------
-- Extend delivered_actions.dedup_key regex to include
-- 'discord_colleague_dm' and 'calendar_event_create' as valid prefixes
-- Prior regex (from 001):
--   '^(gmail_send|drive_save|discord_qa|discord_welcome|clockify_write):[0-9a-f\-]{36}$'
-- NOTE: Postgres auto-names inline CHECK constraints as <table>_<column>_check.
-- If the constraint was defined inline in 001 without an explicit CONSTRAINT clause,
-- its name is delivered_actions_dedup_key_check — which is what DROP targets below.
-- Verify with: SELECT conname FROM pg_constraint
--   WHERE conrelid = 'pipemind.delivered_actions'::regclass AND contype = 'c';
-- ---------------------------------------------------------------
DO $$
BEGIN
    ALTER TABLE pipemind.delivered_actions
        DROP CONSTRAINT IF EXISTS delivered_actions_dedup_key_check;
    ALTER TABLE pipemind.delivered_actions
        ADD CONSTRAINT delivered_actions_dedup_key_check
            CHECK (dedup_key ~ '^(gmail_send|drive_save|discord_qa|discord_welcome|clockify_write|discord_colleague_dm|calendar_event_create):[0-9a-f\-]{36}$');
EXCEPTION WHEN duplicate_object THEN NULL;
       WHEN undefined_object   THEN NULL;
END $$;
