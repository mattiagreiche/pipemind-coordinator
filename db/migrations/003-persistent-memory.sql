-- Persistent memory store (F-14) — apply after 002-security-hardening.sql
-- Provides project-level continuity across workflow runs.
-- Individual-level data (standup_records) stays behind the F-08 aggregation boundary.

-- ---------------------------------------------------------------
-- Table: project_signals
-- One row per feature area. Aggregated, project-level — safe to
-- surface at any boundary tier. Updated by F-04 (standup ingestion)
-- and F-02 (Q&A). Newer primary signal wins (F-14.5).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.project_signals (
    signal_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_area            TEXT NOT NULL
                                CHECK (
                                    char_length(feature_area) BETWEEN 1 AND 100
                                    AND feature_area ~ '^[A-Za-z0-9 \-_]+$'
                                ),
    status_summary          TEXT NOT NULL
                                CHECK (
                                    char_length(status_summary) BETWEEN 1 AND 2000
                                    AND status_summary NOT SIMILAR TO '%@(everyone|here)%'
                                ),
    has_blocker             BOOLEAN NOT NULL DEFAULT FALSE,
    source                  TEXT NOT NULL
                                CHECK (source IN ('standup', 'qa', 'supplementary', 'manual')),
    last_primary_signal_at  TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One row per feature area; upsert ON CONFLICT (feature_area) DO UPDATE
    CONSTRAINT uq_project_signals_area UNIQUE (feature_area)
);

CREATE TRIGGER trg_project_signals_touch
BEFORE UPDATE ON pipemind.project_signals
FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();

CREATE INDEX IF NOT EXISTS idx_project_signals_updated
    ON pipemind.project_signals (updated_at DESC);

-- ---------------------------------------------------------------
-- Table: standup_records
-- Individual standup updates — one row per person per day.
-- NEVER surfaced upward except to the person themselves (F-14.2, SC-14).
-- Written by F-04. Read by memory-reader only for dev_self purpose.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.standup_records (
    record_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    discord_id      TEXT NOT NULL
                        REFERENCES pipemind.roster (discord_id),
    standup_date    DATE NOT NULL,
    raw_text        TEXT NOT NULL
                        CHECK (char_length(raw_text) BETWEEN 1 AND 4000),
    feature_area    TEXT
                        CHECK (
                            feature_area IS NULL
                            OR (
                                char_length(feature_area) BETWEEN 1 AND 100
                                AND feature_area ~ '^[A-Za-z0-9 \-_]+$'
                            )
                        ),
    has_blocker     BOOLEAN NOT NULL DEFAULT FALSE,
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_standup_person_day UNIQUE (discord_id, standup_date)
);

-- Supports dev_self standup lookup (F-14.2)
CREATE INDEX IF NOT EXISTS idx_standup_discord_date
    ON pipemind.standup_records (discord_id, standup_date DESC);

-- Supports anonymised blocker count for tl_internal (F-14.2)
CREATE INDEX IF NOT EXISTS idx_standup_blocker_date
    ON pipemind.standup_records (has_blocker, standup_date DESC);

-- ---------------------------------------------------------------
-- Table: outreach_log
-- Tracks who the agent contacted and when. Used by F-05 (check-ins)
-- and F-07 (time-logging) to avoid duplicate outreach (SC-21, SC-06).
-- Individual-level — never surfaced upward.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.outreach_log (
    outreach_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    discord_id      TEXT NOT NULL
                        REFERENCES pipemind.roster (discord_id),
    outreach_type   TEXT NOT NULL
                        CHECK (outreach_type IN ('check_in', 'time_log_offer')),
    outreach_date   DATE NOT NULL,
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    draft_id        UUID
                        REFERENCES pipemind.approval_drafts (draft_id),
    response_text   TEXT
                        CHECK (
                            response_text IS NULL
                            OR (
                                char_length(response_text) <= 2000
                                AND response_text NOT SIMILAR TO '%@(everyone|here)%'
                            )
                        ),
    responded_at    TIMESTAMPTZ,

    -- One outreach per type per person per day (prevents duplicate check-ins)
    CONSTRAINT uq_outreach_person_type_day UNIQUE (discord_id, outreach_type, outreach_date)
);

CREATE INDEX IF NOT EXISTS idx_outreach_discord_date
    ON pipemind.outreach_log (discord_id, outreach_date DESC);

-- ---------------------------------------------------------------
-- Table: qa_history
-- Project-level Q&A pairs for continuity (F-02, F-14.1).
-- Question and answer are both project-level — no individual attribution.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipemind.qa_history (
    qa_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_text   TEXT NOT NULL
                        CHECK (char_length(question_text) BETWEEN 1 AND 1000),
    answer_text     TEXT
                        CHECK (answer_text IS NULL OR char_length(answer_text) <= 4000),
    feature_area    TEXT
                        CHECK (
                            feature_area IS NULL
                            OR (
                                char_length(feature_area) BETWEEN 1 AND 100
                                AND feature_area ~ '^[A-Za-z0-9 \-_]+$'
                            )
                        ),
    asked_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    answered_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_qa_asked_at
    ON pipemind.qa_history (asked_at DESC);
