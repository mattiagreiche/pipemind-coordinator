-- F-05: mute state and calendar integration — apply after 003-persistent-memory.sql

-- SC-12: per-person mute state — persists until explicitly reversed
-- muted_at records when the mute was last toggled for audit purposes
ALTER TABLE pipemind.roster
    ADD COLUMN IF NOT EXISTS muted      BOOLEAN     NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS muted_at   TIMESTAMPTZ;

-- L-02: auto-stamp muted_at whenever the muted flag changes
CREATE OR REPLACE FUNCTION pipemind.set_muted_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.muted IS DISTINCT FROM OLD.muted THEN
        NEW.muted_at = now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_roster_set_muted_at
BEFORE UPDATE OF muted ON pipemind.roster
FOR EACH ROW EXECUTE FUNCTION pipemind.set_muted_at();

-- F-05 / SC-06: Google Calendar email for freebusy schedule cross-check
-- Nullable — developers without calendar integration skip the calendar check (SC-18 fail-safe applies)
ALTER TABLE pipemind.roster
    ADD COLUMN IF NOT EXISTS calendar_email TEXT
        CHECK (
            calendar_email IS NULL
            OR calendar_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        );
