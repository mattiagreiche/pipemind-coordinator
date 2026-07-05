-- F-02.2/F-02.3: when the agent cannot answer a client question confidently, it privately
-- asks one identified, scheduled teammate a single focused question, waits up to 2 hours
-- (same working day), then drafts the client-facing answer from their reply -- or a holding
-- response if no scheduled teammate is found or the deadline passes unanswered.
--
-- Asking the teammate is not itself an irreversible action (matches F-05 check-in DMs, which
-- also skip F-03) -- only the eventual client-facing answer synthesized from the reply goes
-- through the F-03 approval gate as a normal 'qa_reply' draft.

CREATE TABLE IF NOT EXISTS pipemind.teammate_queries (
    query_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_question     TEXT NOT NULL
                            CHECK (char_length(client_question) BETWEEN 1 AND 1000),
    client_channel_id   TEXT NOT NULL,
    feature_area        TEXT NOT NULL
                            CHECK (
                                char_length(feature_area) BETWEEN 1 AND 100
                                AND feature_area ~ '^[A-Za-z0-9 \-_]+$'
                            ),
    asked_discord_id    TEXT NOT NULL
                            REFERENCES pipemind.roster (discord_id),
    asked_dm_channel_id TEXT,

    status              TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'answered', 'timed_out')),

    -- Raw reply text, sanitized only at the point it enters an LLM prompt (matches how
    -- standup_records.raw_text / own_standups are handled elsewhere in this schema).
    reply_text          TEXT
                            CHECK (
                                reply_text IS NULL
                                OR (
                                    char_length(reply_text) <= 2000
                                    AND reply_text NOT SIMILAR TO '%@(everyone|here)%'
                                )
                            ),

    asked_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    deadline_at         TIMESTAMPTZ NOT NULL,  -- computed by the caller: min(asked_at + 2h, EOD_TIME same day)
    responded_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_teammate_queries_touch
BEFORE UPDATE ON pipemind.teammate_queries
FOR EACH ROW EXECUTE FUNCTION pipemind.touch_updated_at();

-- Supports the janitor sweep (status='pending' AND deadline_at <= now())
CREATE INDEX IF NOT EXISTS idx_teammate_queries_status_deadline
    ON pipemind.teammate_queries (status, deadline_at);

-- Supports the reply-capture lookup (asked_discord_id, status='pending')
CREATE INDEX IF NOT EXISTS idx_teammate_queries_discord_status
    ON pipemind.teammate_queries (asked_discord_id, status);
